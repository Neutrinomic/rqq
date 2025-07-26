import Time "mo:base/Time";
import Debug "mo:base/Debug";
import Array "mo:base/Array";
import Error "mo:base/Error";
import RQQ "../src/rqq";

actor RQQTest {

    // Test payload types
    public type TestPayload = {
        id: Nat32;
        data: Text;
        shouldFail: Bool;
        var failureCount: Nat;
    };

    // RQQ setup (now only takes one type parameter)
    let mem = RQQ.Mem.V1.new<TestPayload>();
    let rqq = RQQ.RQQ(mem, null);

    // Track processed requests for testing
    private stable var processedRequests : [Nat32] = [];
    private stable var dispatchCallCount : Nat = 0;
    private stable var droppedRequests : [TestPayload] = [];

    let some = actor("nzsmr-6iaaa-aaaal-qsnea-cai") : actor {
        non_existent : () -> async ()
    };

    // Configure RQQ dispatch function
    rqq.dispatch := ?(func (payload: TestPayload) : async* () {
        dispatchCallCount += 1;
        
       
        // Simulate processing logic
        if (payload.shouldFail and payload.failureCount != 0) {
            payload.failureCount -= 1;
            await some.non_existent();
        };
        
        
        // Simulate successful processing - just record the processed request ID
        processedRequests := Array.append(processedRequests, [payload.id]);
    });

    // Configure dropped request handler
    rqq.onDropped := ?(func (payload: TestPayload) {
        Debug.print("dropped: " # debug_show(payload.id));
        droppedRequests := Array.append(droppedRequests, [payload]);
    });

    // Public interface for tests
    public func addRequest(id: Nat32, data: Text, priority: Nat32, shouldFail: Bool, failureCount: Nat) : async () {
        let payload : TestPayload = {
            id = id;
            data = data;
            shouldFail = shouldFail;
            var failureCount = failureCount;
        };
        await rqq.add(payload, priority);
    };

    public query func getProcessedRequests() : async [Nat32] {
        processedRequests
    };

    public query func getDispatchCallCount() : async Nat {
        dispatchCallCount
    };

    public query func getDroppedRequests() : async Nat {
        droppedRequests.size()
    };


    // Test utility functions
    public query func getTime() : async Int {
        Time.now()
    };

    public func reset() : async () {
        processedRequests := [];
        dispatchCallCount := 0;
        droppedRequests := [];
        rqq.clearDropped();
    };
} 