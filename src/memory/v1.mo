import MU "mo:mosup";
import BTree "mo:stableheapbtreemap/BTree";

module {
 
 

    public type Mem<A> = {
        store : BTree.BTree<Nat64, Request<A>>;
        dropped : BTree.BTree<Nat64, Request<A>>;
        var next_id : Nat32;
    };

    public func new<A>() : MU.MemShell<Mem<A>> = MU.new<Mem<A>>(
            {
                store = BTree.init<Nat64, Request<A>>(?32);
                dropped = BTree.init<Nat64, Request<A>>(?16);
                var next_id = 0xFFFFFFFE;
            }
        );

    public type Request<A> = {
        payload : A;
        var retry : Nat;
        var next_try : Nat64;
        var error : ?Text;
    };
}; 