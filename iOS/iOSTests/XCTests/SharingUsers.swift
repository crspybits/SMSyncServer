//
//  SharingUsers.swift
//  Tests
//
//  Created by Christopher Prince on 6/11/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import XCTest
@testable import SMSyncServer
import SMCoreLib

class SharingUsers: BaseClass {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    // MARK: Server-level API testing: operationCreateSharingInvitation
    
    func doTestSendCapabilitiesToServerExpectingError(capabilities:[String]?) {
        let createSharingInvitationDone = self.expectationWithDescription("Created Invitation")
        
        self.waitUntilSyncServerUserSignin() {
            SMServerAPI.session.createSharingInvitation(capabilities: capabilities, completion: { (authorizationCode, apiResult) in
                XCTAssert(apiResult.error != nil)
                XCTAssert(authorizationCode == nil)
                createSharingInvitationDone.fulfill()
            })
        }
        
        self.waitForExpectations()
    }
    
    func testThatSendingNilCapabilitiesToServerFails() {
        self.doTestSendCapabilitiesToServerExpectingError(nil)
    }
    
    func testThatSendingEmptyCapabilitiesToServerFails() {
        self.doTestSendCapabilitiesToServerExpectingError([])
    }
    
    // One of the capabilities in the string array sent is bad. E.g., give "ReadIt".
    func testThatSendingInvalidCapabilityToServerFails() {
        self.doTestSendCapabilitiesToServerExpectingError(["ReadIt"])
    }

    func doTestSendCapabilitiesToServerExpectingNoError(capabilities:SMSharingUserCapabilityMask) {
        let createSharingInvitationDone = self.expectationWithDescription("Created Invitation")
        let lookupSharingInvitationDone = self.expectationWithDescription("Lookup Invitation")
        
        self.waitUntilSyncServerUserSignin() {
            SMServerAPI.session.createSharingInvitation(capabilities: capabilities, completion: { (invitationCode, apiResult) in
                XCTAssert(apiResult.error == nil)
                XCTAssert(invitationCode != nil)
                createSharingInvitationDone.fulfill()
                
                SMServerAPI.session.lookupSharingInvitation(invitationCode: invitationCode!, completion: { (invitationContents, apiResult) in
                    
                    XCTAssert(apiResult.error == nil)
                    XCTAssert(invitationContents != nil)
                    
                    let expiryDate = invitationContents![SMServerConstants.invitationExpiryDate] as? String
                    XCTAssert(expiryDate != nil)

                    let owningUser = invitationContents![SMServerConstants.invitationOwningUser] as? String
                    XCTAssert(owningUser != nil)

                    let capabilities = invitationContents![SMServerConstants.invitationCapabilities] as? [String]
                    XCTAssert(capabilities != nil)
                    
                    lookupSharingInvitationDone.fulfill()
                })
            })
        }
        
        self.waitForExpectations()
    }
    
    func testThatSendingOneCapabilityWorks() {
        self.doTestSendCapabilitiesToServerExpectingNoError([.Read])
    }
    
    func testThatSendingMultipleCapabilitiesWorks() {
        self.doTestSendCapabilitiesToServerExpectingNoError([.Create, .Read])
    }
    
    func testThatRedeemingSharingInvitationWorks() {
    }
    
    // Test case: Attempt to create a sharing invitation when you are a sharing user, and don't have authority to create a sharing invitation. Should fail.
    // Test is disabled because you have to make sure to sign in to the right account to make this happen.
    func testThatMinimalCapabilitySharingUserCannotCreateSharingInvitation() {
    }
    
    func testThatInviteCapabilitySharingUserCanCreateSharingInvitation() {
    }
}
