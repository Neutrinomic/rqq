import Time "mo:base/Time";
import Debug "mo:base/Debug";
import Array "mo:base/Array";
import Error "mo:base/Error";
import RQQ "../src";
import Iter "mo:base/Iter";

actor RQQTest {


    // Test payload types
    public type JobState = {
        id: Nat;
        task: {#before; #after};
    };


    let mem = RQQ.Mem.V1.new<JobState>();
    let rqq = RQQ.RQQ<system, JobState>(mem, null);


    // Configure RQQ dispatch function
    rqq.dispatch := ?(func (state: JobState) : async* () {
       
 
        // Handle each task. We carry the job state through and modify it
        switch(state.task) {
            case(#before) {
                Debug.trap("Before commit trap");
                ignore await mock(state.id);
            };
            case(#after) {
                ignore await mock(state.id);
                Debug.trap("After commit trap");
            };
            
        }

    });


    public func mock(id:Nat) : async Text {
        "Something here " # debug_show(id)
    };


    public query func getStats() : async rqq.Debug.Stats {
        rqq.Debug.getStats();
    };

    public func addMany(num: Nat) : async () {
        for (i in Iter.range(1, num)) {
            let initialState : JobState = {
                id = i;
                task = #after;
            };
            rqq.add<system>(initialState, 100);
        };
    };

    // Add method to start a new job workflow
    public func addJob(id: Nat, priority: Nat32, task: {#before; #after}) : async () {
        let initialState : JobState = {
            id = id;
            task = task;
        };
        rqq.add<system>(initialState, priority);
    };

    var test_flag : Bool = false;

    public func test() : async () {
        let x : [Nat] = [0,1];
        try {
          ignore await mock(0);
         let fail = x[10];
         
        } catch (_e) {} finally {
            test_flag := true;
            Debug.print("!!!!!You will never see this!!!!");
        }
    };

    public func get_test_flag() : async Bool {
        test_flag;
    };

} 