# rqq

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

rqq.onError = ?func (x, Error.Error) {

};

rqq.onComplete = ?func (x) {

};

rqq.onDropped = ?func (x) {

};

rqq.add({id=3; some="Hello"});


```
