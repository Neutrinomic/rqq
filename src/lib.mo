import BTree "mo:stableheapbtreemap/BTree";
import Nat64 "mo:base/Nat64";
import Time "mo:base/Time";
import Int "mo:base/Int";
import Error "mo:base/Error";
import MU "mo:mosup";
import Ver1 "./memory/v1";
import Timer "mo:base/Timer";
import Nat "mo:base/Nat";
import Iter "mo:base/Iter";
import List "mo:base/List";
import Option "mo:base/Option";
import Dbg "mo:base/Debug";
import Vector "mo:vector";
import Array "mo:base/Array";

module {

    public module Mem {
        public let V1 = Ver1;
    };

    let VM = Mem.V1;




    public type Settings = {
        THREAD_INTERVAL_SEC : Nat;
        MAX_PER_THREAD : Nat;
        MAX_THREADS : Nat;
        MAX_RETRIES : Nat;
        MIN_RETRY_DELAY_SEC : Nat64;
        MAX_RETRY_DELAY_SEC : Nat64;
    };

    public let DefaultSettings : Settings = {
        THREAD_INTERVAL_SEC = 6;
        MAX_PER_THREAD = 10;
        MAX_THREADS = 20;
        MAX_RETRIES = 3;
        MIN_RETRY_DELAY_SEC = 6;
        MAX_RETRY_DELAY_SEC = 60;
    };

    public class RQQ<system, A>(
        xmem : MU.MemShell<VM.Mem<A>>,
        opt_settings : ?Settings
    ) {

        let mem = MU.access(xmem);
        let settings = Option.get(opt_settings, DefaultSettings);

        public var onDropped : ?((A) -> ()) = null;
        public var dispatch : ?(A -> async* ()) = null;

        public func add<system>(payload: A, priority: Nat32) : () {
            let id = getNextId();
            ignore BTree.insert<Nat64, VM.Request<A>>(mem.store, Nat64.compare, getIndex(id, priority), { payload = payload; var retry = 0; var next_try = 0; var error = null; });
            if (not Thread.isRunning()) Thread.runnerStart<system>();
        };

        private func getNextId() : Nat32 {
            let id = mem.next_id;
            mem.next_id -= 1;
            if (mem.next_id == 0) mem.next_id := 0xFFFFFFFE;
            id;
        };
    
        private func getIndex(id : Nat32, priority:Nat32) : Nat64 {
            Nat64.fromNat32(priority) << 32 | Nat64.fromNat32(id);
        };

        private func deprioritizeIndex(idx : Nat64) : Nat64 {
            let priority = idx >> 32;
            let id = idx & 0xFFFFFFFF;
            ((priority / 2) << 32) | id;
        };

        private func whenToRetry(request: VM.Request<A>) : Nat64 {
            let now = Nat64.fromNat(Int.abs(Time.now()));
            let min_delay = settings.MIN_RETRY_DELAY_SEC * 1_000_000_000;
            let max_delay = settings.MAX_RETRY_DELAY_SEC * 1_000_000_000;
            let retry = Nat64.fromNat(request.retry);
            let max_retries = Nat64.fromNat(settings.MAX_RETRIES);
            
            let delay = if (max_retries == 0) {
                max_delay
            } else {
                min_delay + ((max_delay - min_delay) * retry) / max_retries
            };

            now + delay;
        };

        private func deleteMaxCondition(condition: (VM.Request<A>) -> Bool, last_tip: Nat64) : ?(Nat64,VM.Request<A>) {

            var start :Nat64 = last_tip;
            label search_out loop {
                let resp = BTree.scanLimit<Nat64, VM.Request<A>>(mem.store, Nat64.compare, 0, start, #bwd, 30);
                
                label search_in for ((id, request) in resp.results.vals()) {
                    if (not condition(request)) continue search_in;
                     ignore BTree.delete(mem.store, Nat64.compare, id);
                    return ?(id, request);
                };

                if (resp.nextKey == null) break search_out;
                ignore do ? { start := resp.nextKey! };
            };
            null;
        };

        private func dispatchThread() : async () {
             
                let ?dispatchFn = dispatch else return;
                let now = Nat64.fromNat(Int.abs(Time.now()));

                let max_condition : (VM.Request<A>) -> Bool = func(request) : Bool { request.next_try < now };

                var last_tip : Nat64 = ^0;
                
                label sendloop for (i in Iter.range(0, settings.MAX_PER_THREAD)) { 
                    let ?(id, request) = deleteMaxCondition(max_condition, last_tip) else return;
                    last_tip := id;
                    let status = {var success = false; var caught = false;};
                    try {
                        await* dispatchFn(request.payload);
                        request.error := null;
                        mem.total_processed += 1;
                        status.success := true;
                    } catch (e) {
                        request.error := ?Error.message(e);
                        mem.total_errors += 1;
                        if (request.retry > settings.MAX_RETRIES) { 
                            ignore BTree.insert<Nat64, VM.Request<A>>(mem.dropped, Nat64.compare, id, request);
                            mem.total_dropped += 1;
                            ignore do ? {onDropped!(request.payload)};
                            continue sendloop;
                        };

                        request.retry += 1;
                        request.next_try := whenToRetry(request);
                        ignore BTree.insert<Nat64, VM.Request<A>>(mem.store, Nat64.compare,  deprioritizeIndex(id), request);
                        status.caught := true;
                    } finally {
                        if (not status.success and not status.caught) {
                            request.error := ?("Uncachable error in dispatch code");
                            mem.total_errors += 1;
                            mem.total_dropped += 1;
                            ignore BTree.insert<Nat64, VM.Request<A>>(mem.dropped, Nat64.compare, id, request);
                        };

                    };
                };

        };


        var thread_runner :Bool = false;
        var threads : Nat = 0;

        module Thread {


            public func isRunning() : Bool {
                thread_runner;
            };

            public func runnerStart<system>() : () {
                thread_runner := true;
                ignore Timer.setTimer<system>( #seconds(0), run );
            };

            public func runnerStop() : () {
                thread_runner := false;
            };

            public func run<system>() : async () {
                
                let number_of_requests = BTree.size(mem.store);
                let desired_threads = Nat.min((number_of_requests + settings.MAX_PER_THREAD - 1) / settings.MAX_PER_THREAD, settings.MAX_THREADS);
                if (desired_threads == 0) {
                    threads := 0;
                    thread_runner := false;
                    return;
                };
                threads := desired_threads;
                var i = 0;

                var running = List.nil<() -> async ()>();
                while (i < desired_threads) {
                    try {
                        running := List.push(dispatchThread, running);
                    } catch (e) {
                        Dbg.print("Uncachable error promise! " # Error.message(e));
                    };
                    i += 1;
                };


                // Wait all in parallel
                for (fn in List.toIter(running)) {
                    try {
                        await fn();
                    } catch (e) {
                        Dbg.print("Uncachable error! " # Error.message(e));
                    };
                };
             
                // Loop
                ignore Timer.setTimer<system>( #seconds(1), run );
            };

      

         };


        public module Debug {
                public type Stats = {
                    requests: Nat;
                    threads: Nat;
                    dropped: Nat;
                    total_processed: Nat;
                    total_dropped: Nat;
                    total_errors: Nat;
                };

                public func getStats() : Stats {
                    {
                        requests = BTree.size(mem.store);
                        threads = threads;
                        dropped = BTree.size(mem.dropped);
                        total_processed = mem.total_processed;
                        total_dropped = mem.total_dropped;
                        total_errors = mem.total_errors;
                    };
                };


                public type Dropped<A> = {
                    dropped : [(Nat64, RequestShared<A>)];
                    next_key : ?Nat64;
                    total : Nat;
                };

                public func getDropped(from : Nat64, limit : Nat) : Dropped<A> {
                    let len = Nat.max(limit, 1000);
                    let resp = BTree.scanLimit<Nat64, VM.Request<A>>(mem.dropped, Nat64.compare, from, ^0, #fwd, len);
                    {
                        dropped = Array.map<(Nat64, VM.Request<A>), (Nat64, RequestShared<A>)>(resp.results, func(x) {
                            (x.0, {
                                payload = x.1.payload;
                                retry = x.1.retry;
                                next_try = x.1.next_try;
                                error = x.1.error;
                            });
                        });
                        next_key = resp.nextKey;
                        total = BTree.size(mem.dropped);
                    };
                };
                public type RequestShared<A> = {
                    payload : A;
                    retry : Nat;
                    next_try : Nat64;
                    error : ?Text;
                };
                public type Requests<A> = {
                    requests : [(Nat64, RequestShared<A>)];
                    next_key : ?Nat64;  
                    total : Nat;
                };

                public func getRequests(from : Nat64, limit : Nat) : Requests<A> {
                    let resp = BTree.scanLimit<Nat64, VM.Request<A>>(mem.store, Nat64.compare, from, ^0, #fwd, limit);
                    {
                        requests = Array.map<(Nat64, VM.Request<A>), (Nat64, RequestShared<A>)>(resp.results, func(x) {
                            (x.0, {
                                payload = x.1.payload;
                                retry = x.1.retry;
                                next_try = x.1.next_try;
                                error = x.1.error;
                            });
                        });
                        next_key = resp.nextKey;
                        total = BTree.size(mem.store);
                    };
                };

                public func clearDropped() {
                    BTree.clear(mem.dropped);
                };

        };


      
    };
}