//
//  TestThatOperationWithLockWorks.swift
//  Tests
//
//  Created by Christopher Prince on 2/22/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
@testable import SMSyncServer
import SMCoreLib

// Master: takes out lock, waits for while, releases lock. Client: Tries to do some server operation, with a different Google Drive Id, while the lock is held by the master.
class SMTwoDeviceTestThatOperationWithLockWorks : TwoDeviceTestCase {
    
    init() {
        super.init(withTestLabel: "D: Operation with lock works")
        TestBasics.session.failure = {
            self.failTest("TestBasics.session.failure")
        }
    }
    
    static let shortWait:Float = 5.0
    static let longWait = shortWait * 5.0
    
    // Take out lock and hold it, for a while.
    override func master() {
        super.master()
    
        SMServerAPI.session.lock() { apiResult in
            self.assertIf(apiResult.error != nil, thenFailAndGiveMessage: "Error obtaining lock on master.")
            TimedCallback.withDuration(SMTwoDeviceTestThatOperationWithLockWorks.longWait) {
                SMServerAPI.session.unlock(){ apiResult in
                    self.assertIf(apiResult.error != nil, thenFailAndGiveMessage: "Error releasing lock on master.")
                }
            }
        }
    }
    
    // Try to get lock on slave.
    override func slave(dataForSlave dataForSlave:NSData?) {
        super.slave(dataForSlave: dataForSlave)
        
        // A short wait before the lock to (try to) make sure that master has the lock before we try to obtain it.
        TimedCallback.withDuration(SMTwoDeviceTestThatOperationWithLockWorks.shortWait) {
            SMServerAPI.session.lock() { apiResult in
                self.assertIf(apiResult.error != nil, thenFailAndGiveMessage: "Error obtaining lock on slave.")
                SMServerAPI.session.unlock(){ apiResult in
                    self.assertIf(apiResult.error != nil, thenFailAndGiveMessage: "Error releasing lock on slave.")
                }
            }
        }
    }
}
