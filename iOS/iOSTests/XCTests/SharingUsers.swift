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
    private static var invitationDownloader = SMPersistItemString(name: "SharingUsers.invitationDownloader", initialStringValue: "", persistType: .UserDefaults)
    private static var invitationUploader = SMPersistItemString(name: "SharingUsers.invitationUploader", initialStringValue: "", persistType: .UserDefaults)
    private static var invitationAdmin1 = SMPersistItemString(name: "SharingUsers.invitationAdmin1", initialStringValue: "", persistType: .UserDefaults)
    private static var invitationAdmin2 = SMPersistItemString(name: "SharingUsers.invitationAdmin2", initialStringValue: "", persistType: .UserDefaults)

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    // MARK: Server-level API testing: operationCreateSharingInvitation
    
    func doTestSendSharingTypeToServerExpectingError(sharingType:String?) {
        let createSharingInvitationDone = self.expectationWithDescription("Created Invitation")
        
        self.waitUntilSyncServerUserSignin() {
            SMServerAPI.session.createSharingInvitation(sharingType: sharingType, completion: { (authorizationCode, apiResult) in
                XCTAssert(apiResult.error != nil)
                XCTAssert(authorizationCode == nil)
                createSharingInvitationDone.fulfill()
            })
        }
        
        self.waitForExpectations()
    }
    
    func testThatSendingNilSharingTypeToServerFails() {
        self.doTestSendSharingTypeToServerExpectingError(nil)
    }
    
    // One of the capabilities in the string array sent is bad. E.g., give "ReadIt".
    func testThatSendingInvalidSharingTypeToServerFails() {
        self.doTestSendSharingTypeToServerExpectingError("ReadIt")
    }

    func doTestSendSharingTypeToServerExpectingNoError(sharingType:SMSharingType) {
        let createSharingInvitationDone = self.expectationWithDescription("Created Invitation")
        let lookupSharingInvitationDone = self.expectationWithDescription("Lookup Invitation")
        
        self.waitUntilSyncServerUserSignin() {
            SMServerAPI.session.createSharingInvitation(sharingType:sharingType.rawValue, completion: { (invitationCode, apiResult) in
                XCTAssert(apiResult.error == nil)
                XCTAssert(invitationCode != nil)
                createSharingInvitationDone.fulfill()
                
                SMServerAPI.session.lookupSharingInvitation(invitationCode: invitationCode!, completion: { (invitationContents, apiResult) in
                    
                    XCTAssert(apiResult.error == nil)
                    XCTAssert(invitationContents != nil)

                    // Make sure the expiry date is about 24 hours advanced from now.
                    let beforeExpiryDate = NSDate().plusMinutes(23.99*60)
                    let afterExpiryDate = NSDate().plusMinutes(24.01*60)
                    
                    if invitationContents!.expiryDate.withinRange(beforeExpiryDate, endDate: afterExpiryDate) {
                        lookupSharingInvitationDone.fulfill()
                    }
                    else {
                        XCTFail()
                    }
                })
            })
        }
        
        self.waitForExpectations()
    }
    
    func testThatSendingDownloaderWorks() {
        self.doTestSendSharingTypeToServerExpectingNoError(.Downloader)
    }
    
    func testThatSendingUploaderWorks() {
        self.doTestSendSharingTypeToServerExpectingNoError(.Uploader)
    }
    
    func testThatSendingAdminWorks() {
        self.doTestSendSharingTypeToServerExpectingNoError(.Admin)
    }
    
    func testThatRedeemingSharingInvitationByOwningExclusiveUserFails() {
        let createSharingInvitationDone = self.expectationWithDescription("Created Invitation")
        let redeemSharingInvitationDone = self.expectationWithDescription("Created Invitation")
        
        self.waitUntilSyncServerUserSignin() {
            SMServerAPI.session.createSharingInvitation(sharingType: SMSharingType.Downloader.rawValue, completion: { (invitationCode, apiResult) in
                XCTAssert(apiResult.error == nil)
                XCTAssert(invitationCode != nil)
                createSharingInvitationDone.fulfill()
                
                SMSyncServerUser.session.redeemSharingInvitation(invitationCode: invitationCode!) { (linkedOwningUserId, error) in
                    XCTAssert(linkedOwningUserId == nil)
                    XCTAssert(error != nil)
                    redeemSharingInvitationDone.fulfill()
                }
            })
        }
        
        self.waitForExpectations()
    }
    
    // The following tests are disabled because either you have to do them in a particular order, or you have to make sure to sign in to the right account to carry them out.

    func createAndTestInvitation(expectation:XCTestExpectation, waitUntilSignIn:Bool=true, invitation:SMPersistItemString, sharingType:SMSharingType, testCompleted:(()->())?=nil) {
        
        func createInvitation() {
            SMServerAPI.session.createSharingInvitation(sharingType: sharingType.rawValue, completion: { (invitationCode, apiResult) in
                XCTAssert(apiResult.error == nil)
                XCTAssert(invitationCode != nil)
                invitation.stringValue = invitationCode!
                expectation.fulfill()
                testCompleted?()
            })
        }
        
        if waitUntilSignIn {
            self.waitUntilSyncServerUserSignin() {
                createInvitation()
            }
        
            self.waitForExpectations()
        }
        else {
            createInvitation()
        }
    }

    // This needs to be run *first* before any of the redeeming tests. Run this when you are signed into an OwningUser account (e.g., Google). Do this and the following two tests in a sequence.
    // 1a)
    func testPreparationCreatePersistedInvitation1() {
        let createSharingInvitationDone = self.expectationWithDescription("Created Invitation")
    
        self.createAndTestInvitation(createSharingInvitationDone, invitation:  SharingUsers.invitationDownloader, sharingType: SMSharingType.Downloader) {
            
            // So I can run test 3), manually.
            AppDelegate.sharingInvitationCode = SharingUsers.invitationDownloader.stringValue
        }
    }

    // 1b)
    func testPreparationCreatePersistedInvitation2() {
        let createSharingInvitationDone = self.expectationWithDescription("Created Invitation")

        self.createAndTestInvitation(createSharingInvitationDone, invitation: SharingUsers.invitationUploader, sharingType: SMSharingType.Uploader)
    }

    // 1c)
    func testPreparationCreatePersistedInvitation3() {
        let createSharingInvitationDone = self.expectationWithDescription("Created Invitation")

        self.createAndTestInvitation(createSharingInvitationDone, invitation: SharingUsers.invitationAdmin1, sharingType: SMSharingType.Admin)
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
                XCTAssert(linkedAccounts![0].sharingType == .Downloader)
                checkRedeemedInvitations.fulfill()
            }
        }
        
        self.waitForExpectations()
    }
    
    // Must be signed in as a sharing user.
    // 4)
    func testThatRedeemingAlreadyRedeemedInvitationFails() {
        Assert.If(SharingUsers.invitationDownloader.stringValue == "", thenPrintThisString: "Haven't yet set up invitationCode")
        
        let redeemedSharingInvitationDone = self.expectationWithDescription("Redeemed Invitation")
        
        self.waitUntilSyncServerUserSignin() {
            SMSyncServerUser.session.redeemSharingInvitation(invitationCode: SharingUsers.invitationDownloader.stringValue) { (linkedOwningUserId, error) in
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
            SMServerAPI.session.createSharingInvitation(sharingType: SMSharingType.Downloader.rawValue) { (invitationCode, apiResult) in
                XCTAssert(apiResult.error != nil)
                XCTAssert(invitationCode == nil)
                createSharingInvitationDone.fulfill()
            }
        }
        
        self.waitForExpectations()
    }

    // 7) Sharing user signed in.
    func testThatRedeemingInvitationFromSameOwningUserAccountOverwrites() {
        Assert.If(SharingUsers.invitationUploader.stringValue == "", thenPrintThisString: "Haven't yet set up invitationCode")
        
        let redeemedSharingInvitationDone = self.expectationWithDescription("Redeemed Invitation")
        let checkRedeemedInvitations = self.expectationWithDescription("Check Redeemed")
        let idleExpectation = self.expectationWithDescription("Idle")

        self.waitUntilSyncServerUserSignin() {
            SMSyncServerUser.session.redeemSharingInvitation(invitationCode: SharingUsers.invitationUploader.stringValue) { (linkedOwningUserId, error) in
                XCTAssert(linkedOwningUserId != nil)
                XCTAssert(error == nil)
                redeemedSharingInvitationDone.fulfill()
                
                // Wait for idle after getLinkedAccountsForSharingUser completes-- because the signin callbacks, which occur after redeemSharingInvitation, will cause a check for downloads.
                self.idleCallbacks.append() {
                    idleExpectation.fulfill()
                }
                
                SMSyncServerUser.session.getLinkedAccountsForSharingUser { (linkedAccounts, error) in
                    XCTAssert(error == nil)
                    XCTAssert(linkedAccounts != nil)
                    
                    // Here's the critical bit: We should still just have a single linked account.
                    XCTAssert(linkedAccounts!.count == 1)
                    
                    XCTAssert(linkedAccounts![0].sharingType == SMSharingType.Uploader)
                    checkRedeemedInvitations.fulfill()
                }
            }
        }
        
        self.waitForExpectations()
    }
    
    // 7b) Now signed in as uploader capability sharing user.
    func testThatUploaderCapabilitySharingUserCannotCreateSharingInvitation() {
        let createSharingInvitationDone = self.expectationWithDescription("Created Invitation")
        
        self.waitUntilSyncServerUserSignin() {
            SMServerAPI.session.createSharingInvitation(sharingType: SMSharingType.Downloader.rawValue) { (invitationCode, apiResult) in
                XCTAssert(apiResult.error != nil)
                XCTAssert(invitationCode == nil)
                createSharingInvitationDone.fulfill()
            }
        }
        
        self.waitForExpectations()
    }

    // 8) Sharing user signed in.
    func testThatInviteCapabilitySharingUserCanCreateSharingInvitation() {
        Assert.If(SharingUsers.invitationAdmin1.stringValue == "", thenPrintThisString: "Haven't yet set up invitationCode")
        
        let redeemedSharingInvitationDone = self.expectationWithDescription("Redeemed Invitation")
        let createSharingInvitationDone = self.expectationWithDescription("Created Invitation")
        let idleExpectation = self.expectationWithDescription("Idle")
        
        self.waitUntilSyncServerUserSignin() {
            // Wait for idle-- because the signin callbacks, which occur after redeemSharingInvitation, will cause a check for downloads.
            self.idleCallbacks.append() {
                idleExpectation.fulfill()
            }
            
            SMSyncServerUser.session.redeemSharingInvitation(invitationCode: SharingUsers.invitationAdmin1.stringValue) { (linkedOwningUserId, error) in
                XCTAssert(linkedOwningUserId != nil)
                XCTAssert(error == nil)
                redeemedSharingInvitationDone.fulfill()
                
                self.createAndTestInvitation(createSharingInvitationDone, waitUntilSignIn:false, invitation: SharingUsers.invitationAdmin2, sharingType: .Admin)
            }
        }
        
        self.waitForExpectations()
    }
    
    // BEFORE RUNNING THIS TEST: Manually modify that last created admin invitation in the Mongo database, and make it old.
    func testThatRedeemingExpiredInvitationFails() {
        Assert.If(SharingUsers.invitationAdmin2.stringValue == "", thenPrintThisString: "Haven't yet set up invitationCode")
        
        let redeemedSharingInvitationDone = self.expectationWithDescription("Redeemed Invitation")
        
        self.waitUntilSyncServerUserSignin() {
            // We won't get the idle callback this time, because the signin callbacks won't complete.
            /*
            self.idleCallbacks.append() {
                idleExpectation.fulfill()
            }
            */
            
            SMSyncServerUser.session.redeemSharingInvitation(invitationCode: SharingUsers.invitationAdmin2.stringValue) { (linkedOwningUserId, error) in
                XCTAssert(linkedOwningUserId == nil)
                XCTAssert(error != nil)
                redeemedSharingInvitationDone.fulfill()
            }
        }
        
        self.waitForExpectations()
    }
}
