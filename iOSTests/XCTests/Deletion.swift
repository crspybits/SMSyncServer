//
//  Deletion.swift
//  NetDb
//
//  Created by Christopher Prince on 1/12/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import XCTest
// The @testable notation lets us access "internal" classes within our project.
@testable import SMSyncServer

class Deletion: BaseClass {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
        
    // MARK: Deletion cases
    
    func testThatSingleFileDeleteWorks() {
        let commitCompleteCallbackExpectation1 = self.expectationWithDescription("Commit Complete1")
        let commitCompleteCallbackExpectation2 = self.expectationWithDescription("Commit Complete2")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")
        let singleDeletionExpectation = self.expectationWithDescription("Deletion Complete")
        
        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            
            let fileName = "SingleFileDelete"
            let (file, fileSizeBytes) = self.createFile(withName: fileName)
            let fileUUID = NSUUID(UUIDString: file.uuid!)!
            let fileAttributes = SMSyncAttributes(withUUID: fileUUID, mimeType: "text/plain", andRemoteFileName: fileName)
            
            SMSyncServer.session.uploadImmutableFile(file.url(), withFileAttributes: fileAttributes)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file.uuid!)
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                self.checkFileSize(file.uuid!, size: fileSizeBytes) {
                    commitCompleteCallbackExpectation1.fulfill()
                    
                    SMSyncServer.session.deleteFile(NSUUID(UUIDString: file.uuid!)!)
                    SMSyncServer.session.commit()
                }
            }
            
            SMSyncServer.session.commit()
            
            self.deletionCallbacks.append() { uuids in
                XCTAssert(uuids.count == 1)
                XCTAssert(uuids[0].UUIDString == file.uuid!)
                
                singleDeletionExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberDeletions in
                XCTAssert(numberDeletions == 1)
                XCTAssert(!SMSyncServer.session.isOperating)
                
                let fileAttr = SMSyncServer.session.fileStatus(fileUUID)
                XCTAssert(fileAttr != nil)
                XCTAssert(fileAttr!.deleted!)
                
                commitCompleteCallbackExpectation2.fulfill()
            }
        }
        
        self.waitForExpectations()
    }
    
    // Delete two files, then commit.
    func testThatTwoFileDeleteWorks() {
        let commitCompleteCallbackExpectation1 = self.expectationWithDescription("Commit Complete1")
        let commitCompleteCallbackExpectation2 = self.expectationWithDescription("Commit Complete2")
        let uploadExpectation1 = self.expectationWithDescription("Upload1 Complete")
        let uploadExpectation2 = self.expectationWithDescription("Upload2 Complete")

        let twoDeletionExpectation = self.expectationWithDescription("Deletion Complete")
        
        self.extraServerResponseTime = 60
        
        self.waitUntilSyncServerUserSignin() {
            
            let fileName1 = "TwoFileDelete1"
            let (file1, fileSizeBytes1) = self.createFile(withName: fileName1)
            let file1UUID = NSUUID(UUIDString: file1.uuid!)!
            let fileAttributes1 = SMSyncAttributes(withUUID: file1UUID, mimeType: "text/plain", andRemoteFileName: fileName1)
            
            SMSyncServer.session.uploadImmutableFile(file1.url(), withFileAttributes: fileAttributes1)

            let fileName2 = "TwoFileDelete2"
            let (file2, fileSizeBytes2) = self.createFile(withName: fileName2)
            let file2UUID = NSUUID(UUIDString: file2.uuid!)!
            let fileAttributes2 = SMSyncAttributes(withUUID: file2UUID, mimeType: "text/plain", andRemoteFileName: fileName2)
            
            SMSyncServer.session.uploadImmutableFile(file2.url(), withFileAttributes: fileAttributes2)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file1UUID.UUIDString)
                uploadExpectation1.fulfill()
            }
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file2UUID.UUIDString)
                uploadExpectation2.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 2)
                
                self.checkFileSize(file1UUID.UUIDString, size: fileSizeBytes1) {
                    
                    self.checkFileSize(file2UUID.UUIDString, size: fileSizeBytes2) {
                        commitCompleteCallbackExpectation1.fulfill()
                        
                        SMSyncServer.session.deleteFile(file1UUID)
                        SMSyncServer.session.deleteFile(file2UUID)

                        SMSyncServer.session.commit()
                    }
                }
            }
            
            SMSyncServer.session.commit()
            
            self.deletionCallbacks.append() { uuids in
                XCTAssert(uuids.count == 2)
                
                let result1 = uuids.filter({
                    $0.UUIDString == file1UUID.UUIDString
                })
                
                XCTAssert(result1.count == 1)
                
                let result2 = uuids.filter({
                    $0.UUIDString == file2UUID.UUIDString
                })
                
                XCTAssert(result2.count == 1)
                
                twoDeletionExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberDeletions in
                XCTAssert(numberDeletions == 2)
                XCTAssert(!SMSyncServer.session.isOperating)
                
                let fileAttr1 = SMSyncServer.session.fileStatus(file1UUID)
                XCTAssert(fileAttr1 != nil)
                XCTAssert(fileAttr1!.deleted!)

                let fileAttr2 = SMSyncServer.session.fileStatus(file2UUID)
                XCTAssert(fileAttr2 != nil)
                XCTAssert(fileAttr2!.deleted!)
                
                commitCompleteCallbackExpectation2.fulfill()
            }
        }
        
        self.waitForExpectations()
    }
    
    // Delete, commit, upload: On same file: Should fail on the upload.
    func testThatUploadAfterDeleteFails() {
        let commitCompleteCallbackExpectation1 = self.expectationWithDescription("Commit Complete1")
        let commitCompleteCallbackExpectation2 = self.expectationWithDescription("Commit Complete2")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")
        let singleDeletionExpectation = self.expectationWithDescription("Deletion Complete")
        let errorExpectation = self.expectationWithDescription("Error")
        var errorExpected = false
        
        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            
            let fileName = "UploadAfterDelete"
            let (file, fileSizeBytes) = self.createFile(withName: fileName)
            let file1UUID = NSUUID(UUIDString: file.uuid!)!
            let fileAttributes = SMSyncAttributes(withUUID: file1UUID, mimeType: "text/plain", andRemoteFileName: fileName)
            
            SMSyncServer.session.uploadImmutableFile(file.url(), withFileAttributes: fileAttributes)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file1UUID.UUIDString)
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                self.checkFileSize(file1UUID.UUIDString, size: fileSizeBytes) {
                    commitCompleteCallbackExpectation1.fulfill()
                    
                    SMSyncServer.session.deleteFile(NSUUID(UUIDString: file1UUID.UUIDString)!)
                    SMSyncServer.session.commit()
                }
            }
            
            SMSyncServer.session.commit()
            
            self.deletionCallbacks.append() { uuids in
                XCTAssert(uuids.count == 1)
                XCTAssert(uuids[0].UUIDString == file1UUID.UUIDString)
                
                singleDeletionExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberDeletions in
                XCTAssert(numberDeletions == 1)
                commitCompleteCallbackExpectation2.fulfill()
                
                let fileAttr = SMSyncServer.session.fileStatus(file1UUID)
                XCTAssert(fileAttr != nil)
                XCTAssert(fileAttr!.deleted!)
                
                errorExpected = true
                SMSyncServer.session.uploadImmutableFile(file.url(), withFileAttributes: fileAttributes)
                SMSyncServer.session.commit()
                XCTAssert(!SMSyncServer.session.isOperating)
            }
            
            self.errorCallbacks.append() {
                XCTAssert(errorExpected)
                errorExpectation.fulfill()
            }
        }
        
        self.waitForExpectations()
    }
    
    // Delete a file that has already been deleted (and committed)
    
    func testThatDeletingAlreadyDeletedFileFails() {
        let commitCompleteCallbackExpectation1 = self.expectationWithDescription("Commit Complete1")
        let commitCompleteCallbackExpectation2 = self.expectationWithDescription("Commit Complete2")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")
        let singleDeletionExpectation = self.expectationWithDescription("Deletion Complete")
        let errorExpectation = self.expectationWithDescription("Error")
        var errorExpected = false
        
        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            
            let fileName = "DeleteAlreadyDeletedFile"
            let (file, fileSizeBytes) = self.createFile(withName: fileName)
            let fileUUID = NSUUID(UUIDString: file.uuid!)!
            let fileAttributes = SMSyncAttributes(withUUID: fileUUID, mimeType: "text/plain", andRemoteFileName: fileName)
            
            SMSyncServer.session.uploadImmutableFile(file.url(), withFileAttributes: fileAttributes)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file.uuid!)
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                self.checkFileSize(file.uuid!, size: fileSizeBytes) {
                    commitCompleteCallbackExpectation1.fulfill()
                    
                    SMSyncServer.session.deleteFile(fileUUID)
                    SMSyncServer.session.commit()
                }
            }
            
            SMSyncServer.session.commit()
            
            self.deletionCallbacks.append() { uuids in
                XCTAssert(uuids.count == 1)
                XCTAssert(uuids[0].UUIDString == file.uuid!)
                
                singleDeletionExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberDeletions in
                XCTAssert(numberDeletions == 1)
                
                let fileAttr = SMSyncServer.session.fileStatus(fileUUID)
                XCTAssert(fileAttr != nil)
                XCTAssert(fileAttr!.deleted!)
                
                errorExpected = true
                SMSyncServer.session.deleteFile(NSUUID(UUIDString: file.uuid!)!)
                SMSyncServer.session.commit()
                
                XCTAssert(!SMSyncServer.session.isOperating)
                
                commitCompleteCallbackExpectation2.fulfill()
            }
            
            self.errorCallbacks.append() {
                XCTAssert(errorExpected)
                errorExpectation.fulfill()
            }
        }
        
        self.waitForExpectations()
    }
    
    // Delete a file unknown to the sync server. e.g., file never uploaded.
    func testThatDeletingUnknownFileFails() {
        let errorExpectation = self.expectationWithDescription("Error")
        
        self.waitUntilSyncServerUserSignin() {
            let fileName = "UnknownFile"
            let (file, _) = self.createFile(withName: fileName)
            let fileUUID = NSUUID(UUIDString: file.uuid!)!

            self.errorCallbacks.append() {
                let fileAttr = SMSyncServer.session.fileStatus(fileUUID)
                XCTAssert(fileAttr == nil)
                
                errorExpectation.fulfill()
            }
            
            SMSyncServer.session.deleteFile(NSUUID(UUIDString: file.uuid!)!)
            SMSyncServer.session.commit()
            
            XCTAssert(!SMSyncServer.session.isOperating)
        }
        
        self.waitForExpectations()
    }
    
    // MARK: Deletion combined with upload cases
    
    // Upload one file, and delete another file, followed by a commit.
    func testThatCombinedUploadAndDeleteWorks() {
        let commitCompleteCallbackExpectation1 = self.expectationWithDescription("Commit Complete1")
        let commitCompleteCallbackExpectation2 = self.expectationWithDescription("Commit Complete2")
        let uploadExpectation1 = self.expectationWithDescription("Upload1 Complete")
        let uploadExpectation2 = self.expectationWithDescription("Upload2 Complete")
        let singleDeletionExpectation = self.expectationWithDescription("Deletion Complete")
        
        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            
            let fileName1 = "CombinedUploadAndDelete1"
            let (file1, fileSizeBytes1) = self.createFile(withName: fileName1)
            let file1UUID = NSUUID(UUIDString: file1.uuid!)!
            let fileAttributes1 = SMSyncAttributes(withUUID: file1UUID, mimeType: "text/plain", andRemoteFileName: fileName1)
            
            SMSyncServer.session.uploadImmutableFile(file1.url(), withFileAttributes: fileAttributes1)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file1.uuid!)
                uploadExpectation1.fulfill()
            }
            
            let fileName2 = "CombinedUploadAndDelete2"
            let (file2, fileSizeBytes2) = self.createFile(withName: fileName2)
            let file2UUID = NSUUID(UUIDString: file2.uuid!)!
            let fileAttributes2 = SMSyncAttributes(withUUID: file2UUID, mimeType: "text/plain", andRemoteFileName: fileName2)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file2.uuid!)
                uploadExpectation2.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                self.checkFileSize(file1.uuid!, size: fileSizeBytes1) {
                    commitCompleteCallbackExpectation1.fulfill()
                    
                    SMSyncServer.session.deleteFile(file1UUID)
                    
                    SMSyncServer.session.uploadImmutableFile(file2.url(), withFileAttributes: fileAttributes2)
                    
                    SMSyncServer.session.commit()
                }
            }
            
            self.commitCompleteCallbacks.append() { numberOperations in
                XCTAssert(numberOperations == 2)
                self.checkFileSize(file2.uuid!, size: fileSizeBytes2) {
                    XCTAssert(!SMSyncServer.session.isOperating)
                    
                    let fileAttr1 = SMSyncServer.session.fileStatus(file1UUID)
                    XCTAssert(fileAttr1 != nil)
                    XCTAssert(fileAttr1!.deleted!)
                    
                    let fileAttr2 = SMSyncServer.session.fileStatus(file2UUID)
                    XCTAssert(fileAttr2 != nil)
                    XCTAssert(!fileAttr2!.deleted!)
                
                    commitCompleteCallbackExpectation2.fulfill()
                }
            }
            
            SMSyncServer.session.commit()
            
            self.deletionCallbacks.append() { uuids in
                XCTAssert(uuids.count == 1)
                XCTAssert(uuids[0].UUIDString == file1.uuid!)
                
                singleDeletionExpectation.fulfill()
            }
        }
        
        self.waitForExpectations()
    }
    
    // Edge cases. *Should* be able to upload, delete, and commmit the same file. (Should only do the delete, not the upload.)
    func testThatUploadDeleteSameFileWorks() {
        let commitCompleteCallbackExpectation1 = self.expectationWithDescription("Commit Complete1")
        let commitCompleteCallbackExpectation2 = self.expectationWithDescription("Commit Complete2")
        let uploadExpectation1 = self.expectationWithDescription("Upload1 Complete")
        let deletionExpectation = self.expectationWithDescription("Deletion Complete")
        
        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            
            let fileName1 = "UploadDeleteSameFile"
            let (file1, fileSizeBytes1) = self.createFile(withName: fileName1)
            let file1UUID = NSUUID(UUIDString: file1.uuid!)!
            let fileAttributes1 = SMSyncAttributes(withUUID: file1UUID, mimeType: "text/plain", andRemoteFileName: fileName1)
            
            SMSyncServer.session.uploadImmutableFile(file1.url(), withFileAttributes: fileAttributes1)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file1.uuid!)
                uploadExpectation1.fulfill()
            }

            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                
                self.checkFileSize(file1.uuid!, size: fileSizeBytes1) {
                    commitCompleteCallbackExpectation1.fulfill()

                    SMSyncServer.session.uploadImmutableFile(file1.url(), withFileAttributes: fileAttributes1)
                    
                    SMSyncServer.session.deleteFile(file1UUID)
 
                    SMSyncServer.session.commit()
                }
            }
            
            self.commitCompleteCallbacks.append() { numberOperations in
                XCTAssert(numberOperations == 1)
                XCTAssert(!SMSyncServer.session.isOperating)
                
                let fileAttr = SMSyncServer.session.fileStatus(file1UUID)
                XCTAssert(fileAttr != nil)
                XCTAssert(fileAttr!.deleted!)
                
                commitCompleteCallbackExpectation2.fulfill()
            }
            
            SMSyncServer.session.commit()
            
            self.deletionCallbacks.append() { uuids in
                XCTAssert(uuids.count == 1)
                XCTAssert(uuids[0].UUIDString == file1.uuid!)
                
                deletionExpectation.fulfill()
            }
        }
        
        self.waitForExpectations()
    }
    
    // Edge cases. Should *fail* when attempting to delete, upload, and commit the same file.
    func testThatDeleteUploadSameFileFails() {
        let commitCompleteCallbackExpectation1 = self.expectationWithDescription("Commit1 Complete1")
        let commitCompleteCallbackExpectation2 = self.expectationWithDescription("Commit2 Complete1")
        let uploadExpectation1 = self.expectationWithDescription("Upload1 Complete")
        let deleteExpectation = self.expectationWithDescription("Deletion Complete")
        let errorExpectation = self.expectationWithDescription("Error")
        var errorExpected = false
        
        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            
            let fileName1 = "DeleteUploadSameFile"
            let (file1, fileSizeBytes1) = self.createFile(withName: fileName1)
            let fileAttributes1 = SMSyncAttributes(withUUID: NSUUID(UUIDString: file1.uuid!)!, mimeType: "text/plain", andRemoteFileName: fileName1)
            
            SMSyncServer.session.uploadImmutableFile(file1.url(), withFileAttributes: fileAttributes1)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file1.uuid!)
                uploadExpectation1.fulfill()
            }

            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                
                self.checkFileSize(file1.uuid!, size: fileSizeBytes1) {
                    commitCompleteCallbackExpectation1.fulfill()

                    SMSyncServer.session.deleteFile(NSUUID(UUIDString: file1.uuid!)!)

                    errorExpected = true
                    SMSyncServer.session.uploadImmutableFile(file1.url(), withFileAttributes: fileAttributes1)
                    
                    // Our expectation here is that this should delete the file, despite the error delegate callback for the upload after the delete.
                    SMSyncServer.session.commit()
                }
            }
            
            SMSyncServer.session.commit()
            
            self.errorCallbacks.append() {
                XCTAssert(errorExpected)
                errorExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberOperations in
                XCTAssert(numberOperations == 1)
                XCTAssert(!SMSyncServer.session.isOperating)
                commitCompleteCallbackExpectation2.fulfill()
            }
            
            self.deletionCallbacks.append() { uuids in
                XCTAssert(uuids.count == 1)
                XCTAssert(uuids[0].UUIDString == file1.uuid!)
                
                deleteExpectation.fulfill()
            }
        }
        
        self.waitForExpectations()
    }
    
    // Delete two files, the first is fine, but the second is the same as the first.
    func testThatRepeatedDeleteFails() {
        let commitCompleteCallbackExpectation1 = self.expectationWithDescription("Commit Complete1")
        let commitCompleteCallbackExpectation2 = self.expectationWithDescription("Commit Complete2")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")
        let singleDeletionExpectation = self.expectationWithDescription("Deletion Complete")
        let errorExpectation = self.expectationWithDescription("Deletion Complete")

        var errorExpected = false
        
        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            
            let fileName = "RepeatedDelete"
            let (file, fileSizeBytes) = self.createFile(withName: fileName)
            let fileAttributes = SMSyncAttributes(withUUID: NSUUID(UUIDString: file.uuid!)!, mimeType: "text/plain", andRemoteFileName: fileName)
            
            SMSyncServer.session.uploadImmutableFile(file.url(), withFileAttributes: fileAttributes)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file.uuid!)
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                self.checkFileSize(file.uuid!, size: fileSizeBytes) {
                    commitCompleteCallbackExpectation1.fulfill()
                    
                    SMSyncServer.session.deleteFile(NSUUID(UUIDString: file.uuid!)!)
                    
                    errorExpected = true
                    SMSyncServer.session.deleteFile(NSUUID(UUIDString: file.uuid!)!)

                    // Expect the first delete to work.
                    SMSyncServer.session.commit()
                }
            }
            
            SMSyncServer.session.commit()
            
            self.deletionCallbacks.append() { uuids in
                XCTAssert(uuids.count == 1)
                XCTAssert(uuids[0].UUIDString == file.uuid!)
                
                singleDeletionExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberDeletions in
                XCTAssert(numberDeletions == 1)
                XCTAssert(!SMSyncServer.session.isOperating)
                commitCompleteCallbackExpectation2.fulfill()
            }
                        
            self.errorCallbacks.append() {
                XCTAssert(errorExpected)
                errorExpectation.fulfill()
            }
        }
        
        self.waitForExpectations()
    }
    
    // Delete a file with cloud storage name X, then create a new file with the same cloud storage name, but different UUID. That should succeed.
    func testThatDeleteCreateWithSameCloudStorageNameWorks() {
        let commitCompleteCallbackExpectation1 = self.expectationWithDescription("Commit Complete1")
        let commitCompleteCallbackExpectation2 = self.expectationWithDescription("Commit Complete2")
        let commitCompleteCallbackExpectation3 = self.expectationWithDescription("Commit Complete3")
        let uploadExpectation1 = self.expectationWithDescription("Upload1 Complete")
        let uploadExpectation2 = self.expectationWithDescription("Upload2 Complete")
        let singleDeletionExpectation = self.expectationWithDescription("Deletion Complete")
        
        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            
            let remoteFileName = "DeleteCreateWithSameCloudStorageName1"
            let (file1, fileSizeBytes1) = self.createFile(withName: remoteFileName)
            let fileAttributes1 = SMSyncAttributes(withUUID: NSUUID(UUIDString: file1.uuid!)!, mimeType: "text/plain", andRemoteFileName: remoteFileName)

            let fileName = "DeleteCreateWithSameCloudStorageName2"
            let (file2, _) = self.createFile(withName: fileName)
            let fileAttributes2 = SMSyncAttributes(withUUID: NSUUID(UUIDString: file2.uuid!)!, mimeType: "text/plain", andRemoteFileName: remoteFileName)
            
            SMSyncServer.session.uploadImmutableFile(file1.url(), withFileAttributes: fileAttributes1)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file1.uuid!)
                uploadExpectation1.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                self.checkFileSize(file1.uuid!, size: fileSizeBytes1) {
                    commitCompleteCallbackExpectation1.fulfill()
                    
                    SMSyncServer.session.deleteFile(NSUUID(UUIDString: file1.uuid!)!)
                    SMSyncServer.session.commit()
                }
            }
            
            SMSyncServer.session.commit()
            
            self.deletionCallbacks.append() { uuids in
                XCTAssert(uuids.count == 1)
                XCTAssert(uuids[0].UUIDString == file1.uuid!)
                
                singleDeletionExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberDeletions in
                XCTAssert(numberDeletions == 1)
                commitCompleteCallbackExpectation2.fulfill()
                
                SMSyncServer.session.uploadImmutableFile(file2.url(), withFileAttributes: fileAttributes2)
                SMSyncServer.session.commit()
            }

            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file2.uuid!)
                uploadExpectation2.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                XCTAssert(!SMSyncServer.session.isOperating)
                commitCompleteCallbackExpectation3.fulfill()
            }
        }
        
        self.waitForExpectations()
    }
}
