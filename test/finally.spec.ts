import { Principal } from '@dfinity/principal';
import { Actor, PocketIc, createIdentity } from '@dfinity/pic';
import { IDL } from '@dfinity/candid';

import { toState, CanFinallyTest, FinallyTestService, passTime, passTimeMinutes } from './common';

describe('RQQ Finally', () => {
    let pic: PocketIc;
    let finallyTest: Actor<FinallyTestService>;
    let finallyTestCanisterId: Principal;

    const alice = createIdentity('superSecretAlicePassword');
    const bob = createIdentity('superSecretBobPassword');
  
    beforeAll(async () => {
        pic = await PocketIc.create(process.env.PIC_URL);
        
        // Setup Advanced Test canister
        const fixture = await CanFinallyTest(pic);
        finallyTest = fixture.actor;
        finallyTestCanisterId = fixture.canisterId;

        await passTime(pic, 2);
    });
  
    afterAll(async () => {
        await pic.tearDown();
    });

//    it(`Check finally works`, async () => {

//         try { await finallyTest.test();} catch (_e) {}  
//         try { await finallyTest.test();} catch (_e) {}
//         try { await finallyTest.test();} catch (_e) {}

//         let flag = await finallyTest.get_test_flag();
//         console.log("flag", flag);
//         expect(flag).toBe(true);
//    });


//     it('add one task failing before commit', async () => {
//         await finallyTest.addJob(BigInt(1), 100, {after:null});
        

//         await passTime(pic, 20);
        
//         let stats = await finallyTest.getStats();
//         console.log(toState(stats));

//         expect(stats.total_errors).toBe(1n);
//         expect(stats.total_processed).toBe(0n);
//         expect(stats.total_dropped).toBe(1n);
//         expect(stats.requests).toBe(0n);
        
//     }, 180_000);


    it('add one task failing before commit', async () => {
        await finallyTest.addMany(4n);


        await passTime(pic, 5);
        
        let stats = await finallyTest.getStats();
        console.log(toState(stats));

        expect(stats.requests).toBe(0n);
        expect(stats.total_dropped).toBe(4n);
        expect(stats.total_errors).toBe(4n);
        expect(stats.total_processed).toBe(0n);
        
        
    }, 180_000);

}); 