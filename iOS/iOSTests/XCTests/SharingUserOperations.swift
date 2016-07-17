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

    var downloadingInvitations = [SMPersistItemString]()
    var uploadingInvitations = [SMPersistItemString]()
    var adminInvitations = [SMPersistItemString]()
    let numberInvitationsPerType = 5
    
    func setupPersistentInvitationsFor(sharingType:SMSharingType, inout result:[SMPersistItemString]) {
        for invitationNumber in 1...numberInvitationsPerType {
            let persisentInvitationName =
                "SharingUsers.invitation\(sharingType.rawValue).\(invitationNumber)"
            let persisentInvitation = SMPersistItemString(name: persisentInvitationName, initialStringValue: "", persistType: .UserDefaults)
            result.append(persisentInvitation)
        }
    }
    
    override func setUp() {
        super.setUp()
        
        self.setupPersistentInvitationsFor(.Downloader, result: &self.downloadingInvitations)
        self.setupPersistentInvitationsFor(.Uploader, result: &self.uploadingInvitations)
        self.setupPersistentInvitationsFor(.Admin, result: &self.adminInvitations)
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func createInvitations(sharingType sharingType:SMSharingType, invitationNumber:Int, inout persistentInvitations:[SMPersistItemString], completed:(()->())?) {
        
        if invitationNumber < self.numberInvitationsPerType {
            
            SMServerAPI.session.createSharingInvitation(sharingType: sharingType.rawValue, completion: { (invitationCode, apiResult) in
                XCTAssert(apiResult.error == nil)
                XCTAssert(invitationCode != nil)
                
                persistentInvitations[invitationNumber].stringValue = invitationCode!

                self.createInvitations(sharingType: sharingType, invitationNumber: invitationNumber+1, persistentInvitations: &persistentInvitations, completed: completed)
            })
        }
        else {
            completed?()
        }
    }
    
    func createDownloadingInvitations(completed:()->()) {
        self.createInvitations(sharingType:.Downloader, invitationNumber:0, persistentInvitations: &self.downloadingInvitations) {
            completed()
        }
    }
    
    func createUploadingInvitations(completed:()->()) {
        self.createInvitations(sharingType:.Uploader, invitationNumber:0, persistentInvitations: &self.uploadingInvitations) {
            completed()
        }
    }
    
    func createAdminInvitations(completed:()->()) {
        self.createInvitations(sharingType:.Admin, invitationNumber:0, persistentInvitations: &self.adminInvitations) {
            completed()
        }
    }
    
    // Do this before any of the following tests.
    // Must be signed in as owning user or sharing user with invite capability
    func testCreateInvitations() {
        let createSharingInvitationDone = self.expectationWithDescription("Done Creating")
        self.extraServerResponseTime = Double(self.numberInvitationsPerType) * 3 * 20
        
        self.waitUntilSyncServerUserSignin() {
            self.createDownloadingInvitations() {
                self.createUploadingInvitations() {
                    self.createAdminInvitations() {
                        createSharingInvitationDone.fulfill()
                    }
                }
            }
        }
    
        self.waitForExpectations()
    }
    
    func uploadFileExpectingFailure() {
    }
    
    /*
    func uploadFiles(testFiles:[TestFile], uploadExpectations:[XCTestExpectation]?, commitComplete:XCTestExpectation?, idleExpectation:XCTestExpectation,
        complete:(()->())?) {
        
        for testFileIndex in 0...testFiles.count-1 {
            let testFile = testFiles[testFileIndex]
            let uploadExpectation:XCTestExpectation? = uploadExpectations?[testFileIndex]
        
            try! SMSyncServer.session.uploadImmutableFile(testFile.url, withFileAttributes: testFile.attr)
            
            if uploadExpectation != nil {
                self.singleUploadCallbacks.append() { uuid in
                    XCTAssert(uuid.UUIDString == testFile.uuidString)
                    uploadExpectation!.fulfill()
                }
            }
        }

        // The .Idle callback gets called first
        self.idleCallbacks.append() {
            if commitComplete == nil {
                complete?()
            }
            idleExpectation.fulfill()
        }
        
        if commitComplete != nil {
            // Followed by the commit complete callback.
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == testFiles.count)
                commitComplete!.fulfill()
                self.checkFileSizes(testFiles, complete: complete)
            }
        }
        
        try! SMSyncServer.session.commit()
    }
    */
    
    // For the rest: Must be signed in as sharing user.
    
    // Test the following two when having redeemed *no* invitations. (i.e., the minimum capabilities in a sharing invitation is for downloading).
    func testThatFileDownloadByUnauthorizedSharingUserFails() {
    }

    func testThatDownloadDeletionByUnauthorizedSharingUserFails() {
    }
    
    func testThatFileDownloadByDownloadSharingUserWorks() {
        // Redeem Download invitation first.
    }
    
    func testThatDownloadDeletionByDownloadSharingUserWorks() {
        // Redeem Download invitation first.
    }
    
    func testThatDownloadDeletionByUploadSharingUserWorks() {
        // Redeem Upload invitation first.
    }
    
    func testThatFileDownloadByUploadSharingUserWorks() {
        // Redeem Upload invitation first.
    }
    
    func testThatDownloadDeletionByAdminSharingUserWorks() {
        // Redeem Admin invitation first.
    }
    
    func testThatFileDownloadByAdminSharingUserWorks() {
        // Redeem Admin invitation first.
    }
    
    //MARK: Upload tests
    
    func testThatFileUploadByDownloadingSharingUserFails() {
        // Redeem Download invitation first.
    }
    
    func testThatUploadDeletionByDownloadingSharingUserFails() {
        // Redeem Download invitation first.
    }
    
    func testThatFileUploadByUploadSharingUserWorks() {
        // Redeem Upload invitation first.
    }
    
    func testThatUploadDeletionByUploadSharingUserWorks() {
        // Redeem Upload invitation first.
    }
    
    func testThatFileUploadByAdminSharingUserWorks() {
        // Redeem Admin invitation first.
    }
    
    func testThatUploadDeletionByAdminSharingUserWorks() {
        // Redeem Admin invitation first.
    }

    //MARK: Invitation tests
    
    func testThatInvitationByDownloadingSharingUserFails() {
        // Redeem Download invitation first.
    }
    
    func testThatInvitationByUploadSharingUserFails() {
        // Redeem Upload invitation first.
    }
    
    func testThatInvitationByAdminSharingUserWorks() {
        // Redeem Admin invitation first.
    }
}
