//
//  TestBaseClass.swift
//  NetDb
//
//  Created by Christopher Prince on 1/12/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

// SETUP: (1) Server must be running, (2) Typically before running the test(s), you have to first (a) delete the app, then (b) build and launch the app and ensure the user is signed in. And then, (c) stop the app, and run the test.

// TODO: TimedCallback.withDuration is used to wait for user sign-in, but can now be replaced below with a call to a sign in completion handler. This should speed up testing.

import XCTest
// The @testable notation lets us access "internal" classes within our project.
@testable import SMSyncServer
@testable import Tests
import SMCoreLib

class BaseClass: XCTestCase {
    var initialDelayBeforeFirstTest:NSTimeInterval = 20
    let minServerResponseTime:NSTimeInterval = 15
    var extraServerResponseTime:Double = 0
    
    typealias progressCallback = (progress:SMSyncServerRecovery)->()
    // If you give this, then progressCallbacks is not used.
    var singleProgressCallback:progressCallback?
    var progressSequenceNumber = 0
    var progressCallbacks:[progressCallback]!
    
    typealias commitCompleteCallback = (numberUploads:Int?)->()
    var commitCompleteSequenceNumber = 0
    var commitCompleteCallbacks:[commitCompleteCallback]!

    typealias singleUploadCallback = (uuid:NSUUID)->()
    var singleUploadSequenceNumber = 0
    var singleUploadCallbacks:[singleUploadCallback]!

    typealias deletionCallback = (uuids:[NSUUID])->()
    var deletionSequenceNumber = 0
    var deletionCallbacks:[deletionCallback]!

    typealias downloadCallback = (localFile:NSURL, attr: SMSyncAttributes)->()
    var downloadSequenceNumber = 0
    var downloadCallbacks:[downloadCallback]!

    typealias noDownloadsCallback = ()->()
    var noDownloadsSequenceNumber = 0
    var noDownloadsCallbacks:[noDownloadsCallback]!
    
    typealias allDownloadsCompleteCallback = ()->()
    var allDownloadsCompleteSequenceNumber = 0
    var allDownloadsCompleteCallbacks:[allDownloadsCompleteCallback]!

    typealias errorCallback = ()->()
    var errorSequenceNumber = 0
    var errorCallbacks:[errorCallback]!
    
    override func setUp() {
        super.setUp()

        SMSyncServer.session.autoCommit = false
        SMSyncServer.session.delegate = self
        
        self.extraServerResponseTime = 0
        self.commitCompleteSequenceNumber = 0
        self.commitCompleteCallbacks = [commitCompleteCallback]()
        self.errorCallbacks = [errorCallback]()
        self.progressCallbacks = [progressCallback]()
        self.singleUploadCallbacks = [singleUploadCallback]()
        self.deletionCallbacks = [deletionCallback]()
        self.downloadCallbacks = [downloadCallback]()
        self.allDownloadsCompleteCallbacks = [allDownloadsCompleteCallback]()
        self.noDownloadsCallbacks = [noDownloadsCallback]()
        self.singleProgressCallback = nil
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func waitUntilSyncServerUserSignin(completion:()->()) {
        TimedCallback.withDuration(Float(self.initialDelayBeforeFirstTest)) {
            self.initialDelayBeforeFirstTest = 0.0
            completion()
        }
    }
    
    func waitForExpectations() {
        // [1]. Also needed to add in delay here. Note: This that calling waitForExpectationsWithTimeout within the TimedCallback does *not* work-- XCTest takes this to mean the test succeeded.
        self.waitForExpectationsWithTimeout(self.minServerResponseTime + self.initialDelayBeforeFirstTest + self.extraServerResponseTime, handler: nil)
    }
    
    func makeNewFile(withFileName fileName: String) -> AppFile {
        let file = AppFile.newObjectAndMakeUUID(true)
        file.fileName = fileName
        
        let path = FileStorage.pathToItem(file.fileName)
        NSFileManager.defaultManager().createFileAtPath(path, contents: nil, attributes: nil)

        CoreData.sessionNamed(CoreDataTests.name).saveContext()
        
        return file
    }
    
    func createFile(withName fileName: String) -> (file:AppFile, fileSizeInBytes:Int) {
        let file = self.makeNewFile(withFileName: fileName)
        let fileContents:NSString = fileName + "123" // sample data
        let fileSizeBytes = fileContents.length
        
        do {
            try fileContents.writeToURL(file.url(), atomically: true, encoding: NSASCIIStringEncoding)
        } catch {
            XCTFail("Failed to write file: \(error)!")
        }
        
        return (file, fileSizeBytes)
    }
        
    // Make sure the file size we got on cloud storage was what we expected.
    func checkFileSize(uuid:String, size:Int, finish:()->()) {
        SMServerAPI.session.getFileIndex() { (fileIndex, error) in
            if error == nil {
                let result = fileIndex!.filter({
                    $0.uuid.UUIDString == uuid && $0.sizeBytes == Int32(size)
                })
                if result.count == 1 {
                    finish()
                }
                else {
                    Log.msg("Did not find expected \(size) bytes for uuid \(uuid)")
                    XCTFail()
                }
            }
            else {
                XCTFail()
            }
        }
    }
}

extension BaseClass : SMSyncServerDelegate {
    // Expect this to be called first for the recovery tests.
    func syncServerRecovery(progress:SMSyncServerRecovery) {
        if nil == self.singleProgressCallback {
            let sequenceNumber = self.progressSequenceNumber++
            self.progressCallbacks[sequenceNumber](progress: progress)
        }
        else {
            self.singleProgressCallback!(progress: progress)
        }
    }
    
    func syncServerDeletionsSent(uuids: [NSUUID]) {
        let sequenceNumber = self.deletionSequenceNumber++
        self.deletionCallbacks[sequenceNumber](uuids: uuids)
    }
    
    func syncServerSingleUploadComplete(uuid uuid: NSUUID) {
        let sequenceNumber = self.singleUploadSequenceNumber++
        self.singleUploadCallbacks[sequenceNumber](uuid: uuid)
    }
    
    // And this is to be called second (i.e., in the case of the recovery tests).
    func syncServerCommitComplete(numberOperations numberUploads:Int?) {
        let sequenceNumber = self.commitCompleteSequenceNumber++
        self.commitCompleteCallbacks[sequenceNumber](numberUploads: numberUploads)
    }
    
    // The callee owns the localFile after this call completes.
    func syncServerSingleFileDownloadComplete(localFile:NSURL, withFileAttributes attr: SMSyncAttributes) {
        self.downloadCallbacks[self.downloadSequenceNumber](localFile: localFile, attr: attr)
        self.downloadSequenceNumber += 1
    }
    
    // Called at the end of all downloads, on a non-error condition, if at least one download carried out.
    func syncServerAllDownloadsComplete() {
        self.allDownloadsCompleteCallbacks[self.allDownloadsCompleteSequenceNumber]()
        self.allDownloadsCompleteSequenceNumber += 1
    }
    
    func syncServerDeletionReceived(uuid uuid: NSUUID) {
    }
    
    func syncServerError(error:NSError) {
        let sequenceNumber = self.errorSequenceNumber++
        self.errorCallbacks[sequenceNumber]()
    }
    
#if DEBUG
    func syncServerNoFilesToDownload() {
        self.noDownloadsCallbacks[self.noDownloadsSequenceNumber]()
        self.noDownloadsSequenceNumber += 1
    }
#endif
}
