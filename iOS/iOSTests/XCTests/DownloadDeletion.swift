//
//  DownloadDeletion.swift
//  Tests
//
//  Created by Christopher Prince on 3/3/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import XCTest
// The @testable notation lets us access "internal" classes within our project.
@testable import Tests
@testable import SMSyncServer
import SMCoreLib

class DownloadDeletion: BaseClass {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    // Download deletion of a single file: A file that exists, and hasn't been deleted locally.
    func testThatDownloadDeletionOfASingleFileThatExistsWorks() {
        let singleUploadExpectation = self.expectationWithDescription("Single Upload Complete")
        let commitCompleteUpload = self.expectationWithDescription("Commit Complete Upload")
        let idleExpectationUpload = self.expectationWithDescription("Idle Upload")

        let deletionExpectation = self.expectationWithDescription("Single Deletion Complete")
        let commitCompleteDelete = self.expectationWithDescription("Commit Complete Download")
        let idleExpectationDeletion = self.expectationWithDescription("Idle Deletion")

        let clientShouldDeleteFilesExpectation = self.expectationWithDescription("Should Delete Files")
        let idleAfterShouldDeleteFiles = self.expectationWithDescription("Idle After Should Delete")

        self.extraServerResponseTime = 60
        
        self.waitUntilSyncServerUserSignin() {
            let testFile = TestBasics.session.createTestFile("DownloadDeletionOfASingleFileThatExists")
            
            self.uploadFiles([testFile], uploadExpectations: [singleUploadExpectation], commitComplete: commitCompleteUpload, idleExpectation: idleExpectationUpload) {
                // Upload done: Now idle
                
                self.deleteFiles([testFile], deletionExpectation: deletionExpectation, commitCompleteExpectation: commitCompleteDelete, idleExpectation: idleExpectationDeletion) {
                    // Deletion done: Now idle.
                    
                    // Our situation now is that the file has been deleted on the server, and we've marked the file as deleted locally.
                    // HOWEVER, since what we're trying to test is download-deletion, we now need to fake the local meta data state and mark the file as *not* deleted locally, then do another server sync-- which should result in a download-deletion.
                    
                    SMSyncServer.session.resetMetaData(forUUID: testFile.uuid, resetType: .Undelete)
                    
                    self.shouldDoDeletions.append() { deletions, acknowledgement in
                        XCTAssert(deletions.count == 1)
                        let attr = deletions[0]
                        XCTAssert(attr.uuid.UUIDString == testFile.uuidString)
                        
                        let fileAttr = SMSyncServer.session.localFileStatus(testFile.uuid)
                        XCTAssert(fileAttr != nil)
                        XCTAssert(fileAttr!.deleted!)
                        
                        clientShouldDeleteFilesExpectation.fulfill()
                        acknowledgement()
                    }
                    
                    self.idleCallbacks.append() {
                        idleAfterShouldDeleteFiles.fulfill()
                    }
                    
                    SMSyncControl.session.nextSyncOperation()
                }
            }
        }
        
        self.waitForExpectations()
    }

    // Download deletion of a single file: A file that exists, and has already been deleted locally (but that is pending upload-deletion).
    func testThatDownloadDeletionOfASingleFileThatExistsButHasBeenDeletedLocallyWorks() {
        let singleUploadExpectation = self.expectationWithDescription("Single Upload Complete")
        let commitCompleteUpload = self.expectationWithDescription("Commit Complete Upload")
        let idleExpectationUpload = self.expectationWithDescription("Idle Upload")

        let deletionExpectation = self.expectationWithDescription("Single Deletion Complete")
        let commitCompleteDelete = self.expectationWithDescription("Commit Complete Download")
        let idleExpectationDeletion = self.expectationWithDescription("Idle Deletion")

        let idleExpectationDeletion2 = self.expectationWithDescription("Idle Deletion2")

        self.extraServerResponseTime = 60
        
        self.waitUntilSyncServerUserSignin() {
            let testFile = TestBasics.session.createTestFile(
                "DownloadDeletionOfASingleFileThatExistsButHasBeenDeletedLocally")
            
            self.uploadFiles([testFile], uploadExpectations: [singleUploadExpectation], commitComplete: commitCompleteUpload, idleExpectation: idleExpectationUpload) {
                // Upload done: Now idle
                
                self.deleteFiles([testFile], deletionExpectation: deletionExpectation, commitCompleteExpectation: commitCompleteDelete, idleExpectation: idleExpectationDeletion) {
                    // Deletion done: Now idle.
                    
                    SMSyncServer.session.resetMetaData(forUUID: testFile.uuid, resetType: .Undelete)
                    
                    /*
                    self.shouldDoDeletions.append() { deletions, acknowledgement in
                        XCTAssert(deletions.count == 1)
                        let uuid = deletions[0]
                        XCTAssert(uuid.UUIDString == testFile.uuidString)
                        
                        let fileAttr = SMSyncServer.session.localFileStatus(testFile.uuid)
                        XCTAssert(fileAttr != nil)
                        XCTAssert(fileAttr!.deleted!)
                        
                        clientShouldDeleteFilesExpectation.fulfill()
                        acknowledgement()
                    }*/
                    
                    // What should happen here? Right now, an upload deletion will be triggered-- but this will occur *after* the download deletion, since downloads get priority. What will happen on the following upload deletion? The shouldDoDeletions doesn't get triggered because the download deletion notices that there is a pending upload deletion, and removes the pending upload deletion-- because it's not needed anymore.
                    // Note that the commit that triggers the expected download deletion is in this call to self.deleteFile.
                    // Don't expect a commit here-- because the upload deletion will be removed.
                    self.deleteFiles([testFile], deletionExpectation: nil, commitCompleteExpectation: nil, idleExpectation: idleExpectationDeletion2)
                }
            }
        }
        
        self.waitForExpectations()
    }
    
    // Download deletion of a single file: A file that doesn't exist locally (e.g., that was uploaded and download-deleted before the local device synced with the server).
     func testThatDownloadDeletionOfASingleFileThatDoesNotExistLocallyWorks() {
        let singleUploadExpectation = self.expectationWithDescription("Single Upload Complete")
        let commitCompleteUpload = self.expectationWithDescription("Commit Complete Upload")
        let idleExpectationUpload = self.expectationWithDescription("Idle Upload")

        let deletionExpectation = self.expectationWithDescription("Single Deletion Complete")
        let commitCompleteDelete = self.expectationWithDescription("Commit Complete Download")
        let idleExpectationDeletion = self.expectationWithDescription("Idle Deletion")

        let idleExpectation = self.expectationWithDescription("Idle")

        self.extraServerResponseTime = 60
        
        self.waitUntilSyncServerUserSignin() {
            let testFile = TestBasics.session.createTestFile(
                "DownloadDeletionOfASingleFileThatDoesNotExistLocally")
            
            self.uploadFiles([testFile], uploadExpectations: [singleUploadExpectation], commitComplete: commitCompleteUpload, idleExpectation: idleExpectationUpload) {
                // Upload done: Now idle
                
                self.deleteFiles([testFile], deletionExpectation: deletionExpectation, commitCompleteExpectation: commitCompleteDelete, idleExpectation: idleExpectationDeletion) {
                    // Deletion done: Now idle.
                    
                    SMSyncServer.session.resetMetaData(forUUID: testFile.uuid)
                    
                    // Since we've deleted the meta data locally for the file, we should get no callback for deletion.
                    
                    self.idleCallbacks.append() {
                        idleExpectation.fulfill()
                    }
                    
                    SMSyncControl.session.nextSyncOperation()
                }
            }
        }
        
        self.waitForExpectations()
    }
    
    // Download deletion of two files
    func testThatDownloadDeletionOfTwoFilesWorks() {
        let singleUploadExpectation1 = self.expectationWithDescription("Single Upload Complete1")
        let singleUploadExpectation2 = self.expectationWithDescription("Single Upload Complete2")
        let commitCompleteUpload = self.expectationWithDescription("Commit Complete Upload")
        let idleExpectationUpload = self.expectationWithDescription("Idle Upload")

        let deletionExpectation = self.expectationWithDescription("Single Deletion Complete1")
        let commitCompleteDelete = self.expectationWithDescription("Commit Complete Download")
        let idleExpectationDeletion = self.expectationWithDescription("Idle Deletion")

        let clientShouldDeleteFilesExpectation = self.expectationWithDescription("Should Delete Files")
        let idleAfterShouldDeleteFiles = self.expectationWithDescription("Idle After Should Delete")

        self.extraServerResponseTime = 60
        
        self.waitUntilSyncServerUserSignin() {
            let testFile1 = TestBasics.session.createTestFile("DownloadDeletionOfTwoFiles1")
            let testFile2 = TestBasics.session.createTestFile("DownloadDeletionOfTwoFiles2")
            
            self.uploadFiles([testFile1, testFile2], uploadExpectations: [singleUploadExpectation1, singleUploadExpectation2], commitComplete: commitCompleteUpload, idleExpectation: idleExpectationUpload) {
                // Upload done: Now idle
                
                self.deleteFiles([testFile1, testFile2], deletionExpectation: deletionExpectation, commitCompleteExpectation: commitCompleteDelete, idleExpectation: idleExpectationDeletion) {
                    // Deletion done: Now idle.
                    
                    // Our situation now is that the file has been deleted on the server, and we've marked the file as deleted locally.
                    // HOWEVER, since what we're trying to test is download-deletion, we now need to fake the local meta data state and mark the file as *not* deleted locally, then do another server sync-- which should result in a download-deletion.
                    
                    SMSyncServer.session.resetMetaData(forUUID: testFile1.uuid, resetType: .Undelete)
                    SMSyncServer.session.resetMetaData(forUUID: testFile2.uuid, resetType: .Undelete)
                    
                    self.shouldDoDeletions.append() { deletions, acknowledgement in
                        XCTAssert(deletions.count == 2)
                        // The ordering here isn't well defined, but assume its the same as uploaded/deleted.
                        let attr0 = deletions[0]
                        let attr1 = deletions[1]

                        XCTAssert(attr0.uuid.UUIDString == testFile1.uuidString)
                        XCTAssert(attr1.uuid.UUIDString == testFile2.uuidString)
                        
                        let fileAttr1 = SMSyncServer.session.localFileStatus(testFile1.uuid)
                        XCTAssert(fileAttr1 != nil)
                        XCTAssert(fileAttr1!.deleted!)

                        let fileAttr2 = SMSyncServer.session.localFileStatus(testFile2.uuid)
                        XCTAssert(fileAttr2 != nil)
                        XCTAssert(fileAttr2!.deleted!)
                        
                        clientShouldDeleteFilesExpectation.fulfill()
                        acknowledgement()
                    }
                    
                    self.idleCallbacks.append() {
                        idleAfterShouldDeleteFiles.fulfill()
                    }
                    
                    SMSyncControl.session.nextSyncOperation()
                }
            }
        }
        
        self.waitForExpectations()
    }
    
    // Download deletion of one file with download of one file.
    func testThatDownloadDeletionOfOneFileWithDownloadOfOneFileWorks() {
        let singleUploadExpectation1 = self.expectationWithDescription("Single Upload Complete1")
        let singleUploadExpectation2 = self.expectationWithDescription("Single Upload Complete2")
        let commitCompleteUpload = self.expectationWithDescription("Commit Complete Upload")
        let idleExpectationUpload = self.expectationWithDescription("Idle Upload")

        let deletionExpectation = self.expectationWithDescription("Single Deletion Complete1")
        let commitCompleteDelete = self.expectationWithDescription("Commit Complete Download")
        let idleExpectationDeletion = self.expectationWithDescription("Idle Deletion")

        let clientShouldDeleteFilesExpectation = self.expectationWithDescription("Should Delete Files")
        let singleDownloadExpectation = self.expectationWithDescription("Single Download")
        let downloadsCompleteExpectation = self.expectationWithDescription("Downloads Complete")
        let idleAfterShouldDeleteFiles = self.expectationWithDescription("Idle After Should Delete")

        self.extraServerResponseTime = 60
        
        self.waitUntilSyncServerUserSignin() {
            let testFile1 = TestBasics.session.createTestFile(
                "DownloadDeletionOfOneFileWithDownloadOfOneFile1")
            let testFile2 = TestBasics.session.createTestFile(
                "DownloadDeletionOfOneFileWithDownloadOfOneFile2")
            
            self.uploadFiles([testFile1, testFile2], uploadExpectations: [singleUploadExpectation1, singleUploadExpectation2], commitComplete: commitCompleteUpload, idleExpectation: idleExpectationUpload) {
                // Upload done: Now idle
                
                self.deleteFiles([testFile1], deletionExpectation: deletionExpectation, commitCompleteExpectation: commitCompleteDelete, idleExpectation: idleExpectationDeletion) {
                    // Deletion done: Now idle.
                    
                    SMSyncServer.session.resetMetaData(forUUID: testFile1.uuid, resetType: .Undelete)
                    SMSyncServer.session.resetMetaData(forUUID: testFile2.uuid)
                    
                    self.shouldDoDeletions.append() { deletions, acknowledgement in
                        XCTAssert(deletions.count == 1)
                        let attr = deletions[0]

                        XCTAssert(attr.uuid.UUIDString == testFile1.uuidString)
                        
                        let fileAttr1 = SMSyncServer.session.localFileStatus(testFile1.uuid)
                        XCTAssert(fileAttr1 != nil)
                        XCTAssert(fileAttr1!.deleted!)
                        
                        clientShouldDeleteFilesExpectation.fulfill()
                        acknowledgement()
                    }
                    
                    self.singleDownload.append() { (downloadedFile:NSURL, downloadedFileAttr: SMSyncAttributes) in
                        XCTAssert(downloadedFileAttr.uuid.UUIDString == testFile2.uuidString)
                        let filesAreTheSame = SMFiles.compareFiles(file1: testFile2.url, file2: downloadedFile)
                        XCTAssert(filesAreTheSame)
                        singleDownloadExpectation.fulfill()
                    }
                    
                    self.shouldSaveDownloads.append() { downloads, ack in
                        XCTAssert(downloads.count == 1)
                        
                        let (_, attr) = downloads[0]
                        XCTAssert(attr.uuid!.UUIDString == testFile2.uuidString)
                        XCTAssert(!attr.deleted!)
                        downloadsCompleteExpectation.fulfill()
                        ack()
                    }
                    
                    self.idleCallbacks.append() {
                        idleAfterShouldDeleteFiles.fulfill()
                    }
                    
                    SMSyncControl.session.nextSyncOperation()
                }
            }
        }
        
        self.waitForExpectations()
    }
    
    // Download deletion, followed by local deletion of the same file fails.
    func testThatDownloadDeletionFollowedByLocalDeletionFails() {
        let singleUploadExpectation = self.expectationWithDescription("Single Upload Complete")
        let commitCompleteUpload = self.expectationWithDescription("Commit Complete Upload")
        let idleExpectationUpload = self.expectationWithDescription("Idle Upload")

        let deletionExpectation = self.expectationWithDescription("Single Deletion Complete")
        let commitCompleteDelete = self.expectationWithDescription("Commit Complete Download")
        let idleExpectationDeletion = self.expectationWithDescription("Idle Deletion")

        let clientShouldDeleteFilesExpectation = self.expectationWithDescription("Should Delete Files")
        let idleAfterShouldDeleteFiles = self.expectationWithDescription("Idle After Should Delete")
        let deletionFailure = self.expectationWithDescription("Deletion Failure")
        
        self.extraServerResponseTime = 60
        
        self.waitUntilSyncServerUserSignin() {
            let testFile = TestBasics.session.createTestFile("DownloadDeletionOfASingleFileThatExists")
            
            self.uploadFiles([testFile], uploadExpectations: [singleUploadExpectation], commitComplete: commitCompleteUpload, idleExpectation: idleExpectationUpload) {
                // Upload done: Now idle
                
                self.deleteFiles([testFile], deletionExpectation: deletionExpectation, commitCompleteExpectation: commitCompleteDelete, idleExpectation: idleExpectationDeletion) {
                    // Deletion done: Now idle.
                    
                    // Our situation now is that the file has been deleted on the server, and we've marked the file as deleted locally.
                    // HOWEVER, since what we're trying to test is download-deletion, we now need to fake the local meta data state and mark the file as *not* deleted locally, then do another server sync-- which should result in a download-deletion.
                    
                    SMSyncServer.session.resetMetaData(forUUID: testFile.uuid, resetType: .Undelete)
                    
                    self.shouldDoDeletions.append() { deletions, acknowledgement in
                        XCTAssert(deletions.count == 1)
                        let attr = deletions[0]

                        XCTAssert(attr.uuid.UUIDString == testFile.uuidString)
                        
                        let fileAttr = SMSyncServer.session.localFileStatus(testFile.uuid)
                        XCTAssert(fileAttr != nil)
                        XCTAssert(fileAttr!.deleted!)
                        
                        clientShouldDeleteFilesExpectation.fulfill()
                        acknowledgement()
                    }
                    
                    self.idleCallbacks.append() {
                        idleAfterShouldDeleteFiles.fulfill()
                        
                        do {
                            // This is going to fail.
                            try SMSyncServer.session.deleteFile(testFile.uuid)
                        } catch {
                            deletionFailure.fulfill()
                        }
                        
                        // SMSyncServer.session.commit()
                    }
                    
                    SMSyncControl.session.nextSyncOperation()
                }
            }
        }
        
        self.waitForExpectations()
    }
    
    // Download deletion, followed by upload of file with different UUID but with same remote storage name works.
    func testThatDownloadDeletionFollowedByUploadWithSameRemoteNameWorks() {
        let singleUploadExpectation = self.expectationWithDescription("Single Upload Complete")
        let commitCompleteUpload = self.expectationWithDescription("Commit Complete Upload")
        let idleExpectationUpload = self.expectationWithDescription("Idle Upload")

        let singleUploadExpectation2 = self.expectationWithDescription("Single Upload Complete2")
        let commitCompleteUpload2 = self.expectationWithDescription("Commit Complete Upload2")
        let idleExpectationUpload2 = self.expectationWithDescription("Idle Upload2")
        
        let deletionExpectation = self.expectationWithDescription("Single Deletion Complete")
        let commitCompleteDelete = self.expectationWithDescription("Commit Complete Download")
        let idleExpectationDeletion = self.expectationWithDescription("Idle Deletion")

        let clientShouldDeleteFilesExpectation = self.expectationWithDescription("Should Delete Files")
        let idleAfterShouldDeleteFiles = self.expectationWithDescription("Idle After Should Delete")

        self.extraServerResponseTime = 60
        
        self.waitUntilSyncServerUserSignin() {
            let remoteName = "DownloadDeletionFollowedByUploadWithSameRemoteName"
            let testFile1 = TestBasics.session.createTestFile(remoteName)
            
            self.uploadFiles([testFile1], uploadExpectations: [singleUploadExpectation], commitComplete: commitCompleteUpload, idleExpectation: idleExpectationUpload) {
                // Upload done: Now idle
                
                self.deleteFiles([testFile1], deletionExpectation: deletionExpectation, commitCompleteExpectation: commitCompleteDelete, idleExpectation: idleExpectationDeletion) {
                    // Deletion done: Now idle.
                    
                    // Our situation now is that the file has been deleted on the server, and we've marked the file as deleted locally.
                    // HOWEVER, since what we're trying to test is download-deletion, we now need to fake the local meta data state and mark the file as *not* deleted locally, then do another server sync-- which should result in a download-deletion.
                    
                    SMSyncServer.session.resetMetaData(forUUID: testFile1.uuid, resetType: .Undelete)
                    
                    self.shouldDoDeletions.append() { deletions, acknowledgement in
                        XCTAssert(deletions.count == 1)
                        let attr = deletions[0]

                        XCTAssert(attr.uuid.UUIDString == testFile1.uuidString)
                        
                        let fileAttr = SMSyncServer.session.localFileStatus(testFile1.uuid)
                        XCTAssert(fileAttr != nil)
                        XCTAssert(fileAttr!.deleted!)
                        
                        clientShouldDeleteFilesExpectation.fulfill()
                        acknowledgement()
                    }
                    
                    self.idleCallbacks.append() {
                        idleAfterShouldDeleteFiles.fulfill()
                        
                        let testFile2 = TestBasics.session.createTestFile(remoteName)
                        
                        self.uploadFiles([testFile2], uploadExpectations: [singleUploadExpectation2], commitComplete: commitCompleteUpload2, idleExpectation: idleExpectationUpload2) {
                        }
                    }
                    
                    SMSyncControl.session.nextSyncOperation()
                }
            }
        }
        
        self.waitForExpectations()
    }
}
