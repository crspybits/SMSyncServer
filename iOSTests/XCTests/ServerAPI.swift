//
//  ServerAPI.swift
//  NetDb
//
//  Created by Christopher Prince on 1/14/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import XCTest
//import NetDb
// The @testable notation lets us access "internal" classes within our project.
@testable import SMSyncServer

class ServerAPI: BaseClass {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    // Initiate the download immediately followed by ending it. Should succeed, but call no callbacks.
    func testStartThenEndDownloads() {
        let afterOperationsExpectation = self.expectationWithDescription("After Operations")
        
        self.waitUntilSyncServerUserSignin() {
            SMServerAPI.session.startDownloads() { (serverOperationId, error) in
                XCTAssert(error == nil)
                XCTAssert(serverOperationId != nil)

                SMServerAPI.session.endDownloads(serverOperationId: serverOperationId!) { error in
                    XCTAssert(error == nil)
                    
                    afterOperationsExpectation.fulfill()
                }
            }
        }
        
        self.waitForExpectations()
    }
}
