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
@testable import Tests

class UploadDeletion: BaseClass {
    
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
        
        // First idle after the upload is completed, and the second after the delete is completed.
        let idleExpectation1 = self.expectationWithDescription("Idle1")
        let idleExpectation2 = self.expectationWithDescription("Idle2")

        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            
            let testFile = TestBasics.session.createTestFile("SingleFileDelete")
            
            SMSyncServer.session.uploadImmutableFile(testFile.url, withFileAttributes: testFile.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile.uuidString)
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(testFile.uuidString, size: testFile.sizeInBytes) {
                    commitCompleteCallbackExpectation1.fulfill()
                    
                    self.idleCallbacks.append() {
                        idleExpectation2.fulfill()
                    }
                    
                    SMSyncServer.session.deleteFile(testFile.uuid)
                    SMSyncServer.session.commit()
                }
            }
            
            SMSyncServer.session.commit()
            
            self.deletionCallbacks.append() { uuids in
                XCTAssert(uuids.count == 1)
                XCTAssert(uuids[0].UUIDString == testFile.uuidString)
                
                singleDeletionExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberDeletions in
                XCTAssert(numberDeletions == 1)
                
                let fileAttr = SMSyncServer.session.localFileStatus(testFile.uuid)
                XCTAssert(fileAttr != nil)
                XCTAssert(fileAttr!.deleted!)
                
                commitCompleteCallbackExpectation2.fulfill()
            }
            
            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation1.fulfill()
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
        let idleExpectation1 = self.expectationWithDescription("Idle1")
        let idleExpectation2 = self.expectationWithDescription("Idle2")
        
        self.extraServerResponseTime = 60
        
        self.waitUntilSyncServerUserSignin() {
            let testFile1 = TestBasics.session.createTestFile("TwoFileDelete1")
            
            SMSyncServer.session.uploadImmutableFile(testFile1.url, withFileAttributes: testFile1.attr)

            let testFile2 = TestBasics.session.createTestFile("TwoFileDelete2")
            
            SMSyncServer.session.uploadImmutableFile(testFile2.url, withFileAttributes: testFile2.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile1.uuidString)
                uploadExpectation1.fulfill()
            }
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile2.uuidString)
                uploadExpectation2.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 2)
                
                TestBasics.session.checkFileSize(testFile1.uuidString, size: testFile1.sizeInBytes) {
                    
                    TestBasics.session.checkFileSize(testFile2.uuidString, size: testFile2.sizeInBytes) {
                        commitCompleteCallbackExpectation1.fulfill()
                        
                        SMSyncServer.session.deleteFile(testFile1.uuid)
                        SMSyncServer.session.deleteFile(testFile2.uuid)
            
                        // let idleExpectation = self.expectationWithDescription("Idle")
                        self.idleCallbacks.append() {
                            idleExpectation2.fulfill()
                        }
                        
                        SMSyncServer.session.commit()
                    }
                }
            }

            self.idleCallbacks.append() {
                idleExpectation1.fulfill()
            }
            
            SMSyncServer.session.commit()
            
            self.deletionCallbacks.append() { uuids in
                XCTAssert(uuids.count == 2)
                
                let result1 = uuids.filter({
                    $0.UUIDString == testFile1.uuidString
                })
                
                XCTAssert(result1.count == 1)
                
                let result2 = uuids.filter({
                    $0.UUIDString == testFile2.uuidString
                })
                
                XCTAssert(result2.count == 1)
                
                twoDeletionExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberDeletions in
                XCTAssert(numberDeletions == 2)
                
                let fileAttr1 = SMSyncServer.session.localFileStatus(testFile1.uuid)
                XCTAssert(fileAttr1 != nil)
                XCTAssert(fileAttr1!.deleted!)

                let fileAttr2 = SMSyncServer.session.localFileStatus(testFile2.uuid)
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
        let errorCallbackExpectation = self.expectationWithDescription("ErrorCallback")
        let idleExpectation1 = self.expectationWithDescription("Idle1")
        let idleExpectation2 = self.expectationWithDescription("Idle2")
        let idleExpectation3 = self.expectationWithDescription("Idle3")

        var errorExpected = false
        
        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            
            let testFile = TestBasics.session.createTestFile("UploadAfterDelete")
            
            SMSyncServer.session.uploadImmutableFile(testFile.url, withFileAttributes: testFile.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile.uuidString)
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(testFile.uuidString, size: testFile.sizeInBytes) {
                    commitCompleteCallbackExpectation1.fulfill()
                    
                    // let idleExpectation = self.expectationWithDescription("Idle")
                    self.idleCallbacks.append() {
                        idleExpectation2.fulfill()
                    }
                    
                    SMSyncServer.session.deleteFile(testFile.uuid)
                    SMSyncServer.session.commit()
                }
            }
            
            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation1.fulfill()
            }
            
            SMSyncServer.session.commit()
            
            self.deletionCallbacks.append() { uuids in
                XCTAssert(uuids.count == 1)
                XCTAssert(uuids[0].UUIDString == testFile.uuidString)
                
                singleDeletionExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberDeletions in
                XCTAssert(numberDeletions == 1)
                commitCompleteCallbackExpectation2.fulfill()
                
                let fileAttr = SMSyncServer.session.localFileStatus(testFile.uuid)
                XCTAssert(fileAttr != nil)
                XCTAssert(fileAttr!.deleted!)
                
                // let idleExpectation = self.expectationWithDescription("Idle")
                self.idleCallbacks.append() {
                    idleExpectation3.fulfill()
                }
                
                errorExpected = true
                SMSyncServer.session.uploadImmutableFile(testFile.url, withFileAttributes: testFile.attr)
                SMSyncServer.session.commit()
            }
            
            self.errorCallbacks.append() {
                XCTAssert(errorExpected)
                errorExpectation.fulfill()
                
                SMSyncServer.session.resetFromError() { error in
                    XCTAssert(error == nil)
                    errorCallbackExpectation.fulfill()
                }
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
        let errorCallbackExpectation = self.expectationWithDescription("Error Callback")
        let idleExpectation1 = self.expectationWithDescription("Idle1")
        let idleExpectation2 = self.expectationWithDescription("Idle2")
        let idleExpectation3 = self.expectationWithDescription("Idle3")

        var errorExpected = false
        
        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            
            let testFile = TestBasics.session.createTestFile("DeleteAlreadyDeletedFile")
            
            SMSyncServer.session.uploadImmutableFile(testFile.url, withFileAttributes: testFile.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile.uuidString)
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(testFile.uuidString, size: testFile.sizeInBytes) {
                    commitCompleteCallbackExpectation1.fulfill()
                    
                    // let idleExpectation = self.expectationWithDescription("Idle")
                    self.idleCallbacks.append() {
                        idleExpectation2.fulfill()
                    }
                    
                    SMSyncServer.session.deleteFile(testFile.uuid)
                    SMSyncServer.session.commit()
                }
            }
            
            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation1.fulfill()
            }
            
            SMSyncServer.session.commit()
            
            self.deletionCallbacks.append() { uuids in
                XCTAssert(uuids.count == 1)
                XCTAssert(uuids[0].UUIDString == testFile.uuidString)
                
                singleDeletionExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberDeletions in
                XCTAssert(numberDeletions == 1)
                
                let fileAttr = SMSyncServer.session.localFileStatus(testFile.uuid)
                XCTAssert(fileAttr != nil)
                XCTAssert(fileAttr!.deleted!)
                
                // let idleExpectation = self.expectationWithDescription("Idle")
                self.idleCallbacks.append() {
                    idleExpectation3.fulfill()
                }
            
                errorExpected = true
                SMSyncServer.session.deleteFile(testFile.uuid)
                SMSyncServer.session.commit()
                
                commitCompleteCallbackExpectation2.fulfill()
            }
            
            self.errorCallbacks.append() {
                XCTAssert(errorExpected)
                errorExpectation.fulfill()
                
                SMSyncServer.session.resetFromError() { error in
                    XCTAssert(error == nil)
                    errorCallbackExpectation.fulfill()
                }
            }
        }
        
        self.waitForExpectations()
    }
    
    // Delete a file unknown to the sync server. e.g., file never uploaded.
    func testThatDeletingUnknownFileFails() {
        let errorExpectation = self.expectationWithDescription("Error")
        let errorCallbackExpectation = self.expectationWithDescription("Error Callback")
        let idleExpectation = self.expectationWithDescription("Idle")
        
        self.waitUntilSyncServerUserSignin() {
            let testFile = TestBasics.session.createTestFile("UnknownFile")

            self.errorCallbacks.append() {
                let fileAttr = SMSyncServer.session.localFileStatus(testFile.uuid)
                XCTAssert(fileAttr == nil)
                
                errorExpectation.fulfill()
                
                SMSyncServer.session.resetFromError() { error in
                    XCTAssert(error == nil)
                    errorCallbackExpectation.fulfill()
                }
            }
            
            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation.fulfill()
            }
            
            SMSyncServer.session.deleteFile(testFile.uuid)
            SMSyncServer.session.commit()
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
        let idleExpectation1 = self.expectationWithDescription("Idle1")
        let idleExpectation2 = self.expectationWithDescription("Idle2")

        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            
            let testFile1 = TestBasics.session.createTestFile("CombinedUploadAndDelete1")
            
            SMSyncServer.session.uploadImmutableFile(testFile1.url, withFileAttributes: testFile1.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile1.uuidString)
                uploadExpectation1.fulfill()
            }
            
            let testFile2 = TestBasics.session.createTestFile("CombinedUploadAndDelete2")
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile2.uuidString)
                uploadExpectation2.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(testFile1.uuidString, size: testFile1.sizeInBytes) {
                    commitCompleteCallbackExpectation1.fulfill()
                    
                    SMSyncServer.session.deleteFile(testFile1.uuid)
                    
                    SMSyncServer.session.uploadImmutableFile(testFile2.url, withFileAttributes: testFile2.attr)
                    
                    // let idleExpectation = self.expectationWithDescription("Idle")
                    self.idleCallbacks.append() {
                        idleExpectation2.fulfill()
                    }
                    
                    SMSyncServer.session.commit()
                }
            }
            
            self.commitCompleteCallbacks.append() { numberOperations in
                XCTAssert(numberOperations == 2)
                TestBasics.session.checkFileSize(testFile2.uuidString, size: testFile2.sizeInBytes) {
                    let fileAttr1 = SMSyncServer.session.localFileStatus(testFile1.uuid)
                    XCTAssert(fileAttr1 != nil)
                    XCTAssert(fileAttr1!.deleted!)
                    
                    let fileAttr2 = SMSyncServer.session.localFileStatus(testFile2.uuid)
                    XCTAssert(fileAttr2 != nil)
                    XCTAssert(!fileAttr2!.deleted!)
                
                    commitCompleteCallbackExpectation2.fulfill()
                }
            }

            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation1.fulfill()
            }
            
            SMSyncServer.session.commit()
            
            self.deletionCallbacks.append() { uuids in
                XCTAssert(uuids.count == 1)
                XCTAssert(uuids[0].UUIDString == testFile1.uuidString)
                
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
        let idleExpectation1 = self.expectationWithDescription("Idle1")
        let idleExpectation2 = self.expectationWithDescription("Idle2")

        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            
            let testFile1 = TestBasics.session.createTestFile("UploadDeleteSameFile")
            
            SMSyncServer.session.uploadImmutableFile(testFile1.url, withFileAttributes: testFile1.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile1.uuidString)
                uploadExpectation1.fulfill()
            }

            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                
                TestBasics.session.checkFileSize(testFile1.uuidString, size: testFile1.sizeInBytes) {
                    commitCompleteCallbackExpectation1.fulfill()

                    SMSyncServer.session.uploadImmutableFile(testFile1.url, withFileAttributes: testFile1.attr)
                    
                    SMSyncServer.session.deleteFile(testFile1.uuid)
                    
                    // let idleExpectation = self.expectationWithDescription("Idle")
                    self.idleCallbacks.append() {
                        idleExpectation2.fulfill()
                    }
 
                    SMSyncServer.session.commit()
                }
            }
            
            self.commitCompleteCallbacks.append() { numberOperations in
                XCTAssert(numberOperations == 1)
                
                let fileAttr = SMSyncServer.session.localFileStatus(testFile1.uuid)
                XCTAssert(fileAttr != nil)
                XCTAssert(fileAttr!.deleted!)
                
                commitCompleteCallbackExpectation2.fulfill()
            }
            
            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation1.fulfill()
            }
            
            SMSyncServer.session.commit()
            
            self.deletionCallbacks.append() { uuids in
                XCTAssert(uuids.count == 1)
                XCTAssert(uuids[0].UUIDString == testFile1.uuidString)
                
                deletionExpectation.fulfill()
            }
        }
        
        self.waitForExpectations()
    }
    
    // Edge cases. Should *fail* when attempting to delete, upload, and commit the same file.
    func testThatDeleteUploadSameFileFails() {
        let commitCompleteCallbackExpectation1 = self.expectationWithDescription("Commit1 Complete1")
        //let commitCompleteCallbackExpectation2 = self.expectationWithDescription("Commit2 Complete1")
        let uploadExpectation1 = self.expectationWithDescription("Upload1 Complete")
        //let deleteExpectation = self.expectationWithDescription("Deletion Complete")
        let errorExpectation = self.expectationWithDescription("Error")
        let errorCallbackExpectation = self.expectationWithDescription("Error Callback")
        let idleExpectation1 = self.expectationWithDescription("Idle1")
        let idleExpectation2 = self.expectationWithDescription("Idle2")

        var errorExpected = false
        
        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            
            let testFile1 = TestBasics.session.createTestFile("DeleteUploadSameFile")
            
            SMSyncServer.session.uploadImmutableFile(testFile1.url, withFileAttributes: testFile1.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile1.uuidString)
                uploadExpectation1.fulfill()
            }

            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                
                TestBasics.session.checkFileSize(testFile1.uuidString, size: testFile1.sizeInBytes) {
                    commitCompleteCallbackExpectation1.fulfill()

                    SMSyncServer.session.deleteFile(testFile1.uuid)
                    
                    // let idleExpectation = self.expectationWithDescription("Idle")
                    self.idleCallbacks.append() {
                        idleExpectation2.fulfill()
                    }

                    errorExpected = true
                    SMSyncServer.session.uploadImmutableFile(testFile1.url, withFileAttributes: testFile1.attr)

                    // Our expectation here is that this should *not* delete the file. This is because the resetFromError() call does a flush operation, removing uploads, and upload-deletions.
                    SMSyncServer.session.commit()
                }
            }
            
            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation1.fulfill()
            }
            
            self.errorCallbacks.append() {
                XCTAssert(errorExpected)
                errorExpectation.fulfill()
                
                SMSyncServer.session.resetFromError() { error in
                    XCTAssert(error == nil)
                    errorCallbackExpectation.fulfill()
                }
            }
            
            /*
            self.commitCompleteCallbacks.append() { numberOperations in
                XCTAssert(numberOperations == 1)
                commitCompleteCallbackExpectation2.fulfill()
            }
            
            self.deletionCallbacks.append() { uuids in
                XCTAssert(uuids.count == 1)
                XCTAssert(uuids[0].UUIDString == testFile1.uuidString)
                
                deleteExpectation.fulfill()
            }*/
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    // Delete two files, the first is fine, but the second is the same as the first.
    func testThatRepeatedDeleteFails() {
        let commitCompleteCallbackExpectation1 = self.expectationWithDescription("Commit Complete1")
        //let commitCompleteCallbackExpectation2 = self.expectationWithDescription("Commit Complete2")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")
        //let singleDeletionExpectation = self.expectationWithDescription("Deletion Complete")
        let errorExpectation = self.expectationWithDescription("Error")
        let errorCallbackExpectation = self.expectationWithDescription("Error Callback")
        let idleExpectation1 = self.expectationWithDescription("Idle1")
        let idleExpectation2 = self.expectationWithDescription("Idle2")

        var errorExpected = false
        
        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            
            let testFile = TestBasics.session.createTestFile("RepeatedDelete")
            
            SMSyncServer.session.uploadImmutableFile(testFile.url, withFileAttributes: testFile.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile.uuidString)
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(testFile.uuidString, size: testFile.sizeInBytes) {
                    commitCompleteCallbackExpectation1.fulfill()
                    
                    SMSyncServer.session.deleteFile(testFile.uuid)

                    // let idleExpectation = self.expectationWithDescription("Idle")
                    self.idleCallbacks.append() {
                        idleExpectation2.fulfill()
                    }
                    
                    errorExpected = true
                    SMSyncServer.session.deleteFile(testFile.uuid)
                    
                    // Expect neither delete to work-- because of the flush in the error reset.
                    SMSyncServer.session.commit()
                }
            }

            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation1.fulfill()
            }
            
            SMSyncServer.session.commit()
            
            /*
            self.deletionCallbacks.append() { uuids in
                XCTAssert(uuids.count == 1)
                XCTAssert(uuids[0].UUIDString == testFile.uuidString)
                
                singleDeletionExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberDeletions in
                XCTAssert(numberDeletions == 1)
                commitCompleteCallbackExpectation2.fulfill()
            }*/
                        
            self.errorCallbacks.append() {
                XCTAssert(errorExpected)
                errorExpectation.fulfill()
                
                SMSyncServer.session.resetFromError() { error in
                    XCTAssert(error == nil)
                    errorCallbackExpectation.fulfill()
                }
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
        let idleExpectation1 = self.expectationWithDescription("Idle1")
        let idleExpectation2 = self.expectationWithDescription("Idle2")
        let idleExpectation3 = self.expectationWithDescription("Idle3")
        
        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            
            let testFile1 = TestBasics.session.createTestFile("DeleteCreateWithSameCloudStorageName1")
            var testFile2 = TestBasics.session.createTestFile("DeleteCreateWithSameCloudStorageName2")
            testFile2.remoteFileName = testFile1.fileName
            
            SMSyncServer.session.uploadImmutableFile(testFile1.url, withFileAttributes: testFile1.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile1.uuidString)
                uploadExpectation1.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(testFile1.uuidString, size: testFile1.sizeInBytes) {
                    commitCompleteCallbackExpectation1.fulfill()
                    
                    // let idleExpectation = self.expectationWithDescription("Idle")
                    self.idleCallbacks.append() {
                        idleExpectation2.fulfill()
                    }
                    
                    SMSyncServer.session.deleteFile(testFile1.uuid)
                    SMSyncServer.session.commit()
                }
            }
            
            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation1.fulfill()
            }
            
            SMSyncServer.session.commit()
            
            self.deletionCallbacks.append() { uuids in
                XCTAssert(uuids.count == 1)
                XCTAssert(uuids[0].UUIDString == testFile1.uuidString)
                
                singleDeletionExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberDeletions in
                XCTAssert(numberDeletions == 1)
                commitCompleteCallbackExpectation2.fulfill()
                
                // let idleExpectation = self.expectationWithDescription("Idle")
                self.idleCallbacks.append() {
                    idleExpectation3.fulfill()
                }
                
                SMSyncServer.session.uploadImmutableFile(testFile2.url, withFileAttributes: testFile2.attr)
                SMSyncServer.session.commit()
            }

            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile2.uuidString)
                uploadExpectation2.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                commitCompleteCallbackExpectation3.fulfill()
            }
        }
        
        self.waitForExpectations()
    }
}
