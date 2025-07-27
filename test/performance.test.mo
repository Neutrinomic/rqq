import Time "mo:base/Time";
import Debug "mo:base/Debug";
import Array "mo:base/Array";
import Error "mo:base/Error";
import Float "mo:base/Float";
import Int "mo:base/Int";
import RQQ "../src/rqq";

actor PerformanceTest {

    public type PerformancePayload = {
        id: Nat32;
        batch_id: Nat32;
        processing_time: Nat; // Simulated processing time in milliseconds
    };

    // Track performance metrics
    private stable var processedItems : [PerformancePayload] = [];
    private stable var processingStartTimes : [Int] = [];
    private stable var processingEndTimes : [Int] = [];
    private stable var throughputData : [(Int, Nat)] = []; // (timestamp, items_processed_count)

    let mem = RQQ.Mem.V1.new<PerformancePayload>();
    
    // High-performance settings
    let performanceSettings : RQQ.Settings = {
        THREAD_INTERVAL_SEC = 1;     // Very fast processing
        MAX_PER_THREAD = 20;         // Large batches
        MAX_THREADS = 5;             // Multiple threads
        MAX_RETRIES = 2;
        MIN_RETRY_DELAY_SEC = 1;
        MAX_RETRY_DELAY_SEC = 5;
    };
    
    let rqq = RQQ.RQQ<system, PerformancePayload>(mem, ?performanceSettings);

    // Configure dispatch for performance tracking
    rqq.dispatch := ?(func (payload: PerformancePayload) : async* () {
        let startTime = Time.now();
        processingStartTimes := Array.append(processingStartTimes, [startTime]);
        
        // Simulate processing time
        await simulateWork(payload.processing_time);
        
        let endTime = Time.now();
        processingEndTimes := Array.append(processingEndTimes, [endTime]);
        processedItems := Array.append(processedItems, [payload]);
        
        // Track throughput every 10 items
        if (processedItems.size() % 10 == 0) {
            throughputData := Array.append(throughputData, [(endTime, processedItems.size())]);
        };
    });

    // Test: High-volume sequential processing
    public func testHighVolumeSequential() : () {
        // Add 100 items quickly
        var i : Nat32 = 1000;
        while (i < 1100) {
            rqq.add({
                id = i; 
                batch_id = 1; 
                processing_time = 10 // 10ms simulated work
            }, 100);
            i += 1;
        };
    };

    // Test: Multiple priority levels with high volume
    public func testMultiPriorityHighVolume() : () {
        // Add items with varying priorities
        var i : Nat32 = 2000;
        while (i < 2200) {
                         let priority : Nat32 = if (i % 3 == 0) 200 else if (i % 2 == 0) 150 else 100;
            rqq.add({
                id = i; 
                batch_id = 2; 
                processing_time = 5
            }, priority);
            i += 1;
        };
    };

    // Test: Burst processing capability
    public func testBurstProcessing() : () {
        // Add a large burst of items all at once
        var i : Nat32 = 3000;
        while (i < 3500) {
            rqq.add({
                id = i; 
                batch_id = 3; 
                processing_time = 1 // Minimal processing time
            }, 100);
            i += 1;
        };
    };

    // Test: Mixed processing times
    public func testMixedProcessingTimes() : () {
        var i : Nat32 = 4000;
        while (i < 4050) {
            let processing_time = if (i % 5 == 0) 100 else if (i % 3 == 0) 50 else 10;
            rqq.add({
                id = i; 
                batch_id = 4; 
                processing_time = processing_time
            }, 100);
            i += 1;
        };
    };

    // Test: Thread scaling under load
    public func testThreadScaling() : () {
        // Start with small load
        var i : Nat32 = 5000;
        while (i < 5010) {
            rqq.add({id = i; batch_id = 5; processing_time = 20}, 100);
            i += 1;
        };
        
        // Then add larger load to trigger thread scaling
        while (i < 5100) {
            rqq.add({id = i; batch_id = 5; processing_time = 20}, 100);
            i += 1;
        };
    };

    // Test: Memory usage with large queue
    public func testLargeQueueMemory() : () {
        // Add many items to test memory handling
        var i : Nat32 = 6000;
        while (i < 7000) {
            rqq.add({
                id = i; 
                batch_id = 6; 
                processing_time = 50
            }, 100);
            i += 1;
        };
    };

    // Simulate work by busy waiting
    private func simulateWork(milliseconds: Nat) : async () {
        let start = Time.now();
        let delay_ns = milliseconds * 1_000_000;
        while (Time.now() - start < delay_ns) {
            // Simulate CPU work
        };
    };

    // Performance measurement functions
    public query func getProcessedCount() : async Nat {
        processedItems.size()
    };

    public query func getThroughputData() : async [(Int, Nat)] {
        throughputData
    };

    public query func getProcessingTimes() : async [Int] {
        if (processingStartTimes.size() != processingEndTimes.size()) {
            return [];
        };
        
        var times : [Int] = [];
        var i = 0;
        while (i < processingStartTimes.size()) {
            let duration = processingEndTimes[i] - processingStartTimes[i];
            times := Array.append(times, [duration]);
            i += 1;
        };
        times
    };

    public query func getAverageProcessingTime() : async Float {
        if (processingStartTimes.size() != processingEndTimes.size() or processingStartTimes.size() == 0) {
            return 0.0;
        };
        
                var total : Int = 0;
         var i = 0;
         while (i < processingStartTimes.size()) {
             let duration = Int.abs(processingEndTimes[i] - processingStartTimes[i]);
             total += duration;
             i += 1;
         };
         Float.fromInt(total) / Float.fromInt(processingStartTimes.size())
    };

    public query func getProcessedItemsByBatch(batch_id: Nat32) : async [PerformancePayload] {
        Array.filter(processedItems, func(item: PerformancePayload) : Bool {
            item.batch_id == batch_id
        })
    };

    public func reset() : async () {
        processedItems := [];
        processingStartTimes := [];
        processingEndTimes := [];
        throughputData := [];
    };

    // Wait for processing to complete
    public func waitForProcessing(target_count: Nat, timeout_seconds: Nat) : async Bool {
        let start = Time.now();
        let timeout_ns = timeout_seconds * 1_000_000_000;
        
        while (processedItems.size() < target_count and (Time.now() - start) < timeout_ns) {
            await simulateWork(100); // Wait 100ms between checks
        };
        
        processedItems.size() >= target_count
    };

    // Performance analysis helpers
    public query func getProcessingStats() : async {
        total_processed: Nat;
        average_time_ns: Float;
        max_time_ns: Int;
        min_time_ns: Int;
    } {
        if (processingStartTimes.size() != processingEndTimes.size() or processingStartTimes.size() == 0) {
            return {
                total_processed = 0;
                average_time_ns = 0.0;
                max_time_ns = 0;
                min_time_ns = 0;
            };
        };

        var total : Int = 0;
                 var max_time = Int.abs(processingEndTimes[0] - processingStartTimes[0]);
         var min_time = max_time;
        var i = 0;
        
                 while (i < processingStartTimes.size()) {
             let duration = Int.abs(processingEndTimes[i] - processingStartTimes[i]);
             total += duration;
             if (duration > max_time) max_time := duration;
             if (duration < min_time) min_time := duration;
             i += 1;
         };

        {
            total_processed = processingStartTimes.size();
            average_time_ns = Float.fromInt(total) / Float.fromInt(processingStartTimes.size());
            max_time_ns = max_time;
            min_time_ns = min_time;
        }
    };
} 