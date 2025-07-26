import { Principal } from '@dfinity/principal';
import { resolve } from 'node:path';
import { Actor, PocketIc, createIdentity } from '@dfinity/pic';
import { IDL } from '@dfinity/candid';
import { _SERVICE as RQQTestService, idlFactory as RQQTestIdlFactory, init as rqqTestInit } from './build/rqq.idl.js';
//@ts-ignore
import { toState } from "@infu/icblast";

export const RQQ_TEST_WASM_PATH = resolve(__dirname, "./build/rqq.wasm");

export { toState };

export async function CanRQQTest(pic: PocketIc) {
    const fixture = await pic.setupCanister<RQQTestService>({
        idlFactory: RQQTestIdlFactory,
        wasm: RQQ_TEST_WASM_PATH,
        arg: IDL.encode(rqqTestInit({ IDL }), []),
    });

    return fixture;
}

export { RQQTestService, RQQTestIdlFactory, rqqTestInit };

// Helper function to wait for time to pass in tests
export async function passTime(pic: PocketIc, seconds: number) {
    for (let i = 0; i < seconds; i++) {
        await pic.advanceTime(1000); // 1 second
        await pic.tick(2);
    }
}

// 
export async function passTimeMinutes(pic: PocketIc, minutes: number, times:number) {
    for (let i = 0; i < times; i++) {
        await pic.advanceTime(minutes * 60 * 1000); // 1 minute
        await pic.tick(1);
    };
}

// Helper function to wait longer periods for retry testing
export async function passRetryTime(pic: PocketIc, retryCount: number) {
    // RQQ default retry delays: MIN=6s, MAX=600s
    // Calculate expected delay based on retry count
    const minDelay = 6;
    const maxDelay = 600;
    const maxRetries = 10;
    
    const progress = Math.min(retryCount / maxRetries, 1);
    const delay = minDelay + ((maxDelay - minDelay) * progress);
    
    // Add some buffer time
    const waitTime = Math.ceil(delay + 2);
    
    console.log(`Waiting ${waitTime} seconds for retry ${retryCount}`);
    
    for (let i = 0; i < waitTime; i++) {
        await pic.advanceTime(1000);
        await pic.tick(2);
    }
} 