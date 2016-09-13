//
//  ServerNetworking.swift
//  NetDbTests
//
//  Created by Christopher Prince on 12/11/15.
//  Copyright © 2015 Spastic Muffin, LLC. All rights reserved.
//

import XCTest
@testable import SMSyncServer
import SMCoreLib

// Unit tests for SMServerNetworking
class ServerNetworking: XCTestCase {
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
    
    func testThatItFailsOnBadServerOperation() {
        let serverOpURL = SMServerAPI.session.serverURL
        let parameters:[String:AnyObject] = [:]
        
        self.doTheTestWith(serverOpURL, parameters: parameters, expectedRC:  SMServerConstants.rcUndefinedOperation)
    }
    
    // TODO: Should test that this one fails for all of the valid server operations. i.e., that you get a failure without creds on all of them.
    func testThatItFailsWithoutCredentials() {
        let serverOpURL = NSURL(string: SMServerAPI.session.serverURLString +
                        "/" + SMServerConstants.operationUploadFile)
        let parameters:[String:AnyObject] = [:]
        
        self.doTheTestWith(serverOpURL!, parameters: parameters, expectedRC:  SMServerConstants.rcOperationFailed)
    }
    
    // This only works with the debug/simplified upload app.post method on the server. I'm trying to resolve the problem I've been having with the file size increasing on the server, when uploading a PNG file.
    func DISABLED_testPNGFileUploadWithSimplifiedServerPOSTMethod() {
        let expectation = self.expectationWithDescription("Handler called")
    
        let serverOpURL = NSURL(string: SMServerAPI.session.serverURLString +
                        "/" + SMServerConstants.operationUploadFile)!
        let parameters:[String:AnyObject] = [SMServerConstants.fileMIMEtypeKey: "image/png"]
        
        let url = NSBundle.mainBundle().URLForResource("Meowsie", withExtension: "png")
        
        SMServerNetworking.session.uploadFileTo(serverOpURL, fileToUpload: url!, withParameters: parameters) { (serverResponse, error) in
            expectation.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(minServerResponseTime, handler: nil)
    }
}
