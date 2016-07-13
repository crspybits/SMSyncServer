//
//  SharingUserOperations.swift
//  Tests
//
//  Created by Christopher Prince on 6/17/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import XCTest
import SMCoreLib
@testable import SMSyncServer

class SharingUserOperations: BaseClass {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    enum TestCases {
    // First mask should just one; second can have more
    case Except(SMSharingUserCapabilityMask, SMSharingUserCapabilityMask)
    case AtLeast(SMSharingUserCapabilityMask, SMSharingUserCapabilityMask)
    }
    
    // Creating invitations for these specific test cases.
    let specificTestCases:[(TestCases, String)] = [
        (.Except(.Create, [.Update]),           "ExceptCreate"),
        (.Except(.Create, [.Delete, .Invite]),  "ExceptCreate"),
        (.AtLeast(.Create, [.Create]),          "AtLeastCreate"),
        (.AtLeast(.Create, [.Create, .Delete]), "AtLeastCreate"),
        
        (.Except(.Update, [.Create]),           "ExceptUpdate"),
        (.Except(.Update, [.Read, .Delete]),    "ExceptUpdate"),
        (.AtLeast(.Update, [.Update]),          "AtLeastUpdate"),
        (.AtLeast(.Update, [.ALL]),             "AtLeastUpdate"),
        
        (.Except(.Delete, [.Create]),           "ExceptDelete"),
        (.Except(.Delete, [.Read, .Create]),    "ExceptDelete"),
        (.AtLeast(.Delete, [.Delete]),          "AtLeastDelete"),
        (.AtLeast(.Delete, [.Update, .Delete]), "AtLeastDelete"),
        
        (.Except(.Read, [.Create]),             "ExceptRead"),
        (.Except(.Read, [.Delete, .Create]),    "ExceptRead"),
        (.AtLeast(.Read, [.Read]),              "AtLeastRead"),
        (.AtLeast(.Read, [.ALL]),               "AtLeastRead")
    ]
    
    func convertTestCases() -> [(TestCases, SMPersistItemString)] {
        var result = [(TestCases, SMPersistItemString)] ()
        var counter = 1
        for (testCase, persistItemShortName) in self.specificTestCases {
            let persistItemName = "SharingUserOperations.\(persistItemShortName)\(counter)"
            counter += 1
            let persistItem = SMPersistItemString(name: persistItemName, initialStringValue: "", persistType: .UserDefaults)
            result.append((testCase, persistItem))
        }
        
        return result
    }
    
    // Do this before any of the following tests.
    // Must be signed in as owning user or sharing user with invite capability
    func createInvitations(testCases:[(TestCases, SMPersistItemString)], testCaseIndex:Int, completed:(()->())?) {
        
        if testCaseIndex < testCases.count {
            let (testCase, persistItem) = testCases[testCaseIndex]
            var capabilities:SMSharingUserCapabilityMask
            
            switch testCase {
            case .AtLeast(_, let caps):
                capabilities = caps
            case .Except(_, let caps):
                capabilities = caps
            }
            
            SMServerAPI.session.createSharingInvitation(capabilities: capabilities, completion: { (invitationCode, apiResult) in
                XCTAssert(apiResult.error == nil)
                XCTAssert(invitationCode != nil)
                persistItem.stringValue = invitationCode!

                self.createInvitations(testCases, testCaseIndex: testCaseIndex+1, completed: completed)
            })
        }
    }
    
    func testCreateInvitations() {
        let testCases = self.convertTestCases()
        let createSharingInvitationDone = self.expectationWithDescription("Done Creating")
        
        self.extraServerResponseTime = Double(testCases.count) * 20
        
        self.waitUntilSyncServerUserSignin() {
            self.createInvitations(testCases, testCaseIndex: 0) {
                createSharingInvitationDone.fulfill()
            }
        }
    
        self.waitForExpectations()
    }
    
    // Capabilities: Any/all except Create
    func testThatUploadOfNewFileByUnauthorizedSharingUserFails() {
    }
    
    // Capabilities: At least Create
    func testThatUploadOfNewFileByAuthorizedSharingUserWorks() {
    }
    
    // Capabilities: Any/all except Update
    func testThatUploadOfExistingFileByUnauthorizedSharingUserFails() {
    }
    
    // Capabilities: At least Update
    func testThatUploadOfExistingFileByAuthorizedSharingUserWorks() {
    }
    
    // Capabilities: Any/all except Delete
    func testThatDeletionOfFileByUnauthorizedSharingUserFails() {
    }
    
    // Capabilities: At least Delete
    func testThatDeletionOfFileByAuthorizedSharingUserWorks() {
    }
    
    // Capabilities: Any/all except Read
    func testThatDownloadOfFileByUnauthorizedSharingUserFails() {
    }
    
    // Capabilities: At least Read
    func testThatDownloadOfFileByAuthorizedSharingUserWorks() {
    }
}
