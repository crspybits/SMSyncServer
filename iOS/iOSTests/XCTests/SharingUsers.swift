//
//  SharingUsers.swift
//  Tests
//
//  Created by Christopher Prince on 6/11/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

// 6/20/16; I've been having problems with XCTests failing. Just posted to SO about this: http://stackoverflow.com/questions/37922146/xctests-failing-on-physical-device-canceling-tests-due-to-timeout

import XCTest
@testable import SMSyncServer
import SMCoreLib
@testable import Tests

class SharingUsers: BaseClass {
    private static var invitationRead = SMPersistItemString(name: "SharingUsers.invitationRead1", initialStringValue: "", persistType: .UserDefaults)
    private static var invitationReadAndUpdate = SMPersistItemString(name: "SharingUsers.invitationReadAndUpdate", initialStringValue: "", persistType: .UserDefaults)
    private static var invitationInvite = SMPersistItemString(name: "SharingUsers.invitationInvite", initialStringValue: "", persistType: .UserDefaults)
    private static var invitationInvite2 = SMPersistItemString(name: "SharingUsers.invitationInvite2", initialStringValue: "", persistType: .UserDefaults)

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
        let createSharingInvitationDone = self.expectationWithDescription("Created Invitation")
        let redeemSharingInvitationDone = self.expectationWithDescription("Created Invitation")
        
        self.waitUntilSyncServerUserSignin() {
            SMServerAPI.session.createSharingInvitation(capabilities: self.readCapabilities, completion: { (invitationCode, apiResult) in
                XCTAssert(apiResult.error == nil)
                XCTAssert(invitationCode != nil)
                createSharingInvitationDone.fulfill()
                
                SMSyncServerUser.session.redeemSharingInvitation(invitationCode: SharingUsers.invitationRead.stringValue) { (linkedOwningUserId, error) in
                    XCTAssert(linkedOwningUserId == nil)
                    XCTAssert(error != nil)
                    redeemSharingInvitationDone.fulfill()
                }
            })
        }
    }
    
    // The following tests are disabled because either you have to do them in a particular order, or you have to make sure to sign in to the right account to carry them out.

    let readCapabilities:SMSharingUserCapabilityMask = [.Read]
    let readAndUpdateCapabilities:SMSharingUserCapabilityMask = [.Read, .Update]
    let inviteCapabilities:SMSharingUserCapabilityMask = [.Invite]

    func createAndTestInvitation(expectation:XCTestExpectation, invitation:SMPersistItemString, capabilities:SMSharingUserCapabilityMask, testCompleted:(()->())?=nil) {
        
        self.waitUntilSyncServerUserSignin() {
            SMServerAPI.session.createSharingInvitation(capabilities: capabilities, completion: { (invitationCode, apiResult) in
                XCTAssert(apiResult.error == nil)
                XCTAssert(invitationCode != nil)
                invitation.stringValue = invitationCode!
                expectation.fulfill()
                testCompleted?()
            })
        }
        
        self.waitForExpectations()
    }

    // This needs to be run *first* before any of the redeeming tests. Run this when you are signed into an OwningUser account (e.g., Google). Do this and the following two tests in a sequence.
    // 1a)
    func testPreparationCreatePersistedInvitation1() {
        let createSharingInvitationDone = self.expectationWithDescription("Created Invitation")

        self.createAndTestInvitation(createSharingInvitationDone, invitation: SharingUsers.invitationRead, capabilities: self.readCapabilities) {
            
            // So I can run test 3), manually.
            AppDelegate.sharingInvitationCode = SharingUsers.invitationRead.stringValue
        }
    }

    // 1b)
    func testPreparationCreatePersistedInvitation2() {
        let createSharingInvitationDone = self.expectationWithDescription("Created Invitation")

        self.createAndTestInvitation(createSharingInvitationDone, invitation: SharingUsers.invitationReadAndUpdate, capabilities: self.readAndUpdateCapabilities)
    }

    // 1c)
    func testPreparationCreatePersistedInvitation3() {
        let createSharingInvitationDone = self.expectationWithDescription("Created Invitation")

        self.createAndTestInvitation(createSharingInvitationDone, invitation: SharingUsers.invitationInvite, capabilities: self.inviteCapabilities)
    }
    
    // 2) Don't yet sign out of the OwningUser account, and run this.
    func testThatGettingLinkedAccountsByOwningUserFails() {
        let checkRedeemedInvitations = self.expectationWithDescription("Check Invitation")

        self.waitUntilSyncServerUserSignin() {
            SMSyncServerUser.session.getLinkedAccountsForSharingUser { (linkedAccounts, error) in
                XCTAssert(error != nil)
                checkRedeemedInvitations.fulfill()
            }
        }
        
        self.waitForExpectations()
    }
    
    // 3) NOW: Launch app, without running testing, signout as the owning user, and sign in as a sharing (Facebook) user. 
    // Then, run the following test:
    func testThatInvitationWasRedeemed() {
        let checkRedeemedInvitations = self.expectationWithDescription("Check Invitation")

        self.waitUntilSyncServerUserSignin() {
            // Use REST API call to check which linked/shared accounts we have.
            SMSyncServerUser.session.getLinkedAccountsForSharingUser { (linkedAccounts, error) in
                XCTAssert(error == nil)
                XCTAssert(linkedAccounts != nil)
                XCTAssert(linkedAccounts!.count == 1)
                XCTAssert(linkedAccounts![0].capabilityMask == self.readCapabilities)
                checkRedeemedInvitations.fulfill()
            }
        }
        
        self.waitForExpectations()
    }
    
    // Must be signed in as a sharing user.
    // 4)
    func testThatRedeemingAlreadyRedeemedInvitationFails() {
        Assert.If(SharingUsers.invitationRead.stringValue == "", thenPrintThisString: "Haven't yet set up invitationCode")
        
        let redeemedSharingInvitationDone = self.expectationWithDescription("Redeemed Invitation")
        
        self.waitUntilSyncServerUserSignin() {
            SMSyncServerUser.session.redeemSharingInvitation(invitationCode: SharingUsers.invitationRead.stringValue) { (linkedOwningUserId, error) in
                XCTAssert(linkedOwningUserId == nil)
                XCTAssert(error != nil)
                redeemedSharingInvitationDone.fulfill()
            }
        }
        
        self.waitForExpectations()
    }
    
    // 5) Sharing user signed in.
    func testThatRedeemingEmptyInvitationFails() {
        let redeemAttemptDone = self.expectationWithDescription("Redeem Attempt Done")
        
        self.waitUntilSyncServerUserSignin() {
            SMSyncServerUser.session.redeemSharingInvitation(invitationCode: "") { (linkedOwningUserId, error) in
                XCTAssert(linkedOwningUserId == nil)
                XCTAssert(error != nil)
                redeemAttemptDone.fulfill()
            }
        }
        
        self.waitForExpectations()
    }

    // 6) Sharing user signed in.
    func testThatMinimalCapabilitySharingUserCannotCreateSharingInvitation() {
        let createSharingInvitationDone = self.expectationWithDescription("Created Invitation")
        
        self.waitUntilSyncServerUserSignin() {
            SMServerAPI.session.createSharingInvitation(capabilities: [.Read]) { (invitationCode, apiResult) in
                XCTAssert(apiResult.error != nil)
                XCTAssert(invitationCode == nil)
                createSharingInvitationDone.fulfill()
            }
        }
        
        self.waitForExpectations()
    }

    // 7) Sharing user signed in.
    func testThatRedeemingInvitationFromSameOwningUserAccountOverwrites() {
        Assert.If(SharingUsers.invitationReadAndUpdate.stringValue == "", thenPrintThisString: "Haven't yet set up invitationCode")
        
        let redeemedSharingInvitationDone = self.expectationWithDescription("Redeemed Invitation")
        let checkRedeemedInvitations = self.expectationWithDescription("Check Redeemed")
        
        self.waitUntilSyncServerUserSignin() {
            SMSyncServerUser.session.redeemSharingInvitation(invitationCode: SharingUsers.invitationReadAndUpdate.stringValue) { (linkedOwningUserId, error) in
                XCTAssert(linkedOwningUserId != nil)
                XCTAssert(error == nil)
                redeemedSharingInvitationDone.fulfill()
                
                SMSyncServerUser.session.getLinkedAccountsForSharingUser { (linkedAccounts, error) in
                    XCTAssert(error == nil)
                    XCTAssert(linkedAccounts != nil)
                    
                    // Here's the critical bit: We should still just have a single linked account.
                    XCTAssert(linkedAccounts!.count == 1)
                    
                    XCTAssert(linkedAccounts![0].capabilityMask == self.readAndUpdateCapabilities)
                    checkRedeemedInvitations.fulfill()
                }
            }
        }
        
        self.waitForExpectations()
    }

    // 8) Sharing user signed in.
    func testThatInviteCapabilitySharingUserCanCreateSharingInvitation() {
        Assert.If(SharingUsers.invitationInvite.stringValue == "", thenPrintThisString: "Haven't yet set up invitationCode")
        
        let redeemedSharingInvitationDone = self.expectationWithDescription("Redeemed Invitation")
        let createSharingInvitationDone = self.expectationWithDescription("Created Invitation")
        
        self.waitUntilSyncServerUserSignin() {
            SMSyncServerUser.session.redeemSharingInvitation(invitationCode: SharingUsers.invitationInvite.stringValue) { (linkedOwningUserId, error) in
                XCTAssert(linkedOwningUserId != nil)
                XCTAssert(error == nil)
                redeemedSharingInvitationDone.fulfill()
                
                self.createAndTestInvitation(createSharingInvitationDone, invitation: SharingUsers.invitationInvite2, capabilities: self.inviteCapabilities)
            }
        }
        
        self.waitForExpectations()
    }
    
    func testThatRedeemingExpiredInvitationFails() {
        XCTFail()
    }
}
