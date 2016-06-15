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
import Tests

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

    // Seems ClientAPI error is not used any more-- since we now are using throws for client API errors.
#if false
    func testThatResetFromClientAPIErrorWorks() {
        let idleExpectation = self.expectationWithDescription("Idle Callback")
        let resetExpectation = self.expectationWithDescription("Reset Callback")
        let errorExpectation = self.expectationWithDescription("Error Callback")

        self.waitUntilSyncServerUserSignin() {
            // Add something into a queue to make this actually do something.
            
            // Turn off network so commit doesn't kick off.
            Network.session().debugNetworkOff = true
            
            let testFile = TestBasics.session.createTestFile("ResetFromClientAPIError")
            try! SMSyncServer.session.uploadImmutableFile(testFile.url, withFileAttributes: testFile.attr)
            try! SMSyncServer.session.commit()

            // Generate a client API error: Attempt to delete a file unknown to SMSyncServer. Need to do this because resetFromError requires that the mode currently be an error mode.
            let testFile2 = TestBasics.session.createTestFile("ResetFromClientAPIError.2")
            do {
                try SMSyncServer.session.deleteFile(testFile2.uuid)
            } catch {
            }
            
            self.idleCallbacks.append() {
                idleExpectation.fulfill()
            }
            
            SMSyncServer.session.resetFromError { error in
                XCTAssert(error == nil)
                self.assertsForEmptyQueues()
                XCTAssert(SMSyncServer.session.mode == .Idle)
                
                Network.session().debugNetworkOff = false
                resetExpectation.fulfill()
            }
        }
        
        self.waitForExpectations()
    }
#endif

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
        XCTFail()
    }
    
    func testThatPurelyServerResetWorks() {
        XCTFail()
    }
}
