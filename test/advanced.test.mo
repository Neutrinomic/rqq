import Time "mo:base/Time";
import Debug "mo:base/Debug";
import Array "mo:base/Array";
import Error "mo:base/Error";
import RQQ "../src";
import Iter "mo:base/Iter";

actor RQQTest {

    private stable var finishedJobs : [Text] = [];

    // Test payload types
    public type JobState = {
        id: Nat;
        var task: {
            #get_data;
            #do_work;
            #post_work;
        };
        var data: ?Text;
        var fail_simulation: Nat;
    };

    // Shareable version without var fields
    public type JobStateShared = {
        id: Nat;
        task: {
            #get_data;
            #do_work;
            #post_work;
        };
        data: ?Text;
        fail_simulation: Nat;
    };

    let mem = RQQ.Mem.V1.new<JobState>();
    let rqq = RQQ.RQQ<system, JobState>(mem, null);


    let some = actor("nzsmr-6iaaa-aaaal-qsnea-cai") : actor {
        non_existent : () -> async ()
    };

    // Configure RQQ dispatch function
    rqq.dispatch := ?(func (state: JobState) : async* () {
       
        // Simulate fail every first task attempt
        if (state.fail_simulation != 0) {
            state.fail_simulation -= 1;
            await some.non_existent();
        } else {
            state.fail_simulation := 1;
        };
        
        // Handle each task. We carry the job state through and modify it
        switch(state.task) {
            case(#get_data) {
                state.data := ?(await get_data(state.id));
                state.task := #do_work;
                rqq.add<system>(state, 100);
            };
            case(#do_work) {
                state.data := ?(await do_work(state.id));
                state.task := #post_work;
                rqq.add<system>(state, 100);
            };
            case(#post_work) {
                let postwork = await post_work(state.id);
                finishedJobs := Array.append(finishedJobs, [postwork]);
            };
        }

    });


    public func get_data(id:Nat) : async Text {
        "Something here " # debug_show(id)
    };

    public func do_work(id:Nat) : async Text {
        "Another thing here " # debug_show(id)
    };

    public func post_work(id:Nat) : async Text {
        "Postwork here " # debug_show(id)
    };

    public query func getDoneJobs() : async [Text] {
        finishedJobs;
    };

    public func addManyTasks() : async () {
        for (i in Iter.range(1, 1000)) {
            rqq.add<system>({id = i; var task = #get_data; var data = null; var fail_simulation = 1}, 100);
        };
    };

    public query func getStats() : async rqq.Debug.Stats {
        rqq.Debug.getStats();
    };

    // Add method to start a new job workflow
    public func addJob(id: Nat, priority: Nat32) : async () {
        let initialState : JobState = {
            id = id;
            var task = #get_data;
            var data = null;
            var fail_simulation = 1; // Will fail once then succeed
        };
        rqq.add<system>(initialState, priority);
    };

    // Reset method for testing
    public func reset() : async () {
        finishedJobs := [];
    };

} 