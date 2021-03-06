//
//  ServerCredentials.swift
//  NetDb
//
//  Created by Christopher Prince on 12/18/15.
//  Copyright © 2015 Spastic Muffin, LLC. All rights reserved.
//

// Assumptions: The SyncServer must be running.

import XCTest
@testable import SMSyncServer
import SMCoreLib

class ServerCredentials: XCTestCase {
    let minServerResponseTime:NSTimeInterval = 10

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func doTheTestWith(serverOpURL:NSURL, parameters:[String:AnyObject], expectedRC:Int) {
        let expectation = self.expectationWithDescription("Handler called")
        
        SMServerNetworking.session.sendServerRequestTo(toURL: serverOpURL, withParameters: parameters) { (serverResponse:[String:AnyObject]?, error:NSError?) in
        
            Log.msg("serverResponse: \(serverResponse)")
            expectation.fulfill()
            XCTAssertEqual(error, nil)
            XCTAssert(nil != serverResponse)
            let rc = serverResponse?[SMServerConstants.resultCodeKey] as? Int
            XCTAssert(rc == expectedRC)
        }
        
        self.waitForExpectationsWithTimeout(minServerResponseTime, handler: nil)
    }
    
    enum BadCredentialsType {
        case AllPresent
        case NoUserType
        case NoAccountType
        case NoIdToken
        case NoUUID
        case NoCloudFolderPath
    }
    
    func badCredentials(badCreds:BadCredentialsType) -> [String:AnyObject] {
    
        var serverParameters = [String:AnyObject]()
        var userCredentials = [String:AnyObject]()

        userCredentials[SMServerConstants.mobileDeviceUUIDKey] = "FakeDeviceUUID"
        userCredentials[SMServerConstants.cloudFolderPath] = "SomeFakePath"
        
        userCredentials[SMServerConstants.userType] = SMServerConstants.userTypeOwning
        userCredentials[SMServerConstants.accountType] = SMServerConstants.accountTypeGoogle
        
        userCredentials[SMServerConstants.googleUserIdToken] = "FakeIdToken"
        
        switch (badCreds) {
        case .NoUserType:
            userCredentials[SMServerConstants.userType] = nil

        case .NoAccountType:
            userCredentials[SMServerConstants.accountType] = nil
            
        case .NoIdToken:
            userCredentials[SMServerConstants.googleUserIdToken] = nil
            
        case .NoUUID:
            userCredentials[SMServerConstants.mobileDeviceUUIDKey] = nil
            
        case .NoCloudFolderPath:
            userCredentials[SMServerConstants.cloudFolderPath] = nil
            
        case .AllPresent:
            break
        }

        serverParameters[SMServerConstants.userCredentialsDataKey] = userCredentials
        
        return serverParameters
    }
    
    func doTestThatItFailsWithBadCredentials(badCreds:BadCredentialsType) {
        let serverOpURL = NSURL(string: SMServerAPI.session.serverURLString +
                        "/" + SMServerConstants.operationLock)!
        let parameters = self.badCredentials(badCreds)
        
        self.doTheTestWith(serverOpURL, parameters: parameters, expectedRC:  SMServerConstants.rcOperationFailed)
    }
    
    // Should test that at least one of these fail for all of the server URL's.
    func testThatItFailsWithBadCredentialsAllPresent() {
        self.doTestThatItFailsWithBadCredentials(.AllPresent)
    }
    
    func testThatItFailsWithBadCredentialsNoAccountType() {
        self.doTestThatItFailsWithBadCredentials(.NoAccountType)
    }
    
    func testThatItFailsWithBadCredentialsNoUserType() {
        self.doTestThatItFailsWithBadCredentials(.NoUserType)
    }

    func testThatItFailsWithBadCredentialsNoIdToken() {
        self.doTestThatItFailsWithBadCredentials(.NoIdToken)
    }
    
    func testThatItFailsWithBadCredentialsNoUUID() {
        self.doTestThatItFailsWithBadCredentials(.NoUUID)
    }
    
    func testThatItFailsWithBadCredentialsNoCloudFolderPath() {
        self.doTestThatItFailsWithBadCredentials(.NoCloudFolderPath)
    }
    
    // TEST CASE: Good Cloud type
}
