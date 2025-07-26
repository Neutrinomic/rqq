# RQQ – Retryable Priority Request Queue in Motoko
RQQ is a retryable, priority-based, time-threaded request queue implementation for the Internet Computer, written in Motoko. It helps manage background tasks that might fail and need retries, with support for configurable retry backoff, priority handling, and dynamic threading.

## 🚀 Features
Priority Queue based on BTree with support for FIFO within the same priority

Retry logic with exponential-like backoff and customizable retry limits

Automatic thread scaling based on queue size

Optional event hooks: on success, failure, and dropped

Dispatch isolation via async star (async*) functions

## 🧵 Thread Behavior
Threads run periodically to dispatch jobs:

Each thread picks up to MAX_PER_THREAD tasks.

Threads call dispatch(payload) (must be defined).

If the task traps or throws, it is retried with:

Halved priority (so it moves lower in the queue)

Updated retry count and next_try timestamp

If retries exceed MAX_RETRIES, it's dropped.

Threads are dynamically scaled:

More threads are created if the queue grows.

Idle threads are canceled if the queue shrinks.



## Install
```
mops add rqq
```

## Usage
```motoko
import RQQ "mo:rqq";

type Custom = {
    id: Nat;
    some : Text;
}

stable let rqq_mem = RQQ.Mem.V1.new<Custom>();
let rqq = RQQ.RQQ<system, Custom>(rqq_mem, null);

rqq.dispatch = ?func (x) : async* () {
    await service.call(x.id, x.some);
};

rqq.onDropped = ?func (x) {

};

rqq.add({id=3; some="Hello"});


```
