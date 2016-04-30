//
//  TestThatDownloadDeletionWorks.swift
//  Tests
//
//  Created by Christopher Prince on 4/29/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
@testable import SMSyncServer
import SMCoreLib

/* 
1) Master uploads a file
2) Slave downloads that file (slave needs to be polling to check for downloads; that polling will eventually be changed to a server -> client/slave web socket notification)
3) Master does upload deletion (how to detect when slave has finished downloading?)
4) Slave does download deletion (slave needs to be polling to check for download-deletion; that polling will eventually be changed to a server -> client/slave web socket notification)
*/
class SMTwoDeviceTestThatDownloadDeletionWorks : TwoDeviceTestCase {
    
    init() {
        super.init(withTestLabel: "S: 4) Download deletion works")
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
            TimedCallback.withDuration(SMTwoDeviceTestThatOperationWithLockFails.longWait) {
                SMServerAPI.session.unlock(){ apiResult in
                    self.assertIf(apiResult.error != nil, thenFailAndGiveMessage: "Error releasing lock on master.")
                    self.passTest()
                }
            }
        }
    }
    
    // Try to get lock on slave.
    override func slave(dataForSlave dataForSlave:NSData?) {
        super.slave(dataForSlave: dataForSlave)
        
        // A short wait before the lock to (try to) make sure that master has the lock before we try to obtain it.
        TimedCallback.withDuration(SMTwoDeviceTestThatOperationWithLockFails.shortWait) {
            SMServerAPI.session.lock() { apiResult in
                self.assertIf(apiResult.error == nil, thenFailAndGiveMessage: "Was able to obtain lock on slave!!")
                self.assertIf(apiResult.returnCode != SMServerConstants.rcLockAlreadyHeld, thenFailAndGiveMessage: "Did not get rcLockAlreadyHeld on the slave!!")
                self.passTest()
            }
        }
    }
}