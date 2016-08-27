//
//  ErrorHandling.swift
//  Tests
//
//  Created by Christopher Prince on 5/21/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import XCTest
@testable import SMSyncServer
import SMCoreLib
@testable import Tests

class GenerateInternalError {
    var testCase:BaseClass!
    var errorCallbackExpectation:XCTestExpectation!
    var singleUploadExpectation:XCTestExpectation!
    var idleExpectation:XCTestExpectation!

    init(withTestCase testCase:BaseClass) {
        self.testCase = testCase
        
        self.errorCallbackExpectation = testCase.expectationWithDescription("Error Callback")
        self.singleUploadExpectation = testCase.expectationWithDescription("Single Upload")
        self.idleExpectation = testCase.expectationWithDescription("Idle")
    }
    
    // Does not do a reset from the error.
    func run(withFileName fileName:String, completion:()->()) {
        let fileName1 = fileName + ".1"
        var testFile1 = TestBasics.session.createTestFile(fileName1)
        testFile1.remoteFileName = fileName1

        try! SMSyncServer.session.uploadImmutableFile(testFile1.url, withFileAttributes: testFile1.attr)
        
        var testFile2 = TestBasics.session.createTestFile(fileName + ".2")
        testFile2.remoteFileName = testFile1.remoteFileName

        try! SMSyncServer.session.uploadImmutableFile(testFile2.url, withFileAttributes: testFile2.attr)
        
        self.testCase.idleCallbacks.append() {
            self.idleExpectation.fulfill()
        }
        
        try! SMSyncServer.session.commit()
        
        self.testCase.singleUploadCallbacks.append() { uuid in
            XCTAssert(uuid.UUIDString == testFile1.uuidString)
            self.singleUploadExpectation.fulfill()
        }
        
        self.testCase.errorCallbacks.append() {
            SMSyncServer.session.cleanupFile(testFile1.uuid)
            SMSyncServer.session.cleanupFile(testFile2.uuid)
            
            CoreData.sessionNamed(CoreDataTests.name).removeObject(
                testFile1.appFile)
            CoreData.sessionNamed(CoreDataTests.name).removeObject(
                testFile2.appFile)
            CoreData.sessionNamed(CoreDataTests.name).saveContext()
            
            self.errorCallbackExpectation.fulfill()
            
            completion()
        }
    }
}

class ErrorHandling: BaseClass {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func assertsForEmptyQueues() {
        XCTAssert(SMQueues.current().beingUploaded == nil || SMQueues.current().beingUploaded!.operations!.count == 0)
        XCTAssert(SMQueues.current().uploadsBeingPrepared == nil || SMQueues.current().uploadsBeingPrepared!.operations!.count == 0)
        XCTAssert(SMQueues.current().internalBeingDownloaded == nil || SMQueues.current().internalBeingDownloaded!.count == 0)
        XCTAssert(SMQueues.current().internalCommittedUploads == nil || SMQueues.current().internalCommittedUploads!.count == 0)
    }

    func testSeriousError(doSecondRequest secondRequest:Bool) {
        let idleExpectation = self.expectationWithDescription("Idle Callback")
        let resetExpectation = self.expectationWithDescription("Reset Callback")

        var secondResetCallback:XCTestExpectation?
        
        if secondRequest {
            secondResetCallback = self.expectationWithDescription("Second Reset Callback")
        }

        self.waitUntilSyncServerUserSignin() {
            self.idleCallbacks.append() {
                idleExpectation.fulfill()
            }
            
            // Use SMSyncControl directly because that let's us do a debug test of the "serious" errors.
            SMSyncControl.session.resetFromError(allowDebugReset: true) { error in
                XCTAssert(error == nil)
                self.assertsForEmptyQueues()
                XCTAssert(SMSyncServer.session.mode == .Idle)
                resetExpectation.fulfill()
            }
            
            if secondRequest {
                XCTAssert(SMSyncServer.session.mode == .ResettingFromError)
                SMSyncServer.session.resetFromError() { error in
                    XCTAssert(error != nil)
                    secondResetCallback?.fulfill()
                }
            }
        }
        
        self.waitForExpectations()
    }
    
    func testThatResetFromMoreSeriousErrorWorks() {
        self.testSeriousError(doSecondRequest: false)
    }
    
    // Second reset request immediate after should be ignored.
    func testThatDoubleResetFromMoreSeriousErrorIsIgnored() {
        self.testSeriousError(doSecondRequest: true)
    }
    
    func testThatPurelyLocalResetWorks() {
        let error = GenerateInternalError(withTestCase: self)
        
        self.extraServerResponseTime = 120
        let completed = self.expectationWithDescription("Completed")
        
        self.waitUntilSyncServerUserSignin() {

            error.run(withFileName: "testThatPurelyLocalResetWorks") {
                SMSyncServer.session.resetFromError(resetType: .Local)
                
                // Results of resetFromError: 1) Queues get flushed, 2) mode is idle.
                self.assertsForEmptyQueues()
                XCTAssert(SMSyncServer.session.mode == .Idle)
                
                completed.fulfill()
            }
        }
        
        self.waitForExpectations()
    }
    
    // I have a deficiency here: I have been unable to artifically create an error state where: (a) there is an error mode, and (b) there is a lock held on the server.
}
