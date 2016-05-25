//
//  TestThatTwoUploadsWork.swift
//  Tests
//
//  Created by Christopher Prince on 2/15/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
@testable import SMSyncServer
import SMCoreLib

// Different Google Id's. Master and slave both upload.
class SMTwoDeviceTestThatTwoUploadsWork : TwoDeviceTestCase {
    
    init() {
        super.init(withTestLabel: "D: 2) Two uploads")
        TestBasics.session.failure = {
            self.failTest("TestBasics.session.failure")
        }
    }
    
    var testFile:TestFile!
    var numberUploads:Int = 0
    
    func uploadFile() {
        let fileName = "TestThatTwoUploadsWork"
        self.testFile = TestBasics.session.createTestFile(fileName)
        SMSyncServer.session.uploadImmutableFile(self.testFile.url, withFileAttributes: self.testFile.attr)
        SMSyncServer.session.commit()
    }
    
    // Upload file to server.
    override func master() {
        super.master()
        self.uploadFile()
    }
    
    override func syncServerShouldSaveDownloads(downloads: [(downloadedFile: NSURL, downloadedFileAttributes: SMSyncAttributes)], acknowledgement: () -> ()) {
    }
    
    override func syncServerShouldDoDeletions(downloadDeletions deletions:[SMSyncAttributes], acknowledgement:()->()) {
    }
    
    override func syncServerModeChange(newMode:SMSyncServerMode) {
    }
    
    override func syncServerEventOccurred(event:SMSyncServerEvent) {
        switch event {
        case .SingleUploadComplete(uuid: let uuid):
            self.numberUploads += 1
            
            self.assertIf(self.numberUploads > 1, thenFailAndGiveMessage: "More than one upload")
            self.assertIf(uuid.UUIDString != self.testFile.uuidString, thenFailAndGiveMessage: "Unexpected UUID")
            
        case .OutboundTransferComplete:
            Assert.If(numberUploads != 1, thenPrintThisString: "More than one upload")
            TestBasics.session.checkFileSize(self.testFile.uuidString, size: self.testFile.sizeInBytes) {
                let fileAttr = SMSyncServer.session.localFileStatus(self.testFile.uuid)
                self.assertIf(fileAttr == nil, thenFailAndGiveMessage: "No file attr")
                self.assertIf(fileAttr!.deleted!, thenFailAndGiveMessage: "File was deleted")
                
                self.passTest()
            }
            
        default:
            Log.special("event: \(event)")
        }
    }
    
    override func slave(dataForSlave dataForSlave: NSData?) {
        super.slave(dataForSlave: dataForSlave)
        self.uploadFile()
    }
}