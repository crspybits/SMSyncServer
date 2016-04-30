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
    
    func uploadFiles(testFiles:[TestFile], uploadExpectations:[XCTestExpectation], commitComplete:XCTestExpectation, idleExpectation:XCTestExpectation,
        complete:(()->())?) {
        
        for testFileIndex in 0...testFiles.count-1 {
            let testFile = testFiles[testFileIndex]
            let uploadExpectation = uploadExpectations[testFileIndex]
        
            SMSyncServer.session.uploadImmutableFile(testFile.url, withFileAttributes: testFile.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile.uuidString)
                uploadExpectation.fulfill()
            }
        }

        // The .Idle callback gets called first
        self.idleCallbacks.append() {
            idleExpectation.fulfill()
        }
        
        // Followed by the commit complete callback.
        self.commitCompleteCallbacks.append() { numberUploads in
            XCTAssert(numberUploads == testFiles.count)
            commitComplete.fulfill()
            self.checkFileSizes(testFiles, complete: complete)
        }
        
        SMSyncServer.session.commit()
    }
    
    func checkFileSizes(testFiles:[TestFile], complete:(()->())?) {
        if testFiles.count == 0 {
            complete?()
        }
        else {
            let testFile = testFiles[0]
            
            TestBasics.session.checkFileSize(testFile.uuidString, size: testFile.sizeInBytes) {
                let fileAttr = SMSyncServer.session.localFileStatus(testFile.uuid)
                XCTAssert(fileAttr != nil)
                XCTAssert(!fileAttr!.deleted!)
                self.checkFileSizes(Array(testFiles[1..<testFiles.count]), complete: complete)
            }
        }
    }
    
    func deleteFiles(testFiles:[TestFile], deletionExpectation:XCTestExpectation?, commitComplete:XCTestExpectation, idleExpectation:XCTestExpectation,
        complete:(()->())?=nil) {
        
        for testFileIndex in 0...testFiles.count-1 {
            let testFile = testFiles[testFileIndex]
            SMSyncServer.session.deleteFile(testFile.uuid)
        }
        
        if deletionExpectation != nil {
            self.deletionCallbacks.append() { uuids in
                XCTAssert(uuids.count == testFiles.count)
                for testFileIndex in 0...testFiles.count-1 {
                    let testFile = testFiles[testFileIndex]
                    XCTAssert(uuids[testFileIndex].UUIDString == testFile.uuidString)
                }
                
                deletionExpectation!.fulfill()
            }
        }
        
        // The .Idle callback gets called first
        self.idleCallbacks.append() {
            idleExpectation.fulfill()
        }
        
        // Followed by the commit complete.
        self.commitCompleteCallbacks.append() { numberDeletions in
            if deletionExpectation != nil {
                XCTAssert(numberDeletions == testFiles.count)
            }
            
            for testFile in testFiles {
                let fileAttr = SMSyncServer.session.localFileStatus(testFile.uuid)
                XCTAssert(fileAttr != nil)
                XCTAssert(fileAttr!.deleted!)
            }
            
            commitComplete.fulfill()
            complete?()
        }
        
        SMSyncServer.session.commit()
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
                
                self.deleteFiles([testFile], deletionExpectation: deletionExpectation, commitComplete: commitCompleteDelete, idleExpectation: idleExpectationDeletion) {
                    // Deletion done: Now idle.
                    
                    // Our situation now is that the file has been deleted on the server, and we've marked the file as deleted locally.
                    // HOWEVER, since what we're trying to test is download-deletion, we now need to fake the local meta data state and mark the file as *not* deleted locally, then do another server sync-- which should result in a download-deletion.
                    
                    SMSyncServer.session.resetMetaData(forUUID: testFile.uuid, resetType: .Undelete)
                    
                    self.clientShouldDeleteFilesCallbacks.append() { uuids in
                        XCTAssert(uuids.count == 1)
                        XCTAssert(uuids[0].UUIDString == testFile.uuidString)
                        
                        let fileAttr = SMSyncServer.session.localFileStatus(testFile.uuid)
                        XCTAssert(fileAttr != nil)
                        XCTAssert(fileAttr!.deleted!)
                        
                        clientShouldDeleteFilesExpectation.fulfill()
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

        let clientShouldDeleteFilesExpectation = self.expectationWithDescription("Should Delete Files")

        let commitCompleteDelete2 = self.expectationWithDescription("Commit Complete Download2")
        let idleExpectationDeletion2 = self.expectationWithDescription("Idle Deletion2")

        self.extraServerResponseTime = 60
        
        self.waitUntilSyncServerUserSignin() {
            let testFile = TestBasics.session.createTestFile(
                "DownloadDeletionOfASingleFileThatExistsButHasBeenDeletedLocally")
            
            self.uploadFiles([testFile], uploadExpectations: [singleUploadExpectation], commitComplete: commitCompleteUpload, idleExpectation: idleExpectationUpload) {
                // Upload done: Now idle
                
                self.deleteFiles([testFile], deletionExpectation: deletionExpectation, commitComplete: commitCompleteDelete, idleExpectation: idleExpectationDeletion) {
                    // Deletion done: Now idle.
                    
                    SMSyncServer.session.resetMetaData(forUUID: testFile.uuid, resetType: .Undelete)
                    
                    self.clientShouldDeleteFilesCallbacks.append() { uuids in
                        XCTAssert(uuids.count == 1)
                        XCTAssert(uuids[0].UUIDString == testFile.uuidString)
                        
                        let fileAttr = SMSyncServer.session.localFileStatus(testFile.uuid)
                        XCTAssert(fileAttr != nil)
                        XCTAssert(fileAttr!.deleted!)
                        
                        clientShouldDeleteFilesExpectation.fulfill()
                    }
                    
                    // What should happen here? Right now, an upload deletion will be triggered-- but this will occur *after* the download deletion, since downloads get priority. What will happen on the following upload deletion? It should be treated like a recovery case: It shouldn't do anything, and shouldn't return an error.
                    // Note that the commit that triggers the expected download deletion is in this call to self.deleteFile.
                    self.deleteFiles([testFile], deletionExpectation: nil, commitComplete: commitCompleteDelete2, idleExpectation: idleExpectationDeletion2)
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
                
                self.deleteFiles([testFile], deletionExpectation: deletionExpectation, commitComplete: commitCompleteDelete, idleExpectation: idleExpectationDeletion) {
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
                
                self.deleteFiles([testFile1, testFile2], deletionExpectation: deletionExpectation, commitComplete: commitCompleteDelete, idleExpectation: idleExpectationDeletion) {
                    // Deletion done: Now idle.
                    
                    // Our situation now is that the file has been deleted on the server, and we've marked the file as deleted locally.
                    // HOWEVER, since what we're trying to test is download-deletion, we now need to fake the local meta data state and mark the file as *not* deleted locally, then do another server sync-- which should result in a download-deletion.
                    
                    SMSyncServer.session.resetMetaData(forUUID: testFile1.uuid, resetType: .Undelete)
                    SMSyncServer.session.resetMetaData(forUUID: testFile2.uuid, resetType: .Undelete)
                    
                    self.clientShouldDeleteFilesCallbacks.append() { uuids in
                        XCTAssert(uuids.count == 2)
                        // The ordering here isn't well defined, but assume its the same as uploaded/deleted.
                        XCTAssert(uuids[0].UUIDString == testFile1.uuidString)
                        XCTAssert(uuids[1].UUIDString == testFile2.uuidString)
                        
                        let fileAttr1 = SMSyncServer.session.localFileStatus(testFile1.uuid)
                        XCTAssert(fileAttr1 != nil)
                        XCTAssert(fileAttr1!.deleted!)

                        let fileAttr2 = SMSyncServer.session.localFileStatus(testFile2.uuid)
                        XCTAssert(fileAttr2 != nil)
                        XCTAssert(fileAttr2!.deleted!)
                        
                        clientShouldDeleteFilesExpectation.fulfill()
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
                
                self.deleteFiles([testFile1], deletionExpectation: deletionExpectation, commitComplete: commitCompleteDelete, idleExpectation: idleExpectationDeletion) {
                    // Deletion done: Now idle.
                    
                    SMSyncServer.session.resetMetaData(forUUID: testFile1.uuid, resetType: .Undelete)
                    SMSyncServer.session.resetMetaData(forUUID: testFile2.uuid)
                    
                    self.clientShouldDeleteFilesCallbacks.append() { uuids in
                        XCTAssert(uuids.count == 1)
                        XCTAssert(uuids[0].UUIDString == testFile1.uuidString)
                        
                        let fileAttr1 = SMSyncServer.session.localFileStatus(testFile1.uuid)
                        XCTAssert(fileAttr1 != nil)
                        XCTAssert(fileAttr1!.deleted!)
                        
                        clientShouldDeleteFilesExpectation.fulfill()
                    }
                    
                    self.singleDownload.append() { (downloadedFile:NSURL, downloadedFileAttr: SMSyncAttributes) in
                        XCTAssert(downloadedFileAttr.uuid.UUIDString == testFile2.uuidString)
                        let filesAreTheSame = SMFiles.compareFiles(file1: testFile2.url, file2: downloadedFile)
                        XCTAssert(filesAreTheSame)
                        singleDownloadExpectation.fulfill()
                    }
                    
                    self.downloadsCompleteCallbacks.append() { downloadedFiles in
                        XCTAssert(downloadedFiles.count == 1)
                        
                        let (_, attr) = downloadedFiles[0]
                        XCTAssert(attr.uuid!.UUIDString == testFile2.uuidString)
                        XCTAssert(!attr.deleted!)

                        downloadsCompleteExpectation.fulfill()
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
        let idleAfterErrorReset = self.expectationWithDescription("Idle After Error Reset")
        
        self.extraServerResponseTime = 60
        
        self.waitUntilSyncServerUserSignin() {
            let testFile = TestBasics.session.createTestFile("DownloadDeletionOfASingleFileThatExists")
            
            self.uploadFiles([testFile], uploadExpectations: [singleUploadExpectation], commitComplete: commitCompleteUpload, idleExpectation: idleExpectationUpload) {
                // Upload done: Now idle
                
                self.deleteFiles([testFile], deletionExpectation: deletionExpectation, commitComplete: commitCompleteDelete, idleExpectation: idleExpectationDeletion) {
                    // Deletion done: Now idle.
                    
                    // Our situation now is that the file has been deleted on the server, and we've marked the file as deleted locally.
                    // HOWEVER, since what we're trying to test is download-deletion, we now need to fake the local meta data state and mark the file as *not* deleted locally, then do another server sync-- which should result in a download-deletion.
                    
                    SMSyncServer.session.resetMetaData(forUUID: testFile.uuid, resetType: .Undelete)
                    
                    self.clientShouldDeleteFilesCallbacks.append() { uuids in
                        XCTAssert(uuids.count == 1)
                        XCTAssert(uuids[0].UUIDString == testFile.uuidString)
                        
                        let fileAttr = SMSyncServer.session.localFileStatus(testFile.uuid)
                        XCTAssert(fileAttr != nil)
                        XCTAssert(fileAttr!.deleted!)
                        
                        clientShouldDeleteFilesExpectation.fulfill()
                    }
                    
                    self.idleCallbacks.append() {
                        idleAfterShouldDeleteFiles.fulfill()

                        self.errorCallbacks.append() {
                            SMSyncServer.session.resetFromError()
                        }
                        
                        self.idleCallbacks.append() {
                            idleAfterErrorReset.fulfill()
                        }
                        
                        // This is going to fail.
                        SMSyncServer.session.deleteFile(testFile.uuid)
                        
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
                
                self.deleteFiles([testFile1], deletionExpectation: deletionExpectation, commitComplete: commitCompleteDelete, idleExpectation: idleExpectationDeletion) {
                    // Deletion done: Now idle.
                    
                    // Our situation now is that the file has been deleted on the server, and we've marked the file as deleted locally.
                    // HOWEVER, since what we're trying to test is download-deletion, we now need to fake the local meta data state and mark the file as *not* deleted locally, then do another server sync-- which should result in a download-deletion.
                    
                    SMSyncServer.session.resetMetaData(forUUID: testFile1.uuid, resetType: .Undelete)
                    
                    self.clientShouldDeleteFilesCallbacks.append() { uuids in
                        XCTAssert(uuids.count == 1)
                        XCTAssert(uuids[0].UUIDString == testFile1.uuidString)
                        
                        let fileAttr = SMSyncServer.session.localFileStatus(testFile1.uuid)
                        XCTAssert(fileAttr != nil)
                        XCTAssert(fileAttr!.deleted!)
                        
                        clientShouldDeleteFilesExpectation.fulfill()
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
