//
//  TestThatUpdatedFileWorks.swift
//  Tests
//
//  Created by Christopher Prince on 2/15/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation

import Foundation
@testable import SMSyncServer
import SMCoreLib

// Server has a single file which is an updated version of that on app/client. Do this in two stages: upload/download a file, then upload/download a new version.
class SMTwoDeviceTestThatUpdatedFileWorks : TwoDeviceTestCase {
    
    init() {
        super.init(withTestLabel: "S: Server has updated file")
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
        let fileName = "TestThatUpdatedFileWorks"
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
    
    let newFileContents = "newFileContents"
    
    override func syncServerSingleUploadComplete(uuid uuid:NSUUID) {
        if self.isSlave {
            self.failTest()
        }
        
        self.numberUploads += 1
        
        self.assertIf(self.numberUploads > 2, thenFailAndGiveMessage: "More than two upload")
        self.assertIf(uuid.UUIDString != self.testFile.uuidString, thenFailAndGiveMessage: "Unexpected UUID")
    }
    
    override func syncServerCommitComplete(numberOperations numberOperations: Int?) {
        if self.isSlave {
            self.failTest()
        }
        
        Assert.If(self.numberUploads > 2, thenPrintThisString: "More than two uploads")
        
        if 1 == self.numberUploads {
            TestBasics.session.checkFileSize(self.testFile.uuidString, size: self.testFile.sizeInBytes) {
                let fileAttr = SMSyncServer.session.localFileStatus(self.testFile.uuid)
                self.assertIf(fileAttr == nil, thenFailAndGiveMessage: "No file attr")
                self.assertIf(fileAttr!.deleted!, thenFailAndGiveMessage: "File was deleted")
                
                do {
                    try self.newFileContents.writeToURL(self.testFile.url, atomically: true, encoding: NSASCIIStringEncoding)
                } catch {
                    self.failTest()
                }
            
                SMSyncServer.session.uploadImmutableFile(self.testFile.url, withFileAttributes: self.testFile.attr)
                SMSyncServer.session.commit()
            }
        }
        else {
             TestBasics.session.checkFileSize(self.testFile.uuidString, size: self.newFileContents.characters.count) {
                let fileAttr = SMSyncServer.session.localFileStatus(self.testFile.uuid)
                self.assertIf(fileAttr == nil, thenFailAndGiveMessage: "No file attr")
                self.assertIf(fileAttr!.deleted!, thenFailAndGiveMessage: "File was deleted")
            
                self.passTest()
            }
        }
    }
    
    // So we know how big the file contents are supposed to be.
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
    
    func singleFileDownloadComplete(temporaryLocalFile:NSURL, withFileAttributes attr: SMSyncAttributes) {
        if self.isMaster {
            failTest()
            return
        }
        
        self.numberDownloads += 1
        
        self.assertIf(self.numberDownloads > 2, thenFailAndGiveMessage: "More than two downloads")
        
        var appFile:AppFile!
        
        let fileURL = FileStorage.urlOfItem(attr.remoteFileName)
        var expectedFileSize:Int32!
        
        if 1 == self.numberDownloads {
            // Create AppFile so it shows up in the local app.
        
            appFile = AppFile.newObjectAndMakeUUID(true)
            appFile.fileName = attr.remoteFileName
            CoreData.sessionNamed(CoreDataTests.name).saveContext()
            
            expectedFileSize = self.slaveData!.sizeInBytes
        }
        else {
            appFile = AppFile.fetchObjectWithUUID(attr.uuid!.UUIDString)
            self.assertIf(nil == appFile, thenFailAndGiveMessage: "Could not find AppFile")
            
            do {
                try NSFileManager.defaultManager().removeItemAtURL(fileURL)
            } catch let error {
                self.failTest("Could not remove file from \(fileURL); error was: \(error)")
            }
        
            expectedFileSize = Int32(self.newFileContents.characters.count)
        }
        
        do {
            try NSFileManager.defaultManager().moveItemAtURL(temporaryLocalFile, toURL: fileURL)
        } catch let error {
            self.failTest("Could not move file to \(fileURL); error was: \(error)")
        }
        
        let path = FileStorage.pathToItem(appFile.fileName)
        let sizeInBytes = FileStorage.fileSize(path)
        self.assertIf(UInt(expectedFileSize) != sizeInBytes, thenFailAndGiveMessage: "File size was not that expected")
    }

    override func syncServerDownloadsComplete(downloadedFiles: [(NSURL, SMSyncAttributes)]) {
        if self.isMaster {
            self.failTest()
            return
        }
                
        for (url, attr) in downloadedFiles {
            self.singleFileDownloadComplete(url, withFileAttributes: attr)
        }
        
        if self.numberDownloads == 2 {
            self.passTest()
        }
        else {
            self.failTest("Didn't get exactly two downloads; got: \(self.numberDownloads)")
        }
        
        self.timer!.cancel()
    }
    
    // If the slave has the lock while we're trying to upload, the master will get this called.
    override func syncServerRecovery(progress:SMClientMode) {
        if self.isSlave {
            self.failTest()
        }
    }
}

