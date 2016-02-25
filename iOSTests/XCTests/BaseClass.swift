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
    
    // I have sometimes been getting test failures where it looks like the callback is not defined. i.e., there are no entries in the particular callbacks array. However, the callback was defined. This takes the form of an array index out-of-bounds crash. What was happening is that the timeout was exceeded on the prior test, and so XCTests moved on to the next test, but the prior test was actually still running-- interacting with the server. And when it finished, it tried doing the callbacks, which were no longer defined as the setup had been done for the next test. The cure was to extend the duration of the timeouts.
    typealias progressCallback = (progress:SMClientMode)->()
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

    typealias singleDownloadType = (localFile:NSURL, attr: SMSyncAttributes)->()
    var singleDownloadSequenceNumber = 0
    var singleDownload:[singleDownloadType]!

    typealias noDownloadsCallback = ()->()
    var noDownloadsSequenceNumber = 0
    var noDownloadsCallbacks:[noDownloadsCallback]!
    
    typealias downloadsCompletedCallback = ()->()
    var downloadsCompleteSequenceNumber = 0
    var downloadsCompleteCallbacks:[downloadsCompletedCallback]!

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
        self.singleDownload = [singleDownloadType]()
        self.downloadsCompleteCallbacks = [downloadsCompletedCallback]()
        self.noDownloadsCallbacks = [noDownloadsCallback]()
        self.singleProgressCallback = nil
        
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
            completion()
        }
    }
    
    func waitForExpectations() {
        // [1]. Also needed to add in delay here. Note: This that calling waitForExpectationsWithTimeout within the TimedCallback does *not* work-- XCTest takes this to mean the test succeeded.
        self.waitForExpectationsWithTimeout(self.minServerResponseTime + self.initialDelayBeforeFirstTest + self.extraServerResponseTime, handler: nil)
    }
}

extension BaseClass : SMSyncServerDelegate {
    // Expect this to be called first for the recovery tests.
    func syncServerRecovery(progress:SMClientMode) {
        if nil == self.singleProgressCallback {
            self.progressCallbacks[self.progressSequenceNumber](progress: progress)
            self.progressSequenceNumber += 1
        }
        else {
            self.singleProgressCallback!(progress: progress)
        }
    }
    
    func syncServerDeletionsSent(uuids: [NSUUID]) {
        self.deletionCallbacks[self.deletionSequenceNumber](uuids: uuids)
        self.deletionSequenceNumber += 1
    }
    
    func syncServerSingleUploadComplete(uuid uuid: NSUUID) {
        self.singleUploadCallbacks[self.singleUploadSequenceNumber](uuid: uuid)
        self.singleUploadSequenceNumber += 1
    }
    
    // And this is to be called second (i.e., in the case of the recovery tests).
    func syncServerCommitComplete(numberOperations numberUploads:Int?) {
        self.commitCompleteCallbacks[self.commitCompleteSequenceNumber](numberUploads: numberUploads)
        self.commitCompleteSequenceNumber += 1
    }
    
    // Called at the end of all downloads, on a non-error condition.
    func syncServerDownloadsComplete(downloadedFiles: [(NSURL, SMSyncAttributes)]) {
        for (url, attr) in downloadedFiles {
            self.singleDownload[self.singleDownloadSequenceNumber](localFile: url, attr: attr)
            self.singleDownloadSequenceNumber += 1
        }
        
        self.downloadsCompleteCallbacks[self.downloadsCompleteSequenceNumber]()
        self.downloadsCompleteSequenceNumber += 1
    }
    
    func syncServerDeletionReceived(uuid uuid: NSUUID) {
    }
    
    func syncServerError(error:NSError) {
        self.errorCallbacks[self.errorSequenceNumber]()
        self.errorSequenceNumber += 1
    }
    
#if DEBUG
    func syncServerNoFilesToDownload() {
        self.noDownloadsCallbacks[self.noDownloadsSequenceNumber]()
        self.noDownloadsSequenceNumber += 1
    }
#endif
}
