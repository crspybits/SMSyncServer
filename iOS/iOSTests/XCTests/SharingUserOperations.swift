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
@testable import Tests

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
    
    var uploadFile1:TestFile!
    var uploadFile2:TestFile!
    let uploadFile1UUID = SMPersistItemString(name: "SharingUserOperations.uploadFile1", initialStringValue: "", persistType: .UserDefaults)
    let uploadFile2UUID = SMPersistItemString(name: "SharingUserOperations.uploadFile2", initialStringValue: "", persistType: .UserDefaults)
    
    func createUploadFiles(initial initial:Bool) {
        if initial {
            self.uploadFile1 = TestBasics.session.createTestFile("FileDownloadByDownloadSharingUser")
            self.uploadFile1UUID.stringValue = self.uploadFile1.uuidString
            
            self.uploadFile2 = TestBasics.session.createTestFile("DownloadDeletionByDownloadSharingUser")
            self.uploadFile2UUID.stringValue = self.uploadFile2.uuidString
        }
        else {
            self.uploadFile1 = TestBasics.session.recreateTestFile(fromUUID: self.uploadFile1UUID.stringValue)
            self.uploadFile2 = TestBasics.session.recreateTestFile(fromUUID: self.uploadFile2UUID.stringValue)
        }
    }

    // Do this before any of the following tests.
    // Must be signed in as Owning User.
    func testSetupRemainingTests() {
        let setupDone = self.expectationWithDescription("Done Setup")
        self.extraServerResponseTime = Double(self.numberInvitationsPerType) * 3 * 20
        let uploadExpectations1 = UploadFileExpectations(fromTestClass: self)
        let uploadExpectations2 = UploadFileExpectations(fromTestClass: self)
        let uploadDeletionExpectations = UploadDeletionExpectations(fromTestClass: self)
       
        self.createUploadFiles(initial:true)
        
        self.waitUntilSyncServerUserSignin() {
            self.createDownloadingInvitations() {
                self.createUploadingInvitations() {
                    self.createAdminInvitations() {
                    
                        SMServerAPI.session.createSharingInvitation(sharingType: SMSharingType.Downloader.rawValue, completion: { (invitationCode, apiResult) in
                            XCTAssert(apiResult.error == nil)
                            XCTAssert(invitationCode != nil)
                            
                            // So I can sign in as a sharing user below.
                            AppDelegate.sharingInvitationCode = invitationCode!
                            
                            self.uploadFile(self.uploadFile1, expectations: uploadExpectations1) {
                                self.uploadFile(self.uploadFile2, expectations: uploadExpectations2) {
                                    self.uploadDeletion(self.uploadFile2, expectation: uploadDeletionExpectations) {
                                        setupDone.fulfill()
                                    }
                                }
                            }
                        })
                    }
                }
            }
        }
    
        self.waitForExpectations()
    }
 
    class UploadFileExpectations {
        var uploadCompleteCallbackExpectation:XCTestExpectation
        var singleUploadExpectation:XCTestExpectation
        var idleExpectation:XCTestExpectation
        
        init(fromTestClass testClass:XCTestCase) {
            self.uploadCompleteCallbackExpectation = testClass.expectationWithDescription("Commit Complete")
            self.singleUploadExpectation = testClass.expectationWithDescription("Upload Complete")
            self.idleExpectation = testClass.expectationWithDescription("Idle")
        }
    }
    
    class DownloadFileExpectations {
        var singleDownloadExpectation:XCTestExpectation
        var allDownloadsCompleteExpectation:XCTestExpectation
        var idleExpectation:XCTestExpectation
        
        init(fromTestClass testClass:XCTestCase) {
            self.singleDownloadExpectation = testClass.expectationWithDescription("Single Download")
            self.allDownloadsCompleteExpectation = testClass.expectationWithDescription("All Downloads Complete")
            self.idleExpectation = testClass.expectationWithDescription("Idl1")
        }
    }
    
    class UploadDeletionExpectations {
        var deletionExpectation:XCTestExpectation
        var idleExpectation:XCTestExpectation
        var commitCompleteExpectation:XCTestExpectation
        
        init(fromTestClass testClass:XCTestCase) {
            self.deletionExpectation = testClass.expectationWithDescription("Deletion")
            self.idleExpectation = testClass.expectationWithDescription("Idle Complete")
            self.commitCompleteExpectation = testClass.expectationWithDescription("Commit")
        }
    }
    
    class DownloadDeletionExpectations {
        var clientShouldDeleteFilesExpectation:XCTestExpectation
        var idle:XCTestExpectation
        
        init(fromTestClass testClass:XCTestCase) {
            self.clientShouldDeleteFilesExpectation = testClass.expectationWithDescription("Deletion")
            self.idle = testClass.expectationWithDescription("Idle Complete")
        }
    }
    
    func uploadFile(testFile:TestFile, expectations:UploadFileExpectations, failureExpected:Bool=false, complete:(()->())?=nil) {
        try! SMSyncServer.session.uploadImmutableFile(testFile.url, withFileAttributes: testFile.attr)
        
        self.singleUploadCallbacks.append() { uuid in
            XCTAssert(uuid.UUIDString == testFile.uuidString)
            expectations.singleUploadExpectation.fulfill()
        }
        
        self.idleCallbacks.append() {
            expectations.idleExpectation.fulfill()
        }
        
        if failureExpected {
            self.errorCallbacks.append() {
                SMSyncServer.session.cleanupFile(testFile.uuid)
                CoreData.sessionNamed(CoreDataTests.name).removeObject(
                    testFile.appFile)
                CoreData.sessionNamed(CoreDataTests.name).saveContext()
                
                SMSyncServer.session.resetFromError() { error in
                    XCTAssert(error == nil)
                    expectations.uploadCompleteCallbackExpectation.fulfill()
                }
            }
        }
        else {
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(testFile.uuidString, size: testFile.sizeInBytes) {
                    expectations.uploadCompleteCallbackExpectation.fulfill()
                    complete?()
                }
            }
        }
        
        try! SMSyncServer.session.commit()
    }
    
    func downloadFile(testFile:TestFile, expectations:DownloadFileExpectations,
        complete:(()->())?=nil) {
        var numberDownloads = 0
        
        SMSyncServer.session.resetMetaData(forUUID: NSUUID(UUIDString: self.uploadFile1UUID.stringValue)!)

        self.singleDownload.append() { (downloadedFile:NSURL, downloadedFileAttr: SMSyncAttributes) in
            XCTAssert(downloadedFileAttr.uuid.UUIDString == testFile.uuidString)
            let filesAreTheSame = SMFiles.compareFiles(file1: testFile.url, file2: downloadedFile)
            XCTAssert(filesAreTheSame)
            numberDownloads += 1
            expectations.singleDownloadExpectation.fulfill()
        }
        
        self.shouldSaveDownloads.append() { downloadedFiles, ack in
            XCTAssert(numberDownloads == 1)
            XCTAssert(downloadedFiles.count == 1)
            let (_, _) = downloadedFiles[0]
            expectations.allDownloadsCompleteExpectation.fulfill()
            ack()
        }
        
        self.idleCallbacks.append() {
            expectations.idleExpectation.fulfill()
            complete?()
        }
        
        // Force the check for downloads.
        SMSyncControl.session.nextSyncOperation()
    }
    
    func uploadDeletion(testFile:TestFile, expectation:UploadDeletionExpectations,
        complete:(()->())?=nil) {

        try! SMSyncServer.session.deleteFile(testFile.uuid)
        
        self.deletionCallbacks.append() { uuids in
            XCTAssert(uuids.count == 1)
            XCTAssert(uuids[0].UUIDString == testFile.uuidString)
            expectation.deletionExpectation.fulfill()
        }
        
        // The .Idle callback gets called first
        self.idleCallbacks.append() {
            expectation.idleExpectation.fulfill()
        }
        
        // Followed by the commit complete.
        self.commitCompleteCallbacks.append() { numberDeletions in
            Log.msg("commitCompleteCallbacks: deleteFiles")
            XCTAssert(numberDeletions == 1)
            
            let fileAttr = SMSyncServer.session.localFileStatus(testFile.uuid)
            XCTAssert(fileAttr != nil)
            XCTAssert(fileAttr!.deleted!)
            
            expectation.commitCompleteExpectation.fulfill()
            complete?()
        }
    
        try! SMSyncServer.session.commit()
    }
    
    func downloadDeletion(testFile:TestFile, expectation:DownloadDeletionExpectations,
        complete:(()->())?=nil) {
        
        SMSyncServer.session.resetMetaData(forUUID: testFile.uuid, resetType: .Undelete)

        self.shouldDoDeletions.append() { deletions, acknowledgement in
            XCTAssert(deletions.count == 1)
            let attr = deletions[0]

            XCTAssert(attr.uuid.UUIDString == testFile.uuidString)
            
            let fileAttr = SMSyncServer.session.localFileStatus(testFile.uuid)
            XCTAssert(fileAttr != nil)
            XCTAssert(fileAttr!.deleted!)
            
            expectation.clientShouldDeleteFilesExpectation.fulfill()
            acknowledgement()
        }

        self.idleCallbacks.append() {
            expectation.idle.fulfill()
            complete?()
        }
        
        SMSyncControl.session.nextSyncOperation()
    }
    
    // These two tests have no meaning. In order for a sharing user to sign in to the system, they must have some capabilities-- i.e., they must have at least Downloader capabilities. Thus, the following two tests cannot be carried out.
    /*
    func testThatFileDownloadByUnauthorizedSharingUserFails() {
    }

    func testThatDownloadDeletionByUnauthorizedSharingUserFails() {
    }
    */
    
    // ***** For the rest: Must be signed in as sharing user.
    // 1) Startup the app in Xcode, not doing a test.
    // 2) Sign out of owning user. 
    // 3) Sign in as Facebook user.
    
    func testThatFileDownloadByDownloadSharingUserWorks() {
        // Redeem Download invitation first.
        let downloadInvitation = 0
        let invitationCode = self.downloadingInvitations[downloadInvitation].stringValue
        
        let expectations = DownloadFileExpectations(fromTestClass: self)
        
        self.extraServerResponseTime = 30
        
        self.createUploadFiles(initial:false)
        
        self.waitUntilSyncServerUserSignin() {
            SMSyncServerUser.session.redeemSharingInvitation(invitationCode: invitationCode) { (linkedOwningUserId, error) in
                XCTAssert(linkedOwningUserId == nil)
                XCTAssert(error != nil)
                
                self.downloadFile(self.uploadFile1, expectations: expectations)
            }
        }
        
        self.waitForExpectations()
    }
    
    func testThatDownloadDeletionByDownloadSharingUserWorks() {
        // Redeem Download invitation first.
        let downloadInvitation = 1
        let invitationCode = self.downloadingInvitations[downloadInvitation].stringValue
        
        let expectations = DownloadDeletionExpectations(fromTestClass: self)
        
        self.extraServerResponseTime = 30
        
        self.createUploadFiles(initial:false)
        
        self.waitUntilSyncServerUserSignin() {
            SMSyncServerUser.session.redeemSharingInvitation(invitationCode: invitationCode) { (linkedOwningUserId, error) in
                XCTAssert(linkedOwningUserId == nil)
                XCTAssert(error != nil)

                self.downloadDeletion(self.uploadFile2, expectation: expectations)
            }
        }
        
        self.waitForExpectations()
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
        let downloadInvitation = 2
        let invitationCode = self.downloadingInvitations[downloadInvitation].stringValue
        
        let expectations = UploadFileExpectations(fromTestClass: self)
        
        self.extraServerResponseTime = 30
        
        let testFile = TestBasics.session.createTestFile("FileUploadByDownloadingSharingUser")
        
        self.waitUntilSyncServerUserSignin() {
            SMSyncServerUser.session.redeemSharingInvitation(invitationCode: invitationCode) { (linkedOwningUserId, error) in
                XCTAssert(linkedOwningUserId == nil)
                XCTAssert(error != nil)

                self.uploadFile(testFile, expectations: expectations, failureExpected: true)
            }
        }
        
        self.waitForExpectations()
    }
    
    func testThatUploadDeletionByDownloadingSharingUserFails() {
        // Redeem Download invitation first.
        let downloadInvitation = 3
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
        let downloadInvitation = 4

    }
    
    func testThatInvitationByUploadSharingUserFails() {
        // Redeem Upload invitation first.
    }
    
    func testThatInvitationByAdminSharingUserWorks() {
        // Redeem Admin invitation first.
    }
}
