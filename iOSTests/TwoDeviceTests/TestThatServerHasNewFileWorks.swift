//
//  TwoDeviceTestThatServerHasNewFileWorks.swift
//  Tests
//
//  Created by Christopher Prince on 2/13/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
@testable import SMSyncServer
import SMCoreLib

// Same Google Drive Id's. Server has a file which doesn't yet exist on app/client.
class SMTwoDeviceTestThatServerHasNewFileWorks : TwoDeviceTestCase {
    
    init() {
        super.init(withTestLabel: "Server has new file")
        TestBasics.session.failure = {
            self.failTest("TestBasics.session.failure")
        }
    }
    
    // Master
    var testFile:TestFile!
    var numberUploads:Int = 0
    
    // Slave
    var timer:RepeatingTimer?
    var numberDownloads:Int = 0
    var numberDownloadChecks:Int = 0
    
    override func createDataForSlave() -> NSData? {
        let fileName = "ServerHasNewFile"
        self.testFile = TestBasics.session.createTestFile(fileName)
        
        let slaveData = SlaveData()
        slaveData.sizeInBytes = Int32(self.testFile.sizeInBytes)
        return NSKeyedArchiver.archivedDataWithRootObject(slaveData)
    }
    
    // Upload file to server.
    override func master() {
        super.master()
    
        SMSyncServer.session.uploadImmutableFile(self.testFile.url, withFileAttributes: self.testFile.attr)
        SMSyncServer.session.commit()
    }
    
    override func syncServerSingleUploadComplete(uuid uuid:NSUUID) {
        if self.isSlave {
            self.failTest()
        }
        
        self.numberUploads += 1
        
        self.assertIf(self.numberUploads > 1, thenFailAndGiveMessage: "More than one upload")
        self.assertIf(uuid.UUIDString != self.testFile.uuidString, thenFailAndGiveMessage: "Unexpected UUID")
    }
    
    override func syncServerCommitComplete(numberOperations numberOperations: Int?) {
        if self.isSlave {
            self.failTest()
        }
        
        Assert.If(numberUploads != 1, thenPrintThisString: "More than one upload")
        TestBasics.session.checkFileSize(self.testFile.uuidString, size: self.testFile.sizeInBytes) {
            let fileAttr = SMSyncServer.session.localFileStatus(self.testFile.uuid)
            self.assertIf(fileAttr == nil, thenFailAndGiveMessage: "No file attr")
            self.assertIf(fileAttr!.deleted!, thenFailAndGiveMessage: "File was deleted")
            
            self.passTest()
        }
    }
    
    var slaveData: SlaveData?
    
    // Receive new file.
    override func slave(dataForSlave dataForSlave:NSData?) {
        super.slave(dataForSlave: dataForSlave)
        
        Log.msg("slave: dataForSlave: \(dataForSlave)")
        
        self.slaveData = NSKeyedUnarchiver.unarchiveObjectWithData(dataForSlave!) as? SlaveData
        self.assertIf(self.slaveData == nil, thenFailAndGiveMessage: "Got nil data on slave!")
        
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

        self.numberDownloadChecks += 1
        
        if self.numberDownloadChecks > 10 {
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
        
        let path = FileStorage.pathToItem(newFile.fileName)
        let sizeInBytes = FileStorage.fileSize(path)
        self.assertIf(UInt(self.slaveData!.sizeInBytes) != sizeInBytes, thenFailAndGiveMessage: "File size was not that expected")
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



