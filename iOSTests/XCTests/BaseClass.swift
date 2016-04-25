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
    
    typealias downloadsCompletedCallback = (downloadedFiles:[(NSURL, SMSyncAttributes)])->()
    var downloadsCompleteSequenceNumber = 0
    var downloadsCompleteCallbacks:[downloadsCompletedCallback]!

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
        self.downloadsCompleteCallbacks = [downloadsCompletedCallback]()
        self.idleCallbacks = [idleCallback]()
        self.singleRecoveryCallback = nil
        self.numberOfRecoverySteps = 0
        self.numberOfNoDownloadsCallbacks = 0

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

    func syncServerDownloadsComplete(downloadedFiles:[(NSURL, SMSyncAttributes)], acknowledgement:()->()) {
        self.downloadsCompleteCallbacks[self.downloadsCompleteSequenceNumber](downloadedFiles: downloadedFiles)
        self.downloadsCompleteSequenceNumber += 1
        acknowledgement()
    }
    
    // Called when deletions indications have been received from the server. I.e., these files has been deleted on the server. This is received/called in an atomic manner: This reflects the current state of files on the server. The recommended action is for the client to delete the files represented by the UUID's.
    func syncServerClientShouldDeleteFiles(uuids:[NSUUID], acknowledgement:()->()) {
        acknowledgement()
    }
    
    // Reports mode changes including errors. Generally useful for presenting a graphical user-interface which indicates ongoing server/networking operations. E.g., so that the user doesn't close or otherwise the dismiss the app until server operations have completed.
    func syncServerModeChange(newMode:SMSyncServerMode) {
        if !self.processModeChanges {
            return
        }
        
        switch newMode {
        case .Idle:
            self.idleCallbacks[self.idleSequenceNumber]()
            self.idleSequenceNumber += 1
            
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
        }
    }
}
