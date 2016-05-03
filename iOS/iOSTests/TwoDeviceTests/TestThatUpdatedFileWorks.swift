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
        super.init(withTestLabel: "S: 2) Server has updated file")
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
    
    override func syncServerDownloadsComplete(downloadedFiles:[(NSURL, SMSyncAttributes)], acknowledgement: () -> ()) {
        if self.isMaster {
            self.failTest()
            return
        }
                
        for (url, attr) in downloadedFiles {
            self.singleFileDownloadComplete(url, withFileAttributes: attr)
        }
        
        if self.numberDownloads == 1 {
            // We are expecting one more download.
            self.timer!.start()
        }
        else if self.numberDownloads == 2 {
            // On the slave, we'll get one file downloaded each time.
            self.passTest()
        }
        else if self.numberDownloads > 2 {
            self.failTest("Got more than two downloads: \(self.numberDownloads)")
        }
        
        acknowledgement()
    }
    
    override func syncServerModeChange(newMode:SMSyncServerMode) {
        switch newMode {
        case .Idle, .Synchronizing, .NetworkNotConnected:
            break
            
        case .NonRecoverableError(let error):
            self.failTest("We got a non-recoverable error: \(error)")
        case .InternalError(let error):
            self.failTest("We got an internal error: \(error)")
        case .ClientAPIError(let error):
            self.failTest("We got an client api error: \(error)")
        }
    }
    
    override func syncServerEventOccurred(event:SMSyncServerEvent) {
        Log.special("event: \(event)")
        
        switch event {
        case .SingleUploadComplete(uuid: let uuid):
            if self.isSlave {
                self.failTest()
            }
            
            self.numberUploads += 1
            
            self.assertIf(self.numberUploads > 2, thenFailAndGiveMessage: "More than two upload")
            self.assertIf(uuid.UUIDString != self.testFile.uuidString, thenFailAndGiveMessage: "Unexpected UUID")
            
        case .OutboundTransferComplete:
            self.commitComplete()
               
        case .NoFilesToDownload, .LockAlreadyHeld:
            // Initially, on the slave, there may be no files to download yet-- the master may not yet have uploaded. Not an error to get this event on the master, because in SMSyncControl we normally check for downloads to get the lock.
            if self.isSlave {
                if self.numberDownloads < 2 {
                    // Start the timer to check for additional downloads in a while.
                    self.timer!.start()
                }
            }
            else {
                switch event {
                case .LockAlreadyHeld:
                    TimedCallback.withDuration(5.0) {
                        SMSyncControl.session.nextSyncOperation()
                    }
                    
                default:
                    break
                }
            }
            
        default:
            break
        }
    }
    
    let masterWaitTime:Float = 30.0
    
    func commitComplete() {
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
            
                // Give the slave time to download the first file version.
                TimedCallback.withDuration(self.masterWaitTime) {
                    SMSyncServer.session.uploadImmutableFile(self.testFile.url, withFileAttributes: self.testFile.attr)
                    SMSyncServer.session.commit()
                }
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
        
        // The timer will not be running when created. The divided by factor is just to ensure the timer interval for the slave is quite a bit smaller than the waiting interval of the master.
        self.timer = RepeatingTimer(interval: self.masterWaitTime/10.0, selector: #selector(SMTwoDeviceTestThatUpdatedFileWorks.checkForDownloads), andTarget: self)
        self.checkForDownloads()
    }
    
    // I'm not sure why but despite the fact that this class inherits from NSObject, I still have to mark this as @objc or I get a crash on the RepeatingTimer init method.
    // See also http://stackoverflow.com/questions/27911479/nstimer-doesnt-find-selector
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
            // First download. Create AppFile so it shows up in the local app.
        
            appFile = AppFile.newObjectAndMakeUUID(false)
            appFile.uuid = attr.uuid.UUIDString
            appFile.fileName = attr.remoteFileName
            CoreData.sessionNamed(CoreDataTests.name).saveContext()
            
            expectedFileSize = self.slaveData!.sizeInBytes
        }
        else {
            // Second download. We should have already created the AppFile.
            appFile = AppFile.fetchObjectWithUUID(attr.uuid!.UUIDString)
            self.assertIf(nil == appFile, thenFailAndGiveMessage: "Could not find AppFile: uuid: \(attr.uuid!.UUIDString)")
            
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
        self.assertIf(UInt(expectedFileSize) != sizeInBytes, thenFailAndGiveMessage: "File size: \(sizeInBytes) was not that expected: \(expectedFileSize); self.numberDownloads= \(self.numberDownloads)")
    }
}

