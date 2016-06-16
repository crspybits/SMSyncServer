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
@testable import Tests

class SharingUsers: BaseClass {
    private static var invitation = SMPersistItemString(name: "SharingUsers.invitation", initialStringValue: "", persistType: .UserDefaults)
    
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
    
    func testThatRedeemingSharingInvitationByOwningExclusiveUserFails() {
        XCTFail()
    }
    
    // The following tests are disabled because either you have to do them in a particular order, or you have to make sure to sign in to the right account to carry them out.
    
    // This needs to be run *first* before any of the redeeming tests. Run this when you are signed into an OwningUser account (e.g., Google). Do this and the following two tests in a sequence.
    // 1)
    func testPreparationCreatePersistedInvitations() {
        let createSharingInvitationDone = self.expectationWithDescription("Created Invitation")
        
        self.waitUntilSyncServerUserSignin() {
            SMServerAPI.session.createSharingInvitation(capabilities: [.Read], completion: { (invitationCode, apiResult) in
                XCTAssert(apiResult.error == nil)
                XCTAssert(invitationCode != nil)
                SharingUsers.invitation.stringValue = invitationCode!
                
                // So I can run test 2), manually.
                AppDelegate.sharingInvitationCode = invitationCode!
                
                createSharingInvitationDone.fulfill()
            })
        }
        
        self.waitForExpectations()
    }
    
    // 2) Signout as the owning user, and sign in as a sharing (Facebook)
    // Manual test.

    // Must be signed in as a sharing user.
    // 3)
    func testThatRedeemingAlreadyRedeemedInvitationFails() {
        Assert.If(SharingUsers.invitation.stringValue == "", thenPrintThisString: "Haven't yet set up invitationCode")
        
        let redeemedSharingInvitationDone = self.expectationWithDescription("Redeemed Invitation")
        
        self.waitUntilSyncServerUserSignin() {
            SMSyncServerUser.session.redeemSharingInvitation(invitationCode: SharingUsers.invitation.stringValue, completion: { (error) in
                XCTAssert(error != nil)
                redeemedSharingInvitationDone.fulfill()
            })
        }
        
        self.waitForExpectations()
    }
    
    func testThatRedeemingEmptyInvitationFails() {
        let redeemAttemptDone = self.expectationWithDescription("Redeem Attempt Done")
        
        self.waitUntilSyncServerUserSignin() {
            SMSyncServerUser.session.redeemSharingInvitation(invitationCode: "", completion: { (error) in
                XCTAssert(error != nil)
                redeemAttemptDone.fulfill()
            })
        }
        
        self.waitForExpectations()
    }

    func testThatMinimalCapabilitySharingUserCannotCreateSharingInvitation() {
        XCTFail()
    }
    
    func testThatInviteCapabilitySharingUserCanCreateSharingInvitation() {
        XCTFail()
    }
    
    func testThatRedeemingExpiredInvitationFails() {
        XCTFail()
    }
    
    func testThatRedeemingAndLinkingSameOwningUserAccountOverwrites() {
        XCTFail()
    }
}
