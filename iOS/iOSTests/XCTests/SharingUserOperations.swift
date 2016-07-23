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
    var uploadFile3:TestFile!
    let uploadFile1UUID = SMPersistItemString(name: "SharingUserOperations.uploadFile1", initialStringValue: "", persistType: .UserDefaults)
    let uploadFile2UUID = SMPersistItemString(name: "SharingUserOperations.uploadFile2", initialStringValue: "", persistType: .UserDefaults)
    let uploadFile3UUID = SMPersistItemString(name: "SharingUserOperations.uploadFile3", initialStringValue: "", persistType: .UserDefaults)
    
    func createUploadFiles(initial initial:Bool) {
        if initial {
            self.uploadFile1 = TestBasics.session.createTestFile("FileDownloadByDownloadSharingUser")
            self.uploadFile1UUID.stringValue = self.uploadFile1.uuidString
            
            self.uploadFile2 = TestBasics.session.createTestFile("DownloadDeletionByDownloadSharingUser")
            self.uploadFile2UUID.stringValue = self.uploadFile2.uuidString
            
            self.uploadFile3 = TestBasics.session.createTestFile("UploadDeletionByDownloadSharingUser")
            self.uploadFile3UUID.stringValue = self.uploadFile3.uuidString
        }
        else {
            self.uploadFile1 = TestBasics.session.recreateTestFile(fromUUID: self.uploadFile1UUID.stringValue)
            self.uploadFile2 = TestBasics.session.recreateTestFile(fromUUID: self.uploadFile2UUID.stringValue)
            self.uploadFile3 = TestBasics.session.recreateTestFile(fromUUID: self.uploadFile3UUID.stringValue)
        }
    }

    // Do this before any of the following tests.
    // Must be signed in as Owning User.
    func testSetupRemainingTests() {
        let setupDone = self.expectationWithDescription("Done Setup")
        self.extraServerResponseTime = Double(self.numberInvitationsPerType) * 3 * 20
        let uploadExpectations1 = UploadFileExpectations(fromTestClass: self)
        let uploadExpectations2 = UploadFileExpectations(fromTestClass: self)
        let uploadExpectations3 = UploadFileExpectations(fromTestClass: self)

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
                                        self.uploadFile(self.uploadFile3, expectations: uploadExpectations3) {
                                            setupDone.fulfill()
                                        }
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
            self.uploadCompleteCallbackExpectation = testClass.expectationWithDescription("Upload Complete")
            self.singleUploadExpectation = testClass.expectationWithDescription("Single Upload Complete")
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
        
        if !failureExpected {
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile.uuidString)
                expectations.singleUploadExpectation.fulfill()
            }
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
                    Log.msg("SMSyncServer.session.resetFromError: Completed")
                    XCTAssert(error == nil)
                    
                    // These aren't really true, but we need to fulfil them to clean up.
                    expectations.uploadCompleteCallbackExpectation.fulfill()
                    expectations.singleUploadExpectation.fulfill()
                    
                    complete?()
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
        
        SMSyncServer.session.resetMetaData(forUUID: testFile.uuid)

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
    
    func uploadDeletion(testFile:TestFile, expectation:UploadDeletionExpectations, failureExpected:Bool=false, complete:(()->())?=nil) {

        try! SMSyncServer.session.deleteFile(testFile.uuid)
        
        if failureExpected {
            expectation.deletionExpectation.fulfill()
        }
        else {
            self.deletionCallbacks.append() { uuids in
                XCTAssert(uuids.count == 1)
                XCTAssert(uuids[0].UUIDString == testFile.uuidString)
                expectation.deletionExpectation.fulfill()
            }
        }
        
        // The .Idle callback gets called first
        self.idleCallbacks.append() {
            expectation.idleExpectation.fulfill()
        }
        
        if failureExpected {
            self.errorCallbacks.append() {
                SMSyncServer.session.cleanupFile(testFile.uuid)
                CoreData.sessionNamed(CoreDataTests.name).removeObject(
                    testFile.appFile)
                CoreData.sessionNamed(CoreDataTests.name).saveContext()
                
                SMSyncServer.session.resetFromError() { error in
                    Log.msg("SMSyncServer.session.resetFromError: Completed")
                    XCTAssert(error == nil)
                    
                    // This isn't really true, but we need to fulfil them to clean up.
                    expectation.commitCompleteExpectation.fulfill()
                    
                    complete?()
                }
            }
        }
        else {
            self.commitCompleteCallbacks.append() { numberDeletions in
                Log.msg("commitCompleteCallbacks: deleteFiles")
                XCTAssert(numberDeletions == 1)
                
                let fileAttr = SMSyncServer.session.localFileStatus(testFile.uuid)
                XCTAssert(fileAttr != nil)
                XCTAssert(fileAttr!.deleted!)
                
                expectation.commitCompleteExpectation.fulfill()
                complete?()
            }
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
    // 4) Then do the following:
    
    func startTestWithInvitationCode(invitationCode: String, testBody:()->()) {
        self.waitUntilSyncServerUserSignin() {
            self.idleCallbacks.append() {
                testBody()
            }
            
            SMSyncServerUser.session.redeemSharingInvitation(invitationCode: invitationCode) { (linkedOwningUserId, error) in
                XCTAssert(linkedOwningUserId != nil)
                XCTAssert(error == nil)
            }
        }
        
        self.waitForExpectations()
    }
    
    func testThatFileDownloadByDownloadSharingUserWorks() {
        // Redeem Download invitation first.
        let downloadInvitation = 0
        let invitationCode = self.downloadingInvitations[downloadInvitation].stringValue
        
        let expectations = DownloadFileExpectations(fromTestClass: self)
        
        self.extraServerResponseTime = 30
        
        self.createUploadFiles(initial:false)
        
        self.startTestWithInvitationCode(invitationCode) {
            self.downloadFile(self.uploadFile1, expectations: expectations)
        }
    }
    
    func testThatDownloadDeletionByDownloadSharingUserWorks() {
        // Redeem Download invitation first.
        let downloadInvitation = 1
        let invitationCode = self.downloadingInvitations[downloadInvitation].stringValue
        
        let expectations = DownloadDeletionExpectations(fromTestClass: self)
        
        self.extraServerResponseTime = 30
        
        self.createUploadFiles(initial:false)
        
        self.startTestWithInvitationCode(invitationCode) {
            self.downloadDeletion(self.uploadFile2, expectation: expectations)
        }
    }
    
    func testThatDownloadDeletionByUploadSharingUserWorks() {
        let uploadInvitation = 0
        let invitationCode = self.uploadingInvitations[uploadInvitation].stringValue
        let uploadExpectations = UploadFileExpectations(fromTestClass: self)
        let uploadDeletionExpectations = UploadDeletionExpectations(fromTestClass: self)
        let downloadDeletionExpectations = DownloadDeletionExpectations(fromTestClass: self)
        
        self.startTestWithInvitationCode(invitationCode) {
            let testFile = TestBasics.session.createTestFile(
                "DownloadDeletionByUploadSharingUser")
            
            self.uploadFile(testFile, expectations: uploadExpectations) {
                self.uploadDeletion(testFile, expectation: uploadDeletionExpectations) {
                    self.downloadDeletion(testFile, expectation: downloadDeletionExpectations)
                }
            }
        }
    }
    
    func testThatFileDownloadByUploadSharingUserWorks() {
        let uploadInvitation = 1
        
        // Redeem Upload invitation first.
        
        let invitationCode = self.uploadingInvitations[uploadInvitation].stringValue
        
        let uploadExpectations = UploadFileExpectations(fromTestClass: self)
        let downloadExpectations = DownloadFileExpectations(fromTestClass: self)
        
        self.startTestWithInvitationCode(invitationCode) {
            let testFile = TestBasics.session.createTestFile(
                "FileDownloadByUploadSharingUser")
            
            self.uploadFile(testFile, expectations: uploadExpectations) {
                self.downloadFile(testFile, expectations: downloadExpectations)
            }
        }
    }
    
    func testThatDownloadDeletionByAdminSharingUserWorks() {
        let adminInvitation = 0
        
        // Redeem Admin invitation first.
        
        let invitationCode = self.adminInvitations[adminInvitation].stringValue
        
        let uploadExpectations = UploadFileExpectations(fromTestClass: self)
        let uploadDeletionExpectations = UploadDeletionExpectations(fromTestClass: self)
        let downloadDeletionExpectations = DownloadDeletionExpectations(fromTestClass: self)
        
        self.startTestWithInvitationCode(invitationCode) {
            let testFile = TestBasics.session.createTestFile(
                "DownloadDeletionByAdminSharingUser")
            
            self.uploadFile(testFile, expectations: uploadExpectations) {
                self.uploadDeletion(testFile, expectation: uploadDeletionExpectations) {
                    self.downloadDeletion(testFile, expectation: downloadDeletionExpectations)
                }
            }
        }
    }
    
    func testThatFileDownloadByAdminSharingUserWorks() {
        let adminInvitation = 1
        // Redeem Admin invitation first.
        
        let invitationCode = self.adminInvitations[adminInvitation].stringValue
        
        let uploadExpectations = UploadFileExpectations(fromTestClass: self)
        let downloadExpectations = DownloadFileExpectations(fromTestClass: self)
        
        self.startTestWithInvitationCode(invitationCode) {
            let testFile = TestBasics.session.createTestFile(
                "FileDownloadByAdminSharingUser")
            
            self.uploadFile(testFile, expectations: uploadExpectations) {
                self.downloadFile(testFile, expectations: downloadExpectations)
            }
        }
    }
    
    //MARK: Upload tests
    
    func testThatFileUploadByDownloadingSharingUserFails() {
        // Redeem Download invitation first.
        let downloadInvitation = 2
        let invitationCode = self.downloadingInvitations[downloadInvitation].stringValue
        
        let expectations = UploadFileExpectations(fromTestClass: self)
        
        self.extraServerResponseTime = 60
        
        let testFile = TestBasics.session.createTestFile("FileUploadByDownloadingSharingUser")
    
        self.startTestWithInvitationCode(invitationCode) {
            self.uploadFile(testFile, expectations: expectations, failureExpected: true)
        }
    }
    
    func testThatUploadDeletionByDownloadingSharingUserFails() {
        // Redeem Download invitation first.
        let downloadInvitation = 3
        
        let invitationCode = self.downloadingInvitations[downloadInvitation].stringValue
        let uploadDeletionExpectations = UploadDeletionExpectations(fromTestClass: self)
        
        self.startTestWithInvitationCode(invitationCode) {
            self.uploadDeletion(self.uploadFile3, expectation: uploadDeletionExpectations, failureExpected: true)
        }
    }
    
    func testThatFileUploadByUploadSharingUserWorks() {
        let uploadInvitation = 2
        // Redeem Upload invitation first.
        
        let invitationCode = self.uploadingInvitations[uploadInvitation].stringValue

        let uploadExpectations = UploadFileExpectations(fromTestClass: self)
        
        self.startTestWithInvitationCode(invitationCode) {
            let testFile = TestBasics.session.createTestFile(
                "FileUploadByUploadSharingUser")
            self.uploadFile(testFile, expectations: uploadExpectations)
        }
    }
    
    func testThatUploadDeletionByUploadSharingUserWorks() {
        let uploadInvitation = 3
        // Redeem Upload invitation first.
        let invitationCode = self.uploadingInvitations[uploadInvitation].stringValue

        let uploadExpectations = UploadFileExpectations(fromTestClass: self)
        let uploadDeletionExpectations = UploadDeletionExpectations(fromTestClass: self)
        
        self.startTestWithInvitationCode(invitationCode) {
            let testFile = TestBasics.session.createTestFile(
                "UploadDeletionByUploadSharingUser")
            
            self.uploadFile(testFile, expectations: uploadExpectations) {
                self.uploadDeletion(testFile, expectation: uploadDeletionExpectations)
            }
        }
    }
    
    func testThatFileUploadByAdminSharingUserWorks() {
        let adminInvitation = 2
        // Redeem Admin invitation first.
        
        let invitationCode = self.adminInvitations[adminInvitation].stringValue

        let uploadExpectations = UploadFileExpectations(fromTestClass: self)
        
        self.startTestWithInvitationCode(invitationCode) {
            let testFile = TestBasics.session.createTestFile(
                "FileUploadByAdminSharingUser")
            self.uploadFile(testFile, expectations: uploadExpectations)
        }
    }
    
    func testThatUploadDeletionByAdminSharingUserWorks() {
        let adminInvitation = 3
        // Redeem Admin invitation first.
        let invitationCode = self.adminInvitations[adminInvitation].stringValue

        let uploadExpectations = UploadFileExpectations(fromTestClass: self)
        let uploadDeletionExpectations = UploadDeletionExpectations(fromTestClass: self)
        
        self.startTestWithInvitationCode(invitationCode) {
            let testFile = TestBasics.session.createTestFile(
                "UploadDeletionByAdminSharingUser")
            self.uploadFile(testFile, expectations: uploadExpectations) {
                self.uploadDeletion(testFile, expectation: uploadDeletionExpectations)
            }
        }
    }

    //MARK: Invitation tests
    
    func doInvitation(invitationCode:String, failureExpected:Bool) {
        self.startTestWithInvitationCode(invitationCode) {
            SMServerAPI.session.createSharingInvitation(sharingType: SMSharingType.Admin.rawValue, completion: { (invitationCode, apiResult) in
                if failureExpected {
                    XCTAssert(apiResult.error != nil)
                    XCTAssert(invitationCode == nil)
                }
                else {
                    XCTAssert(apiResult.error == nil)
                    XCTAssert(invitationCode != nil)
                }
            })
        }
    }
    
    func testThatInvitationByDownloadingSharingUserFails() {
        // Redeem Download invitation first.
        let downloadInvitation = 4
        let invitationCode = self.downloadingInvitations[downloadInvitation].stringValue
        self.doInvitation(invitationCode, failureExpected: true)
    }
    
    func testThatInvitationByUploadSharingUserFails() {
        let uploadInvitation = 4
        
        // Redeem Upload invitation first.
        let invitationCode = self.uploadingInvitations[uploadInvitation].stringValue
        self.doInvitation(invitationCode, failureExpected: true)
    }
    
    func testThatInvitationByAdminSharingUserWorks() {
        let adminInvitation = 4
        
        // Redeem Admin invitation first.
        
        let invitationCode = self.adminInvitations[adminInvitation].stringValue
        self.doInvitation(invitationCode, failureExpected: false)
    }
}
