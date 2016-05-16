//
//  DownloadConflicts.swift
//  Tests
//
//  Created by Christopher Prince on 4/25/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import XCTest
// The @testable notation lets us access "internal" classes within our project.
@testable import Tests
@testable import SMSyncServer
import SMCoreLib

class DownloadConflicts: BaseClass {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    // MARK: Download deletion conflicts

    func setupDownloadDeletionLocalUploadConflict(fileName fileName: String, keepConflicting:Bool, handleConflict:(conflict: SMSyncServerConflict,
            testFile:TestFile)->()) {
        let singleUploadExpectation = self.expectationWithDescription("Single Upload Complete")
        let commitCompleteUpload = self.expectationWithDescription("Commit Complete Upload")
        let idleExpectationUpload = self.expectationWithDescription("Idle Upload")

        let deletionExpectation = self.expectationWithDescription("Single Deletion Complete")
        let commitCompleteDelete = self.expectationWithDescription("Commit Complete Download")
        let idleExpectationDeletion = self.expectationWithDescription("Idle Deletion")

        let idleAfterShouldDeleteFiles = self.expectationWithDescription("Idle After Should Delete")
        
        var commitCompleteUpload2:XCTestExpectation?
        var upload2:XCTestExpectation?
        
        if keepConflicting {
            commitCompleteUpload2 = self.expectationWithDescription("Commit Complete Upload")
            upload2 = self.expectationWithDescription("Commit Complete Upload")
        }

        self.extraServerResponseTime = 60
        
        self.waitUntilSyncServerUserSignin() {
            var testFile = TestBasics.session.createTestFile(fileName)
            
            self.uploadFiles([testFile], uploadExpectations: [singleUploadExpectation], commitComplete: commitCompleteUpload, idleExpectation: idleExpectationUpload) {
                // Upload done: Now idle
                
                let newFileContents = "Some new file contents"

                self.deleteFiles([testFile], deletionExpectation: deletionExpectation, commitComplete: commitCompleteDelete, idleExpectation: idleExpectationDeletion) {
                    // Deletion done: Now idle.
                    
                    SMSyncServer.session.resetMetaData(forUUID: testFile.uuid, resetType: .Undelete)
                    
                    // Our current situation is that, when we next do a sync with the server, there will be a download-deletion.
                    // To generate a LocalUpload conflict, we need to now do an upload for this file.
                    let newFileContentsData = newFileContents.dataUsingEncoding(NSUTF8StringEncoding)
                    SMSyncServer.session.uploadData(newFileContentsData!, withDataAttributes: testFile.attr)
                    
                    self.shouldResolveDeletionConflicts.append() { conflicts in
                        XCTAssert(conflicts.count == 1)
                        let (uuid, conflict) = conflicts[0]
                        XCTAssert(conflict.conflictType == .FileUpload)
                        XCTAssert(uuid.UUIDString == testFile.uuidString)
                        
                        let fileAttr = SMSyncServer.session.localFileStatus(testFile.uuid)
                        XCTAssert(fileAttr != nil)
                        XCTAssert(fileAttr!.deleted!)
                        
                        handleConflict(conflict:conflict, testFile:testFile)
                    }
                    
                    // The .Idle callback gets called first
                    self.idleCallbacks.append() {
                        if keepConflicting {
                            idleAfterShouldDeleteFiles.fulfill()
                        }
                        else {
                            // Delete conflicting client operations.
                            
                            let attr = SMSyncServer.session.localFileStatus(testFile.uuid)
                            Assert.If(attr == nil, thenPrintThisString: "Yikes: Nil attr")
                            Assert.If(!attr!.deleted!, thenPrintThisString: "Yikes: not deleted!")
                            
                            TestBasics.session.checkForFileOnServer(testFile.uuidString) { fileExists in
                                XCTAssert(!fileExists)
                                testFile.remove()
                                idleAfterShouldDeleteFiles.fulfill()
                            }
                        }
                    }
                    
                    if keepConflicting {
                        self.singleUploadCallbacks.append() { uuid in
                            XCTAssert(uuid.UUIDString == testFile.uuidString)
                            upload2!.fulfill()
                        }
            
                        // Followed by the commit complete callback.
                        self.commitCompleteCallbacks.append() { numberUploads in
                            XCTAssert(numberUploads == 1)
                            testFile.sizeInBytes = newFileContents.characters.count
                            self.checkFileSizes([testFile]) {
                                let attr = SMSyncServer.session.localFileStatus(testFile.uuid)
                                Assert.If(attr == nil, thenPrintThisString: "Yikes: Nil attr")
                                Assert.If(attr!.deleted!, thenPrintThisString: "Yikes: deleted!")
                                commitCompleteUpload2!.fulfill()
                            }
                        }
                    }
                    
                    SMSyncServer.session.commit()
                }
            }
        }
        
        self.waitForExpectations()
    }

    func testThatDownloadDeletionLocalUploadResolveConflictByKeepWorks() {
        // We should get the idle callback in setupDownloadDeletionLocalUploadConflict after ack is called, so shouldn't need another expectation here. We won't get idle callback, and that fulfilled expectation, without the call to ack() below.
        
        self.setupDownloadDeletionLocalUploadConflict(fileName: "DownloadDeletionLocalUploadResolveConflictByKeep", keepConflicting: true) { conflict, testFile in
            conflict.resolveConflict(resolution: .KeepConflictingClientOperations)
        }
    }

    func testThatDownloadDeletionLocalUploadResolveConflictByDeleteWorks() {
        self.setupDownloadDeletionLocalUploadConflict(fileName: "DownloadDeletionLocalUploadResolveConflictByDelete", keepConflicting: false) { conflict, testFile in
            conflict.resolveConflict(resolution: .DeleteConflictingClientOperations)
            // Need to assert that, after all the server operations have completed, the file has been deleted on server, and is marked as deleted in sync server meta data.
        }
    }
    
    // TODO: Download-deletion, a conflict where there are two files being uploaded. Do both accept and reject.
    
    // MARK: Download file conflicts
    
    func testThatDownloadFileLocalUploadDeletionKeepWorks() {
    }
    
    func testThatDownloadFileLocalUploadDeletionDeleteWorks() {
    }

    func testThatDownloadFileLocalUploadKeepWorks() {
    }
    
    func testThatDownloadFileLocalUploadDeleteWorks() {
    }
}
