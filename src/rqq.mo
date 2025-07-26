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

module {

    let VM = Ver1;

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
        MAX_RETRIES = 10;
        MIN_RETRY_DELAY_SEC = 6;
        MAX_RETRY_DELAY_SEC = 600;
    };

    public class RQQ<system, A>(
        xmem : MU.MemShell<VM.Mem<A>>,
        opt_settings : ?Settings
    ) {

        let mem = MU.access(xmem);
        let settings = Option.get(opt_settings, DefaultSettings);

        public var onComplete : ?((A) -> ()) = null;
        public var onDropped : ?((A) -> ()) = null;
        public var onError : ?((A, Error.Error) -> ()) = null;
        public var dispatch : ?(A -> async* ()) = null;

        public func add(payload: A, priority: Nat32) : async () {
            let id = getNextId();
            ignore BTree.insert<Nat64, VM.Request<A>>(mem.store, Nat64.compare, getIndex(id, priority), { payload = payload; var retry = 0; var last_try = 0 });
        };

        private func getNextId() : Nat32 {
            let id = mem.next_id;
            mem.next_id += 1;
            if (mem.next_id > 0xFFFFFFFE) mem.next_id := 0;
            id;
        };

        private func getIndex(id : Nat32, priority:Nat32) : Nat64 {
            Nat64.fromNat32(priority) << 32 | Nat64.fromNat32(id);
        };

        private func deprioritizeIndex(idx : Nat64) : Nat64 {
            let priority = idx >> 32;
            let id = idx & 0xFFFFFFFF;
            (priority / 2) << 32 | id;
        };

        private func whenToRetry(request: VM.Request<A>) : Nat64 {
            let last_try = request.last_try;
            let min_delay = settings.MIN_RETRY_DELAY_SEC * 1_000_000_000;
            let max_delay = settings.MAX_RETRY_DELAY_SEC * 1_000_000_000;
            let delay = min_delay + (max_delay - min_delay) * Nat64.fromNat(request.retry);
            last_try + delay;
        };

        private func deleteMaxCondition(condition: (VM.Request<A>) -> Bool, last_tip: Nat64) : ?(Nat64,VM.Request<A>) {

            var start :Nat64 = last_tip;
            label search_out loop {
                let resp = BTree.scanLimit<Nat64, VM.Request<A>>(mem.store, Nat64.compare, start, 0, #bwd, 10);
                label search_in for ((id, request) in resp.results.vals()) {
                    if (not condition(request)) continue search_in;
                    ignore BTree.delete(mem.store, Nat64.compare, id);
                    return ?(id, request);
                };
                ignore do ? { start := resp.nextKey! };
            };
            null;
        };

        private func dispatchThread() : async () {
                var i = 0;
                let ?dispatchFn = dispatch else return;

                let now = Nat64.fromNat(Int.abs(Time.now()));

                let max_condition : (VM.Request<A>) -> Bool = func(request) : Bool { request.last_try != 0 and (now < whenToRetry(request)) };

                var last_tip : Nat64 = ^0;
                label sendloop while (i < settings.MAX_PER_THREAD) { 

                    let ?(id, request) = deleteMaxCondition(max_condition, last_tip) else break sendloop;
                    last_tip := id;

                    try {
                        await* (with timeout=20) dispatchFn(request.payload);
                        ignore do ? {onComplete!(request.payload)};
                    } catch (e) {
                        ignore do ? {onError!(request.payload, e)};

                        if (request.retry > settings.MAX_RETRIES) { 
                            ignore do ? {onDropped!(request.payload)};
                            continue sendloop;
                        };

                        // readd it to the queue, but with a lower id
                        request.retry += 1;
                        request.last_try := now;
                        ignore BTree.insert<Nat64, VM.Request<A>>(mem.store, Nat64.compare, deprioritizeIndex(id), request);
                    };
        
                    i += 1;
                };
        };

        var threads = List.nil<Nat>();

        private func launchThreads<system>() : () {
            let number_of_requests = BTree.size(mem.store);
            let desired_threads = Nat.min(1, Nat.max(number_of_requests / settings.MAX_PER_THREAD, settings.MAX_THREADS));
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
            }
            
        };

        launchThreads<system>();


    };
}