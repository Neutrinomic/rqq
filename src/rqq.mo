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
import Debug "mo:base/Debug";

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
        MAX_THREADS = 10;
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

        public func add(payload: A, priority: Nat32) : async () {
            let id = getNextId();
            ignore BTree.insert<Nat64, VM.Request<A>>(mem.store, Nat64.compare, getIndex(id, priority), { payload = payload; var retry = 0; var next_try = 0; var error = null; });
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
                let resp = BTree.scanLimit<Nat64, VM.Request<A>>(mem.store, Nat64.compare, 0, start, #bwd, 10);
                
                label search_in for ((id, request) in resp.results.vals()) {
                    if (not condition(request)) continue search_in;
                    ignore BTree.delete(mem.store, Nat64.compare, id);
                    return ?(id, request);
                };
                ignore do ? { start := resp.nextKey! };
                if (resp.results.size() < 10) return null;
            };
            null;
        };

        private func dispatchThread() : async () {
     
                var i = 0;
                let ?dispatchFn = dispatch else return;
                let now = Nat64.fromNat(Int.abs(Time.now()));

                let max_condition : (VM.Request<A>) -> Bool = func(request) : Bool { request.next_try < now };

                var last_tip : Nat64 = ^0;
                label sendloop while (i < settings.MAX_PER_THREAD) { 

                    let ?(id, request) = deleteMaxCondition(max_condition, last_tip) else break sendloop;
                    last_tip := id;
                    try {
                        await* dispatchFn(request.payload);
                        request.error := null;
                        
                    } catch (e) {
                        request.error := ?Error.message(e);
                        if (request.retry > settings.MAX_RETRIES) { 
                            ignore BTree.insert<Nat64, VM.Request<A>>(mem.dropped, Nat64.compare, id, request);
                           
                            ignore do ? {onDropped!(request.payload)};
                            continue sendloop;
                        };

                        // readd it to the queue, but with a lower id
                        request.retry += 1;
                        request.next_try := whenToRetry(request);
                        ignore BTree.insert<Nat64, VM.Request<A>>(mem.store, Nat64.compare,  deprioritizeIndex(id), request);
                    };
        
                    i += 1;
                };

                manageThreads<system>();
        };

        var threads = List.nil<Nat>();

        private func manageThreads<system>() : () {
            let number_of_requests = BTree.size(mem.store);
            let desired_threads = Nat.min(1, Nat.max(number_of_requests / (2*settings.MAX_PER_THREAD), settings.MAX_THREADS));
            let current_threads = List.size(threads);

            if (desired_threads > current_threads) {
                for (i in Iter.range(current_threads, desired_threads - 1)) {
                    let thread_id = Timer.recurringTimer<system>( #seconds(settings.THREAD_INTERVAL_SEC), dispatchThread );
                    threads := List.push(thread_id, threads);
                }
            } else if (desired_threads < current_threads) {
                for (i in Iter.range(current_threads, desired_threads - 1)) {
                    let (opt_thread_id, new_threads) = List.pop(threads);
                    threads := new_threads;
                    ignore do ? {Timer.cancelTimer(opt_thread_id!)};
                }
            };

            
        };

        manageThreads<system>();

        public type Dropped<A> = {
            dropped : [(Nat64, VM.Request<A>)];
            next_key : ?Nat64;
            total : Nat;
        };

        public func getDropped(from : Nat64, limit : Nat) : Dropped<A> {
            let len = Nat.max(limit, 1000);
            let resp = BTree.scanLimit<Nat64, VM.Request<A>>(mem.dropped, Nat64.compare, from, 0, #fwd, len);
            {
                dropped = resp.results;
                next_key = resp.nextKey;
                total = BTree.size(mem.dropped);
            };
        };



        public func clearDropped() {
            BTree.clear(mem.dropped);
        };

      
    };
}