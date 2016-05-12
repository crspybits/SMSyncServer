//
//  TestThatTwoUploadsWithLargerFileWork.swift
//  Tests
//
//  Created by Christopher Prince on 2/15/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
@testable import SMSyncServer
import SMCoreLib

// Different Google Id's. Master and slave both upload a larger file.
class SMTwoDeviceTestThatTwoUploadsWithLargerFileWork : TwoDeviceTestCase {
    
    init() {
        super.init(withTestLabel: "D: 3) Two uploads-- larger file")
        TestBasics.session.failure = {
            self.failTest("TestBasics.session.failure")
        }
    }
    
    var uuidString:String!
    var sizeInBytes:UInt!
    var numberUploads:Int = 0
    
    func uploadFile() {
    
        let file = AppFile.newObjectAndMakeUUID(true)
        file.fileName =  "Kitty.png"
        let remoteFileName = file.fileName!
        CoreData.sessionNamed(CoreDataTests.name).saveContext()

        let url = SMRelativeLocalURL(withRelativePath: file.fileName!, toBaseURLType: .MainBundle)!
        self.uuidString = file.uuid!
        let fileUUID = NSUUID(UUIDString: self.uuidString)!
        let fileAttributes = SMSyncAttributes(withUUID: fileUUID, mimeType: "image/png", andRemoteFileName: remoteFileName)

        self.sizeInBytes = FileStorage.fileSize(url.path!)

        SMSyncServer.session.uploadImmutableFile(url, withFileAttributes: fileAttributes)

        SMSyncServer.session.commit()
    }
    
    // Upload file to server.
    override func master() {
        super.master()
        self.uploadFile()
    }
    
    override func syncServerDownloadsComplete(downloadedFiles:[(NSURL, SMSyncAttributes, SMSyncServerFileDownloadConflict?)], acknowledgement: () -> ()) {
        
    }
    
    override func syncServerClientShouldDeleteFiles(uuids:[(NSUUID, SMSyncServerDownloadDeletionConflict?)], acknowledgement: () -> ()) {
        
    }
    
    override func syncServerModeChange(newMode:SMSyncServerMode) {
        
    }
    
    override func syncServerEventOccurred(event:SMSyncServerEvent) {
        switch event {
        case .SingleUploadComplete(uuid: let uuid):
            self.numberUploads += 1
            
            self.assertIf(self.numberUploads > 1, thenFailAndGiveMessage: "More than one upload")
            self.assertIf(uuid.UUIDString != self.uuidString, thenFailAndGiveMessage: "Unexpected UUID")
            
        case .OutboundTransferComplete:
            Assert.If(numberUploads != 1, thenPrintThisString: "More than one upload")
            TestBasics.session.checkFileSize(self.uuidString, size: Int(self.sizeInBytes)) {
                let fileAttr = SMSyncServer.session.localFileStatus(NSUUID(UUIDString: self.uuidString)!)
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