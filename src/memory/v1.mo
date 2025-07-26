import MU "mo:mosup";
import BTree "mo:stableheapbtreemap/BTree";

module {
 
 

    public type Mem<A,B> = {
        store : BTree.BTree<Nat64, Request<A,B>>;
        dropped : BTree.BTree<Nat64, Request<A,B>>;
        var next_id : Nat32;
    };

    public func new<A,B>() : MU.MemShell<Mem<A,B>> = MU.new<Mem<A,B>>(
            {
                store = BTree.init<Nat64, Request<A,B>>(?32);
                dropped = BTree.init<Nat64, Request<A,B>>(?16);
                var next_id = 0xFFFFFFFE;
            }
        );

    public type Request<A,B> = {
        payload : A;
        var retry : Nat;
        var next_try : Nat64;
        var result : ?B;
        var error : ?Text;
    };
}; 