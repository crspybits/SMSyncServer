//
//  TwoDeviceBasics.swift
//  Tests
//
//  Created by Christopher Prince on 2/13/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
@testable import SMSyncServer
import SMCoreLib

// TODO: Two clients signed on to the server, with different Google Drive Id's.

// TODO: Master: takes out lock, waits for while, releases lock. Client: Tries to do some server operation, with the same Google Drive Id, while the lock is held by the master.

// Same Google Drive Id's. Server has a file which doesn't yet exist on app/client.
class SMTwoDeviceTestThatServerHasNewFileWorks : TwoDeviceTestCase {
    
    init() {
        super.init(withTestLabel: "Server has new file")
        TestBasics.session.failure = {
            self.failTest("TestBasics.session.failure")
        }
    }
    
    var createFile:(file:AppFile, fileSizeInBytes:Int)!
    var uuidString:String! {
        return self.createFile.file.uuid!
    }
    var fileUUID: NSUUID {
        return NSUUID(UUIDString: self.uuidString)!
    }
    
    var numberUploads:Int = 0
    var numberDownloads:Int = 0
    var device2Checks:Int = 0
    
    // Slave
    var timer:RepeatingTimer?

    // Upload file to server.
    override func master() {
        super.master()
        
        let fileName = "ServerHasNewFile"
        self.createFile = TestBasics.session.createFile(withName: fileName)

        let fileAttributes = SMSyncAttributes(withUUID: self.fileUUID, mimeType: "text/plain", andRemoteFileName: fileName)
    
        SMSyncServer.session.uploadImmutableFile(self.createFile.file.url(), withFileAttributes: fileAttributes)
        SMSyncServer.session.commit()
    }
    
    override func syncServerSingleUploadComplete(uuid uuid:NSUUID) {
        if self.isSlave {
            self.failTest()
        }
        
        self.numberUploads += 1
        
        self.assertIf(self.numberUploads > 1, thenFailAndGiveMessage: "More than one upload")
        self.assertIf(uuid.UUIDString != self.uuidString, thenFailAndGiveMessage: "Unexpected UUID")
    }
    
    override func syncServerCommitComplete(numberOperations numberOperations: Int?) {
        if self.isSlave {
            self.failTest()
        }
        
        Assert.If(numberUploads != 1, thenPrintThisString: "More than one upload")
        TestBasics.session.checkFileSize(self.uuidString, size: self.createFile.fileSizeInBytes) {
            let fileAttr = SMSyncServer.session.fileStatus(self.fileUUID)
            self.assertIf(fileAttr == nil, thenFailAndGiveMessage: "No file attr")
            self.assertIf(fileAttr!.deleted!, thenFailAndGiveMessage: "File was deleted")
            
            self.passTest()
        }
    }
    
    // Receive new file.
    override func slave() {
        super.slave()
        
        // The timer will not be running when created.
        self.timer = RepeatingTimer(interval: 10.0, selector: "checkForDownloads", andTarget: self)
        self.checkForDownloads()
    }
    
    // PRIVATE
    // I'm not sure why but despite the fact that this class inherits from NSObject, I still have to mark this as @objc or I get a crash on the RepeatingTimer init method.
    // See also http://stackoverflow.com/questions/27911479/nstimer-doesnt-find-selector
    @objc func checkForDownloads() {
        Log.msg("Slave: checkForDownloads")
        
        // We'll start it again if we don't get downloads.
        self.timer!.cancel()

        self.device2Checks += 1
        
        if self.device2Checks > 10 {
            failTest("Too many checks")
            return
        }
        
        SMDownloadFiles.session.checkForDownloads()
    }
    
    // Initially, on the slave, there may be no files to download yet-- the master may not yet have uploaded.
    override func syncServerNoFilesToDownload() {
        if self.isMaster {
            self.failTest()
        }
        
        // No downloads ready yet. Start the timer to check for downloads in a while.
        self.timer!.start()
    }
    
    override func syncServerSingleFileDownloadComplete(temporaryLocalFile:NSURL, withFileAttributes attr: SMSyncAttributes) {
        if self.isMaster {
            failTest()
            return
        }
        
        self.numberDownloads += 1
        
        self.assertIf(self.numberDownloads > 1, thenFailAndGiveMessage: "More than one download")
        
        // Create AppFile so it shows up in the local app.
        
        let newFile = AppFile.newObjectAndMakeUUID(true)
        newFile.fileName = attr.remoteFileName
        CoreData.sessionNamed(CoreDataTests.name).saveContext()

        let newURL = FileStorage.urlOfItem(newFile.fileName)

        do {
            try NSFileManager.defaultManager().moveItemAtURL(temporaryLocalFile, toURL: newURL)
        } catch let error {
            self.failTest("Could not move file to \(newURL); error was: \(error)")
        }
    }

    override func syncServerAllDownloadsComplete() {
        if self.isMaster {
            self.failTest()
            return
        }
        
        if self.numberDownloads == 1 {
            self.passTest()
        }
        else {
            self.failTest("Didn't get exactly one download; got: \(self.numberDownloads)")
        }
        
        self.timer!.cancel()
    }
    
    // If the slave has the lock while we're trying to upload, the master will get this called.
    override func syncServerRecovery(progress:SMSyncServerRecovery) {
        if self.isSlave {
            self.failTest()
        }
    }
}

// TODO: Server has a single file which is an updated version of that on app/client.



