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
    var timedCallback:TimedCallback?
    var initialDelayBeforeFirstTest:NSTimeInterval = 20
    let minServerResponseTime:NSTimeInterval = 15
    var extraServerResponseTime:Double = 0
    var processModeChanges = false
    
    // I have sometimes been getting test failures where it looks like the callback is not defined. i.e., there are no entries in the particular callbacks array. However, the callback was defined. This takes the form of an array index out-of-bounds crash. What was happening is that the timeout was exceeded on the prior test, and so XCTests moved on to the next test, but the prior test was actually still running-- interacting with the server. And when it finished, it tried doing the callbacks, which were no longer defined as the setup had been done for the next test. The cure was to extend the duration of the timeouts.
    var singleRecoveryCallback:(()->())?
    var numberOfRecoverySteps = 0

    var downloadsFinishedCallback:(()->())?
    var numberOfDownloadsFinishedCallbacks = 0
    
    typealias inboundTransferCallback = (numberOperations:Int)->()
    var singleInboundTransferCallback:inboundTransferCallback?

    typealias frameworkUploadMetaDataUpdatedCallback = ()->()
    var frameworkUploadMetaDataUpdatedCallbackSequenceNumber = 0
    var frameworkUploadMetaDataUpdatedCallbacks:[frameworkUploadMetaDataUpdatedCallback]!
    var useFrameworkUploadMetaDataUpdated = false
    
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
    
    typealias shouldSaveDownloadsCallback = (downloads:[(downloadedFile: NSURL, downloadedFileAttributes: SMSyncAttributes)], acknowledgement:()->())->()
    var shouldSaveDownloadsSequenceNumber = 0
    var shouldSaveDownloads:[shouldSaveDownloadsCallback]!

    typealias shouldResolveDownloadConflictsCallback = (conflicts:[(downloadedFile: NSURL, downloadedFileAttributes: SMSyncAttributes, uploadConflict: SMSyncServerConflict)])->()
    var shouldResolveDownloadConflictsSequenceNumber = 0
    var shouldResolveDownloadConflicts:[shouldResolveDownloadConflictsCallback]!
    
    typealias shouldDoDeletionsCallback = (deletions:[SMSyncAttributes], acknowledgement:()->())->()
    var shouldDoDeletionsSequenceNumber = 0
    var shouldDoDeletions:[shouldDoDeletionsCallback]!
    
    typealias shouldResolveDeletionConflictsCallback = (conflicts:[(downloadDeletion: SMSyncAttributes, uploadConflict: SMSyncServerConflict)])->()
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
        self.shouldSaveDownloadsSequenceNumber = 0
        self.shouldResolveDownloadConflicts = [shouldResolveDownloadConflictsCallback]()
        self.shouldResolveDownloadConflictsSequenceNumber = 0
        self.shouldResolveDeletionConflicts = [shouldResolveDeletionConflictsCallback]()
        self.shouldResolveDeletionConflictsSequenceNumber = 0
        self.idleCallbacks = [idleCallback]()
        self.singleRecoveryCallback = nil
        self.numberOfRecoverySteps = 0
        self.numberOfDownloadsFinishedCallbacks = 0
        self.shouldDoDeletionsSequenceNumber = 0
        self.shouldDoDeletions = [shouldDoDeletionsCallback]()
        self.processModeChanges = false
        self.frameworkUploadMetaDataUpdatedCallbackSequenceNumber = 0
        self.frameworkUploadMetaDataUpdatedCallbacks = [frameworkUploadMetaDataUpdatedCallback]()
        self.useFrameworkUploadMetaDataUpdated = false
        
        TestBasics.session.failure = {
            XCTFail()
        }
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func waitUntilSyncServerUserSignin(completion:()->()) {
        Log.special("Waiting for user signin to server...")
        self.timedCallback = TimedCallback.withDuration(Float(self.initialDelayBeforeFirstTest)) {
            Log.special("Starting XCTest...")
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

    func syncServerShouldSaveDownloads(downloads: [(downloadedFile: NSURL, downloadedFileAttributes: SMSyncAttributes)], acknowledgement: () -> ()) {
        let sequenceNumber = self.shouldSaveDownloadsSequenceNumber
        self.shouldSaveDownloadsSequenceNumber += 1
        self.shouldSaveDownloads[sequenceNumber](downloads: downloads, acknowledgement:acknowledgement)
    }
    
    func syncServerShouldResolveDownloadConflicts(conflicts: [(downloadedFile: NSURL, downloadedFileAttributes: SMSyncAttributes, uploadConflict: SMSyncServerConflict)]) {
        let sequenceNumber = self.shouldResolveDownloadConflictsSequenceNumber
        self.shouldResolveDownloadConflictsSequenceNumber += 1
        self.shouldResolveDownloadConflicts[sequenceNumber](conflicts: conflicts)
    }
    
    // Called when deletion indications have been received from the server. I.e., these files has been deleted on the server. This is received/called in an atomic manner: This reflects the current state of files on the server. The recommended action is for the client to delete the files represented by the UUID's.
    func syncServerShouldDoDeletions(downloadDeletions downloadDeletions:[SMSyncAttributes], acknowledgement:()->()) {
        let sequenceNumber = self.shouldDoDeletionsSequenceNumber
        self.shouldDoDeletionsSequenceNumber += 1
        self.shouldDoDeletions[sequenceNumber](deletions: downloadDeletions, acknowledgement:acknowledgement)
    }
        
    func syncServerShouldResolveDeletionConflicts(conflicts:[(downloadDeletion: SMSyncAttributes, uploadConflict: SMSyncServerConflict)]) {
        let sequenceNumber = self.shouldResolveDeletionConflictsSequenceNumber
        self.shouldResolveDeletionConflictsSequenceNumber += 1
        self.shouldResolveDeletionConflicts[sequenceNumber](conflicts: conflicts)
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
            
        case .Synchronizing, .ResettingFromError:
            break

        case .NetworkNotConnected:
            break
        
        case .NonRecoverableError, .InternalError:
            let sequenceNumber = self.errorSequenceNumber
            self.errorSequenceNumber += 1
            self.errorCallbacks[sequenceNumber]()
        }
    }
    
    // Reports events. Useful for testing and debugging.
    func syncServerEventOccurred(event:SMSyncServerEvent) {
        switch event {
        case .DeletionsSent(uuids: let uuids):
            let sequenceNumber = self.deletionSequenceNumber
            self.deletionSequenceNumber += 1
            self.deletionCallbacks[sequenceNumber](uuids: uuids)
            
        case .SingleUploadComplete(uuid: let uuid):
            let sequenceNumber = self.singleUploadSequenceNumber
            self.singleUploadSequenceNumber += 1
            self.singleUploadCallbacks[sequenceNumber](uuid: uuid)
        
        case .FrameworkUploadMetaDataUpdated:
            if !self.useFrameworkUploadMetaDataUpdated {
                return
            }
            let sequenceNumber = self.frameworkUploadMetaDataUpdatedCallbackSequenceNumber
            self.frameworkUploadMetaDataUpdatedCallbackSequenceNumber += 1
            self.frameworkUploadMetaDataUpdatedCallbacks[sequenceNumber]()
            
        case .AllUploadsComplete(numberOperations: let numberOperations):
            let sequenceNumber = self.commitCompleteSequenceNumber
            self.commitCompleteSequenceNumber += 1
            self.commitCompleteCallbacks[sequenceNumber](numberUploads: numberOperations)
        
        case .DownloadsFinished:
            if nil != self.downloadsFinishedCallback {
                self.downloadsFinishedCallback!()
            }
            self.numberOfDownloadsFinishedCallbacks += 1
        
        case .NoFilesToUpload:
            break
            
        case .SingleDownloadComplete(url: let url, attr: let attr):
            let sequenceNumber = self.singleDownloadSequenceNumber
            self.singleDownloadSequenceNumber += 1
            self.singleDownload[sequenceNumber](localFile: url, attr: attr)
            
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

    func uploadFiles(testFiles:[TestFile], uploadExpectations:[XCTestExpectation]?, commitComplete:XCTestExpectation?, idleExpectation:XCTestExpectation,
        complete:(()->())?) {
        
        for testFileIndex in 0...testFiles.count-1 {
            let testFile = testFiles[testFileIndex]
            let uploadExpectation:XCTestExpectation? = uploadExpectations?[testFileIndex]
        
            try! SMSyncServer.session.uploadImmutableFile(testFile.url, withFileAttributes: testFile.attr)
            
            if uploadExpectation != nil {
                self.singleUploadCallbacks.append() { uuid in
                    XCTAssert(uuid.UUIDString == testFile.uuidString)
                    uploadExpectation!.fulfill()
                }
            }
        }

        // The .Idle callback gets called first
        self.idleCallbacks.append() {
            if commitComplete == nil {
                complete?()
            }
            idleExpectation.fulfill()
        }
        
        if commitComplete != nil {
            // Followed by the commit complete callback.
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == testFiles.count)
                commitComplete!.fulfill()
                self.checkFileSizes(testFiles, complete: complete)
            }
        }
        
        try! SMSyncServer.session.commit()
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
    
    func deleteFiles(testFiles:[TestFile], deletionExpectation:XCTestExpectation?, commitCompleteExpectation:XCTestExpectation?, idleExpectation:XCTestExpectation,
        complete:(()->())?=nil) {
        
        for testFileIndex in 0...testFiles.count-1 {
            let testFile = testFiles[testFileIndex]
            try! SMSyncServer.session.deleteFile(testFile.uuid)
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
            if commitCompleteExpectation == nil  {
                complete?()
            }
            idleExpectation.fulfill()
        }
        
        // Followed by the commit complete.
        if commitCompleteExpectation != nil  {
            self.commitCompleteCallbacks.append() { numberDeletions in
                Log.msg("commitCompleteCallbacks: deleteFiles")
                if deletionExpectation != nil {
                    XCTAssert(numberDeletions == testFiles.count)
                }
                
                for testFile in testFiles {
                    let fileAttr = SMSyncServer.session.localFileStatus(testFile.uuid)
                    XCTAssert(fileAttr != nil)
                    XCTAssert(fileAttr!.deleted!)
                }
                
                commitCompleteExpectation!.fulfill()
                complete?()
            }
        }
        
        try! SMSyncServer.session.commit()
    }
    
    func downloadOneFile(testFile:TestFile) {

        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Commit Complete")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")
        let singleDownloadExpectation = self.expectationWithDescription("Single Download")
        let allDownloadsCompleteExpectation = self.expectationWithDescription("All Downloads Complete")
        let idleExpectation1 = self.expectationWithDescription("Idle1")
        let idleExpectation2 = self.expectationWithDescription("Idle2")

        var numberDownloads = 0
        
        self.extraServerResponseTime = 360
        
        self.waitUntilSyncServerUserSignin() {
            try! SMSyncServer.session.uploadImmutableFile(testFile.url, withFileAttributes: testFile.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile.uuidString)
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(testFile.uuidString, size: testFile.sizeInBytes) {
                    uploadCompleteCallbackExpectation.fulfill()
                }
            }
            
            self.singleDownload.append() { (downloadedFile:NSURL, downloadedFileAttr: SMSyncAttributes) in
                XCTAssert(downloadedFileAttr.uuid.UUIDString == testFile.uuidString)
                let filesAreTheSame = SMFiles.compareFiles(file1: testFile.url, file2: downloadedFile)
                XCTAssert(filesAreTheSame)
                numberDownloads += 1
                singleDownloadExpectation.fulfill()
            }
            
            self.shouldSaveDownloads.append() { downloadedFiles, ack in
                XCTAssert(numberDownloads == 1)
                XCTAssert(downloadedFiles.count == 1)
                let (_, _) = downloadedFiles[0]
                allDownloadsCompleteExpectation.fulfill()
                ack()
            }
            
            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation1.fulfill()
                
                // Forget locally about the uploaded file so we can download it.
                SMSyncServer.session.resetMetaData(forUUID:testFile.uuid)
                
                // Force the check for downloads.
                SMSyncControl.session.nextSyncOperation()
            }
            
            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation2.fulfill()
            }
            
            try! SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
}
