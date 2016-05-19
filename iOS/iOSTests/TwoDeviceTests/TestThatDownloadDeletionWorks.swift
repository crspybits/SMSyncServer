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
4) Slave gets download deletion (slave needs to be polling to check for download-deletion; that polling will eventually be changed to a server -> client/slave web socket notification)
*/
class SMTwoDeviceTestThatDownloadDeletionWorks : TwoDeviceTestCase {
    
    init() {
        super.init(withTestLabel: "S: 4) Download deletion works")
        TestBasics.session.failure = {
            self.failTest("TestBasics.session.failure: Download deletion works")
        }
    }
    
    // Master
    var testFile:TestFile!
    var numberUploads:Int = 0
    var deletionPhase = false
    
    // Slave
    var timer:RepeatingTimer?
    var numberDownloads = 0
    var numberDownloadDeletions = 0
    var numberDownloadChecks = 0
    
    override func createDataForSlave() -> NSData? {
        let fileName = "TestThatDownloadDeletionWorks"
        self.testFile = TestBasics.session.createTestFile(fileName)
        
        let slaveData = SlaveData()
        slaveData.sizeInBytes = Int32(self.testFile.sizeInBytes)
        return NSKeyedArchiver.archivedDataWithRootObject(slaveData)
    }
    
    static let shortWait:Float = 10.0
    
    override func master() {
        super.master()
    
        // 1) Master uploads a file
        SMSyncServer.session.uploadImmutableFile(self.testFile.url, withFileAttributes: self.testFile.attr)
        SMSyncServer.session.commit()
        
        // 3) Master does upload deletion (how to detect when slave has finished downloading?)
        TimedCallback.withDuration(SMTwoDeviceTestThatDownloadDeletionWorks.shortWait) {
            self.deletionPhase = true
            SMSyncServer.session.deleteFile(self.testFile.uuid)
            SMSyncServer.session.commit()
        }
    }
    
    override func slave(dataForSlave dataForSlave:NSData?) {
        super.slave(dataForSlave: dataForSlave)
        
        self.timer = RepeatingTimer(interval: 1.0, selector: #selector(checkForDownloads), andTarget: self)
        self.timer!.start()
    }

    @objc private func checkForDownloads() {
        Log.msg("Slave: checkForDownloads")
        
        // We'll start it again if we don't get downloads.
        self.timer!.cancel()

        self.numberDownloadChecks += 1
        
        if self.numberDownloadChecks > 30 {
            failTest("Too many checks")
            return
        }
        
        SMSyncControl.session.nextSyncOperation()
    }
    
    override func syncServerShouldSaveDownloads(downloads: [(downloadedFile: NSURL, downloadedFileAttributes: SMSyncAttributes)], acknowledgement: () -> ()) {
        if self.isMaster {
            self.failTest()
            return
        }
        
        self.assertIf(downloads.count != 1, thenFailAndGiveMessage: "Didn't get exactly one download")
        self.numberDownloads = 1
        
        acknowledgement()
    }

    override func syncServerShouldDoDeletions(downloadDeletions deletions:[NSUUID], acknowledgement:()->()) {
        if self.isMaster {
            self.failTest()
            return
        }
        
        self.assertIf(deletions.count != 1, thenFailAndGiveMessage: "Didn't get exactly one download-deletion")
        self.numberDownloadDeletions = 1
        
        acknowledgement()
    }
    
    override func syncServerModeChange(newMode:SMSyncServerMode) {
        Log.msg("Mode change occurred: \(newMode); self.isMaster: \(self.isMaster)")

        if self.isSlave {
            switch newMode {
            case .Idle:
                if self.numberDownloadDeletions == 1 && self.numberDownloads == 1 {
                    self.passTest()
                }
                else {
                    self.timer!.start()
                }
            
            default:
                break
            }
        }
    }
    
    override func syncServerEventOccurred(event:SMSyncServerEvent) {
        Log.msg("Event occurred: \(event); self.isMaster: \(self.isMaster)")

        if self.isMaster {
            switch event {
            case .LockAlreadyHeld:
                TimedCallback.withDuration(5.0) {
                    SMSyncControl.session.nextSyncOperation()
                }
                
            case .DeletionsSent(let uuids):
                self.assertIf(!self.deletionPhase, thenFailAndGiveMessage: "Not in deletion phase")
                self.assertIf(uuids.count != 1, thenFailAndGiveMessage: "Didn't delete exactly one file")
                self.assertIf(testFile.uuidString != uuids[0].UUIDString, thenFailAndGiveMessage: "Didn't get same UUID")
                self.passTest()
                
            case .SingleUploadComplete(let uuid):
                self.assertIf(self.deletionPhase, thenFailAndGiveMessage: "In deletion phase")
                self.assertIf(testFile.uuidString != uuid.UUIDString, thenFailAndGiveMessage: "Didn't get same UUID")
            
            case .OutboundTransferComplete:
                TestBasics.session.checkFileSize(testFile.uuidString, size: testFile.sizeInBytes) {
                    let fileAttr = SMSyncServer.session.localFileStatus(self.testFile.uuid)
                    self.assertIf(fileAttr == nil, thenFailAndGiveMessage: "fileAttr is nil")
                }
            
            default:
                break
            }
        }
    }
}