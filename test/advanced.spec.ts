import { Principal } from '@dfinity/principal';
import { Actor, PocketIc, createIdentity } from '@dfinity/pic';
import { IDL } from '@dfinity/candid';

import { toState, CanAdvancedTest, AdvancedTestService, passTime, passTimeMinutes } from './common';

describe('RQQ Advanced Workflow', () => {
    let pic: PocketIc;
    let advancedTest: Actor<AdvancedTestService>;
    let advancedTestCanisterId: Principal;

    const alice = createIdentity('superSecretAlicePassword');
    const bob = createIdentity('superSecretBobPassword');
  
    beforeAll(async () => {
        pic = await PocketIc.create(process.env.PIC_URL);
        
        // Setup Advanced Test canister
        const fixture = await CanAdvancedTest(pic);
        advancedTest = fixture.actor;
        advancedTestCanisterId = fixture.canisterId;

        await passTime(pic, 2);
    });
  
    afterAll(async () => {
        await pic.tearDown();
    });

    beforeEach(async () => {
        // Reset state before each test
        await advancedTest.reset();
        await passTime(pic, 1);
    });

    it('should initialize advanced RQQ successfully', async () => {
        const doneJobs = await advancedTest.getDoneJobs();
        expect(doneJobs.length).toEqual(0);
    }, 30_000);

    it('should process a complete job workflow: get_data -> do_work -> post_work', async () => {
        // Add a job to start the workflow
        await advancedTest.addJob(BigInt(1), 100);
        
        // Wait for processing through all stages
        // Each stage fails once then succeeds, so we need to wait for retries
        await passTimeMinutes(pic, 5, 10);
        
        // Check that job completed the full workflow
        const doneJobs = await advancedTest.getDoneJobs();
        const jobs = toState(doneJobs);
        
        expect(jobs).toHaveLength(1);
        expect(jobs[0]).toBe("Postwork here 1");
    }, 180_000);

    it('should handle multiple jobs concurrently', async () => {
        // Add multiple jobs with different priorities
        await advancedTest.addJob(BigInt(1), 100);
        await advancedTest.addJob(BigInt(2), 200); // Higher priority
        await advancedTest.addJob(BigInt(3), 50);  // Lower priority
        
        // Wait for all jobs to complete their workflows
        await passTimeMinutes(pic, 5, 15);
        
        // Check that all jobs completed
        const doneJobs = await advancedTest.getDoneJobs();
        const jobs = toState(doneJobs);
        
        expect(jobs).toHaveLength(3);
        
        // Should contain all three jobs (order may vary due to priority and retry timing)
        expect(jobs).toContain("Postwork here 1");
        expect(jobs).toContain("Postwork here 2");
        expect(jobs).toContain("Postwork here 3");
    }, 300_000);

    it('should handle job failures and retries correctly', async () => {
        // Add a job and check intermediate progress
        await advancedTest.addJob(BigInt(1), 100);
        
        // Wait a short time - job should be in progress but not complete due to failures
        await passTimeMinutes(pic, 1, 5);
        
        let doneJobs = await advancedTest.getDoneJobs();
        let jobs = toState(doneJobs);
        
        // Should not be complete yet due to retry delays
        expect(jobs).toHaveLength(0);
        
        // Wait longer for full completion
        await passTimeMinutes(pic, 5, 10);
        
        doneJobs = await advancedTest.getDoneJobs();
        jobs = toState(doneJobs);
        
        // Should now be complete
        expect(jobs).toHaveLength(1);
        expect(jobs[0]).toBe("Postwork here 1");
    }, 240_000);

    it('should process jobs with different IDs correctly', async () => {
        // Add jobs with specific IDs to test data flow
        await advancedTest.addJob(BigInt(42), 100);
        await advancedTest.addJob(BigInt(99), 100);
        
        // Wait for completion
        await passTimeMinutes(pic, 5, 15);
        
        const doneJobs = await advancedTest.getDoneJobs();
        const jobs = toState(doneJobs);
        
        expect(jobs).toHaveLength(2);
        expect(jobs).toContain("Postwork here 42");
        expect(jobs).toContain("Postwork here 99");
    }, 300_000);

    it('should handle rapid job additions', async () => {
        // Add multiple jobs quickly
        for (let i = 1; i <= 5; i++) {
            await advancedTest.addJob(BigInt(i), 100);
        }
        
        // Wait for all to complete
        await passTimeMinutes(pic, 5, 20);
        
        const doneJobs = await advancedTest.getDoneJobs();
        const jobs = toState(doneJobs);
        
        expect(jobs).toHaveLength(5);
        
        // Check all jobs completed
        for (let i = 1; i <= 5; i++) {
            expect(jobs).toContain(`Postwork here ${i}`);
        }
    }, 400_000);

    it('should maintain job state through workflow stages', async () => {
        // This test verifies that the job state is properly maintained
        // through get_data -> do_work -> post_work transitions
        
        await advancedTest.addJob(BigInt(123), 100);
        
        // Wait for completion
        await passTimeMinutes(pic, 5, 15);
        
        const doneJobs = await advancedTest.getDoneJobs();
        const jobs = toState(doneJobs);
        
        expect(jobs).toHaveLength(1);
        // The final result should contain the ID that was passed through all stages
        expect(jobs[0]).toBe("Postwork here 123");
        await passTimeMinutes(pic, 55, 55);
    }, 300_000);

    it('should handle many jobs correctly', async () => {
        const statsBefore = await advancedTest.getStats();
        expect(statsBefore.requests).toBe(0n);
        expect(statsBefore.threads).toBe(0n);
        expect(statsBefore.dropped).toBe(0n);
        expect(statsBefore.total_processed).toBe(39n);

        await advancedTest.addManyTasks();
        await passTime(pic, 600);
        const stats = await advancedTest.getStats();
        console.log(toState(stats));

        expect(stats.total_errors).toBe(1226n);
        expect(stats.requests).toBe(999n);
        expect(stats.threads).toBe(20n);
        expect(stats.dropped).toBe(0n);
        expect(stats.total_processed).toBe(227n);



        await passTime(pic, 3000);
        const stats3 = await advancedTest.getStats();

        console.log(toState(stats3));
        expect(stats3.requests).toBe(0n);
        expect(stats3.threads).toBe(0n);
        expect(stats3.dropped).toBe(0n);
        expect(stats3.total_processed).toBe(3039n);
        expect(stats3.total_dropped).toBe(0n);
        expect(stats3.total_errors).toBe(3039n);

    }, 300_000);


}); 