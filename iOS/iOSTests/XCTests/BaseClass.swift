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
    var processModeChanges = false
    
    // I have sometimes been getting test failures where it looks like the callback is not defined. i.e., there are no entries in the particular callbacks array. However, the callback was defined. This takes the form of an array index out-of-bounds crash. What was happening is that the timeout was exceeded on the prior test, and so XCTests moved on to the next test, but the prior test was actually still running-- interacting with the server. And when it finished, it tried doing the callbacks, which were no longer defined as the setup had been done for the next test. The cure was to extend the duration of the timeouts.
    var singleRecoveryCallback:(()->())?
    var numberOfRecoverySteps = 0

    var singleNoDownloadsCallback:(()->())?
    var numberOfNoDownloadsCallbacks = 0
    
    typealias inboundTransferCallback = (numberOperations:Int)->()
    var singleInboundTransferCallback:inboundTransferCallback?
    
    typealias commitCompleteCallback = (numberUploads:Int?)->()
    var commitCompleteSequenceNumber = 0
    var commitCompleteCallbacks:[commitCompleteCallback]!

    typealias singleUploadCallback = (uuid:NSUUID)->()
    var singleUploadSequenceNumber = 0
    var singleUploadCallbacks:[singleUploadCallback]!

    typealias deletionCallback = (uuids:[NSUUID])->()
    var deletionSequenceNumber = 0
    var deletionCallbacks:[deletionCallback]!

    typealias singleDownloadType = (localFile:SMRelativeLocalURL, attr: SMSyncAttributes)->()
    var singleDownloadSequenceNumber = 0
    var singleDownload:[singleDownloadType]!
    
    typealias shouldSaveDownloadsCallback = (downloads:[(NSURL, SMSyncAttributes)], acknowledgement:()->())->()
    var shouldSaveDownloadsSequenceNumber = 0
    var shouldSaveDownloads:[shouldSaveDownloadsCallback]!

    typealias shouldResolveDownloadConflictsCallback = (conflicts:[(NSURL, SMSyncAttributes, SMSyncServerConflict)])->()
    var shouldResolveDownloadConflictsSequenceNumber = 0
    var shouldResolveDownloadConflicts:[shouldResolveDownloadConflictsCallback]!
    
    typealias shouldDoDeletionsCallback = (deletions:[NSUUID], acknowledgement:()->())->()
    var shouldDoDeletionsSequenceNumber = 0
    var shouldDoDeletions:[shouldDoDeletionsCallback]!
    
    typealias shouldResolveDeletionConflictsCallback = (conflicts:[(NSUUID, SMSyncServerConflict)])->()
    var shouldResolveDeletionConflictsSequenceNumber = 0
    var shouldResolveDeletionConflicts:[shouldResolveDeletionConflictsCallback]!

    typealias errorCallback = ()->()
    var errorSequenceNumber = 0
    var errorCallbacks:[errorCallback]!

    typealias idleCallback = ()->()
    var idleSequenceNumber = 0
    var idleCallbacks:[idleCallback]!
    
    override func setUp() {
        super.setUp()

        SMSyncServer.session.autoCommit = false
        SMSyncServer.session.delegate = self
        
        self.extraServerResponseTime = 0
        self.commitCompleteSequenceNumber = 0
        self.commitCompleteCallbacks = [commitCompleteCallback]()
        self.errorCallbacks = [errorCallback]()
        //self.progressCallbacks = [progressCallback]()
        self.singleUploadCallbacks = [singleUploadCallback]()
        self.deletionCallbacks = [deletionCallback]()
        self.singleDownload = [singleDownloadType]()
        self.shouldSaveDownloads = [shouldSaveDownloadsCallback]()
        self.shouldResolveDownloadConflicts = [shouldResolveDownloadConflictsCallback]()
        self.shouldResolveDownloadConflictsSequenceNumber = 0
        self.shouldResolveDeletionConflicts = [shouldResolveDeletionConflictsCallback]()
        self.shouldResolveDeletionConflictsSequenceNumber = 0
        self.idleCallbacks = [idleCallback]()
        self.singleRecoveryCallback = nil
        self.numberOfRecoverySteps = 0
        self.numberOfNoDownloadsCallbacks = 0
        self.shouldDoDeletionsSequenceNumber = 0
        self.shouldDoDeletions = [shouldDoDeletionsCallback]()
        self.processModeChanges = false
        
        TestBasics.session.failure = {
            XCTFail()
        }
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func waitUntilSyncServerUserSignin(completion:()->()) {
        TimedCallback.withDuration(Float(self.initialDelayBeforeFirstTest)) {
            self.initialDelayBeforeFirstTest = 0.0
            self.processModeChanges = true
            completion()
        }
    }
    
    func waitForExpectations() {
        // [1]. Also needed to add in delay here. Note: This that calling waitForExpectationsWithTimeout within the TimedCallback does *not* work-- XCTest takes this to mean the test succeeded.
        self.waitForExpectationsWithTimeout(self.minServerResponseTime + self.initialDelayBeforeFirstTest + self.extraServerResponseTime, handler: nil)
    }
}

extension BaseClass : SMSyncServerDelegate {

    func syncServerShouldSaveDownloads(downloads: [(NSURL, SMSyncAttributes)], acknowledgement: () -> ()) {
        self.shouldSaveDownloads[self.shouldSaveDownloadsSequenceNumber](downloads: downloads, acknowledgement:acknowledgement)
        self.shouldSaveDownloadsSequenceNumber += 1
    }
    
    func syncServerShouldResolveDownloadConflicts(conflicts: [(NSURL, SMSyncAttributes, SMSyncServerConflict)]) {
        self.shouldResolveDownloadConflicts[self.shouldResolveDownloadConflictsSequenceNumber](conflicts: conflicts)
        self.shouldResolveDownloadConflictsSequenceNumber += 1
    }
    
    // Called when deletion indications have been received from the server. I.e., these files has been deleted on the server. This is received/called in an atomic manner: This reflects the current state of files on the server. The recommended action is for the client to delete the files represented by the UUID's.
    func syncServerShouldDoDeletions(deletions:[NSUUID], acknowledgement:()->()) {
        self.shouldDoDeletions[self.shouldDoDeletionsSequenceNumber](deletions: deletions, acknowledgement:acknowledgement)
        self.shouldDoDeletionsSequenceNumber += 1
    }
        
    func syncServerShouldResolveDeletionConflicts(conflicts:[(NSUUID, SMSyncServerConflict)]) {
        self.shouldResolveDeletionConflicts[self.shouldResolveDeletionConflictsSequenceNumber](conflicts: conflicts)
        self.shouldResolveDeletionConflictsSequenceNumber += 1
    }
    
    // Reports mode changes including errors. Generally useful for presenting a graphical user-interface which indicates ongoing server/networking operations. E.g., so that the user doesn't close or otherwise the dismiss the app until server operations have completed.
    func syncServerModeChange(newMode:SMSyncServerMode) {
        if !self.processModeChanges {
            return
        }
        
        switch newMode {
        case .Idle:
            // Sometimes get idle callbacks called from within idle callbacks, so increment the index first.
            let idleIndex = self.idleSequenceNumber
            self.idleSequenceNumber += 1
            self.idleCallbacks[idleIndex]()
            
        case .Synchronizing:
            break

        case .NetworkNotConnected:
            break
        
        case .NonRecoverableError, .ClientAPIError, .InternalError:
            self.errorCallbacks[self.errorSequenceNumber]()
            self.errorSequenceNumber += 1
        }
    }
    
    // Reports events. Useful for testing and debugging.
    func syncServerEventOccurred(event:SMSyncServerEvent) {
        switch event {
        case .DeletionsSent(uuids: let uuids):
            self.deletionCallbacks[self.deletionSequenceNumber](uuids: uuids)
            self.deletionSequenceNumber += 1
        
        case .SingleUploadComplete(uuid: let uuid):
            self.singleUploadCallbacks[self.singleUploadSequenceNumber](uuid: uuid)
            self.singleUploadSequenceNumber += 1
            
        case .OutboundTransferComplete(numberOperations: let numberOperations):
            self.commitCompleteCallbacks[self.commitCompleteSequenceNumber](numberUploads: numberOperations)
            self.commitCompleteSequenceNumber += 1
        
        case .NoFilesToDownload:
            if nil != self.singleNoDownloadsCallback {
                self.singleNoDownloadsCallback!()
            }
            self.numberOfNoDownloadsCallbacks += 1
        
        case .NoFilesToUpload:
            break
            
        case .SingleDownloadComplete(url: let url, attr: let attr):
            self.singleDownload[self.singleDownloadSequenceNumber](localFile: url, attr: attr)
            self.singleDownloadSequenceNumber += 1
            
        case .InboundTransferComplete(numberOperations: let numberOperations):
            if self.singleInboundTransferCallback != nil {
                self.singleInboundTransferCallback!(numberOperations: numberOperations!)
            }
            
        case .Recovery:
            if nil != self.singleRecoveryCallback {
                self.singleRecoveryCallback!()
            }
            self.numberOfRecoverySteps += 1
        
        case .LockAlreadyHeld:
            break
        }
    }

    func uploadFiles(testFiles:[TestFile], uploadExpectations:[XCTestExpectation], commitComplete:XCTestExpectation, idleExpectation:XCTestExpectation,
        complete:(()->())?) {
        
        for testFileIndex in 0...testFiles.count-1 {
            let testFile = testFiles[testFileIndex]
            let uploadExpectation = uploadExpectations[testFileIndex]
        
            SMSyncServer.session.uploadImmutableFile(testFile.url, withFileAttributes: testFile.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile.uuidString)
                uploadExpectation.fulfill()
            }
        }

        // The .Idle callback gets called first
        self.idleCallbacks.append() {
            idleExpectation.fulfill()
        }
        
        // Followed by the commit complete callback.
        self.commitCompleteCallbacks.append() { numberUploads in
            XCTAssert(numberUploads == testFiles.count)
            commitComplete.fulfill()
            self.checkFileSizes(testFiles, complete: complete)
        }
        
        SMSyncServer.session.commit()
    }
    
    func checkFileSizes(testFiles:[TestFile], complete:(()->())?) {
        if testFiles.count == 0 {
            complete?()
        }
        else {
            let testFile = testFiles[0]
            
            TestBasics.session.checkFileSize(testFile.uuidString, size: testFile.sizeInBytes) {
                let fileAttr = SMSyncServer.session.localFileStatus(testFile.uuid)
                XCTAssert(fileAttr != nil)
                XCTAssert(!fileAttr!.deleted!)
                self.checkFileSizes(Array(testFiles[1..<testFiles.count]), complete: complete)
            }
        }
    }
    
    func deleteFiles(testFiles:[TestFile], deletionExpectation:XCTestExpectation?, commitComplete:XCTestExpectation?, idleExpectation:XCTestExpectation,
        complete:(()->())?=nil) {
        
        for testFileIndex in 0...testFiles.count-1 {
            let testFile = testFiles[testFileIndex]
            SMSyncServer.session.deleteFile(testFile.uuid)
        }
        
        if deletionExpectation != nil {
            self.deletionCallbacks.append() { uuids in
                XCTAssert(uuids.count == testFiles.count)
                for testFileIndex in 0...testFiles.count-1 {
                    let testFile = testFiles[testFileIndex]
                    XCTAssert(uuids[testFileIndex].UUIDString == testFile.uuidString)
                }
                
                deletionExpectation!.fulfill()
            }
        }
        
        // The .Idle callback gets called first
        self.idleCallbacks.append() {
            idleExpectation.fulfill()
        }
        
        // Followed by the commit complete.
        if commitComplete == nil  {
            // I'm going to require that complete is nil too-- since that callback is called below, in the "else".
            Assert.If(complete != nil, thenPrintThisString: "complete not nil!")
        }
        else {
            self.commitCompleteCallbacks.append() { numberDeletions in
                if deletionExpectation != nil {
                    XCTAssert(numberDeletions == testFiles.count)
                }
                
                for testFile in testFiles {
                    let fileAttr = SMSyncServer.session.localFileStatus(testFile.uuid)
                    XCTAssert(fileAttr != nil)
                    XCTAssert(fileAttr!.deleted!)
                }
                
                commitComplete!.fulfill()
                complete?()
            }
        }
        
        SMSyncServer.session.commit()
    }
}
