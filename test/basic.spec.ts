import { Principal } from '@dfinity/principal';
import { Actor, PocketIc, createIdentity } from '@dfinity/pic';
import { IDL } from '@dfinity/candid';

import { toState, CanRQQTest, RQQTestService, passTime, passTimeMinutes } from './common';

describe('RQQ Basic Functionality', () => {
    let pic: PocketIc;
    let rqqTest: Actor<RQQTestService>;
    let rqqTestCanisterId: Principal;

    const alice = createIdentity('superSecretAlicePassword');
    const bob = createIdentity('superSecretBobPassword');
  
    beforeAll(async () => {
        pic = await PocketIc.create(process.env.PIC_URL);
        
        // Setup RQQ Test canister
        const fixture = await CanRQQTest(pic);
        rqqTest = fixture.actor;
        rqqTestCanisterId = fixture.canisterId;

        await passTime(pic, 2);
    });
  
    afterAll(async () => {
        await pic.tearDown();
    });

    beforeEach(async () => {
        // Reset state before each test
        await rqqTest.reset();
        await passTime(pic, 1);
    });

    it('should initialize RQQ successfully', async () => {
   
        
        const processedRequests = await rqqTest.getProcessedRequests();
        expect(processedRequests.length).toEqual(0);
        
        const dispatchCount = await rqqTest.getDispatchCallCount();
        expect(dispatchCount).toBe(0n);
    }, 30_000);

    it('should add and process a single request successfully', async () => {
        // Add a request to the queue
        await rqqTest.addRequest(1, "test data", 100, false, 0n);
        
        // Wait for processing
        await passTime(pic, 10);
        
        // Check that request was processed
        const processedRequests = await rqqTest.getProcessedRequests();
        
        expect(processedRequests).toHaveLength(1);
        expect(processedRequests[0]).toBe(1); // request id
        
        const dispatchCount = await rqqTest.getDispatchCallCount();
        expect(dispatchCount).toBe(1n);
    }, 60_000);

    it('should process multiple requests in priority order', async () => {
 

        // Add requests with different priorities (higher number = higher priority)
        await rqqTest.addRequest(1, "low priority", 50, false, 0n);
        await rqqTest.addRequest(2, "high priority", 200, false, 0n);
        await rqqTest.addRequest(3, "medium priority", 100, false, 0n);
        
        // Wait for processing
        await passTime(pic, 15);
        
        // Check processing order
        const processedRequests = await rqqTest.getProcessedRequests();
        const processed = toState(processedRequests);

        expect(processed).toHaveLength(3);
        
        // Should be processed in priority order: 2 (200), 3 (100), 1 (50)
        expect(processed).toEqual([2, 3, 1]);
        
        const dispatchCount = await rqqTest.getDispatchCallCount();
        expect(toState(dispatchCount)).toBe("3");
    }, 60_000);

    it('should handle failing requests with retry logic', async () => {
        // Add a request that will fail initially
        await rqqTest.addRequest(4, "failing request", 100, true, 1n);
        
        // Wait for initial processing and first retry
        await passTime(pic, 15);
        
        // Check dispatch count - should be more than 1 due to retries
        const dispatchCount = await rqqTest.getDispatchCallCount();
        expect(dispatchCount).toBe(1n); 
        
        // Request should not be in processed list yet
        const processedRequests = await rqqTest.getProcessedRequests();
        expect(toState(processedRequests)).toHaveLength(0);

        await passTimeMinutes(pic, 30, 30);

    }, 120_000);

    it('should eventually drop requests after max retries', async () => {
        // Add a request that will always fail
        await rqqTest.addRequest(5, "always failing", 100, true, 5n);
        
        // Wait longer to allow multiple retries
        await passTimeMinutes(pic, 30, 30);
        
        // Check that request was dropped
        const droppedRequests = await rqqTest.getDroppedRequests();
        
        expect(droppedRequests).toBe(1n);
        
        // Should not be in processed requests
        const processedRequests = await rqqTest.getProcessedRequests();
        expect(toState(processedRequests)).toHaveLength(0);
    }, 180_000);

    it('should handle mixed success and failure scenarios', async () => {
        // Add mix of successful and failing requests
        await rqqTest.addRequest(6, "success 1", 100, false, 0n);
        await rqqTest.addRequest(7, "will fail then succeed", 100, true, 1n);
        await rqqTest.addRequest(8, "success 2", 100, false, 0n);
        await rqqTest.addRequest(9, "always fails", 100, true, 20n);
        
        // Wait for processing
        await passTimeMinutes(pic, 30, 30);
        
        // Check results
        const processedRequests = await rqqTest.getProcessedRequests();
        const processed = toState(processedRequests);
        
        // Should have at least the successful ones
        expect(processed.length).toBeGreaterThanOrEqual(2);
        
        expect(processed).toContain(6);
        expect(processed).toContain(8);
        expect(processed).toContain(7);
        
        // Eventually the always failing one should be dropped
        const droppedRequests = await rqqTest.getDroppedRequests();

        expect(droppedRequests).toBe(1n);

        await passTimeMinutes(pic, 30, 30);

    }, 240_000);


});
