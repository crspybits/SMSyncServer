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
    
    func uploadFile(testFile:TestFile, singleUploadExpectation:XCTestExpectation, commitComplete:XCTestExpectation, idleExpectation:XCTestExpectation,
        complete:(()->())?) {
        
        SMSyncServer.session.uploadImmutableFile(testFile.url, withFileAttributes: testFile.attr)
        
        self.singleUploadCallbacks.append() { uuid in
            XCTAssert(uuid.UUIDString == testFile.uuidString)
            singleUploadExpectation.fulfill()
        }
        
        // The .Idle callback gets called first
        self.idleCallbacks.append() {
            idleExpectation.fulfill()
        }
        
        // Followed by the commit complete callback.
        self.commitCompleteCallbacks.append() { numberUploads in
            XCTAssert(numberUploads == 1)
            commitComplete.fulfill()
            
            TestBasics.session.checkFileSize(testFile.uuidString, size: testFile.sizeInBytes) {
                let fileAttr = SMSyncServer.session.localFileStatus(testFile.uuid)
                XCTAssert(fileAttr != nil)
                XCTAssert(!fileAttr!.deleted!)
                complete?()
            }
        }
        
        SMSyncServer.session.commit()
    }
    
    func deleteFile(testFile:TestFile, singleDeletionExpectation:XCTestExpectation?, commitComplete:XCTestExpectation, idleExpectation:XCTestExpectation,
        complete:(()->())?=nil) {
        
        SMSyncServer.session.deleteFile(testFile.uuid)
        
        self.deletionCallbacks.append() { uuids in
            XCTAssert(uuids.count == 1)
            XCTAssert(uuids[0].UUIDString == testFile.uuidString)
            
            singleDeletionExpectation?.fulfill()
        }
        
        // The .Idle callback gets called first
        self.idleCallbacks.append() {
            idleExpectation.fulfill()
        }
        
        // Followed by the commit complete.
        self.commitCompleteCallbacks.append() { numberDeletions in
            if singleDeletionExpectation != nil {
                XCTAssert(numberDeletions == 1)
            }
            
            let fileAttr = SMSyncServer.session.localFileStatus(testFile.uuid)
            XCTAssert(fileAttr != nil)
            XCTAssert(fileAttr!.deleted!)
            
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
            
            self.uploadFile(testFile, singleUploadExpectation: singleUploadExpectation, commitComplete: commitCompleteUpload, idleExpectation: idleExpectationUpload) {
                // Upload done: Now idle
                
                self.deleteFile(testFile, singleDeletionExpectation: deletionExpectation, commitComplete: commitCompleteDelete, idleExpectation: idleExpectationDeletion) {
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
            
            self.uploadFile(testFile, singleUploadExpectation: singleUploadExpectation, commitComplete: commitCompleteUpload, idleExpectation: idleExpectationUpload) {
                // Upload done: Now idle
                
                self.deleteFile(testFile, singleDeletionExpectation: deletionExpectation, commitComplete: commitCompleteDelete, idleExpectation: idleExpectationDeletion) {
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
                    self.deleteFile(testFile, singleDeletionExpectation: nil, commitComplete: commitCompleteDelete2, idleExpectation: idleExpectationDeletion2)
                }
            }
        }
        
        self.waitForExpectations()
    }
    
    // Download deletion of a single file: A file that doesn't exist locally (i.e., that was uploaded and download-deleted before the local device synced with the server).
    
    // Download deletion of a single file: Where the deletion progresses to the deletion callback, but the app crashes before the acknowledge is called. Then, the app restarts: Make sure that the deletion callback is again called.
    
    // Download deletion of two files
    
    // Download deletion of one file with download of one file.
    
    // Download deletion, followed by local deletion of the same file fails.
    
    // Download deletion, followed by upload with same remote storage name works.
}
