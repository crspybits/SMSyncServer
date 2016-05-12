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
    
    // Rejection of a download conflict: Push your conflicting change up to the server instead.
    // Acceptance of a download conflict: Client will remove its conflicting change.
    
    // MARK: Download deletion conflicts

    func setupDownloadDeletionLocalUploadConflict(fileName fileName: String, handleConflict:(testFile:TestFile, ack:()->())->()) {
        let singleUploadExpectation = self.expectationWithDescription("Single Upload Complete")
        let commitCompleteUpload = self.expectationWithDescription("Commit Complete Upload")
        let idleExpectationUpload = self.expectationWithDescription("Idle Upload")

        let deletionExpectation = self.expectationWithDescription("Single Deletion Complete")
        let commitCompleteDelete = self.expectationWithDescription("Commit Complete Download")
        let idleExpectationDeletion = self.expectationWithDescription("Idle Deletion")

        let idleAfterShouldDeleteFiles = self.expectationWithDescription("Idle After Should Delete")

        self.extraServerResponseTime = 60
        
        self.waitUntilSyncServerUserSignin() {
            let testFile = TestBasics.session.createTestFile(fileName)
            
            self.uploadFiles([testFile], uploadExpectations: [singleUploadExpectation], commitComplete: commitCompleteUpload, idleExpectation: idleExpectationUpload) {
                // Upload done: Now idle
                
                self.deleteFiles([testFile], deletionExpectation: deletionExpectation, commitComplete: commitCompleteDelete, idleExpectation: idleExpectationDeletion) {
                    // Deletion done: Now idle.
                    
                    SMSyncServer.session.resetMetaData(forUUID: testFile.uuid, resetType: .Undelete)
                    
                    // Our current situation is that, when we next do a sync with the server, there will be a download-deletion.
                    // To generate a LocalUpload conflict, we need to now do an upload for this file.
                    let newFileContents = "Some new file contents".dataUsingEncoding(NSUTF8StringEncoding)
                    SMSyncServer.session.uploadData(newFileContents!, withDataAttributes: testFile.attr)
                    
                    self.clientShouldDeleteFilesCallbacks.append() { deletions, acknowledgement in
                        XCTAssert(deletions.count == 1)
                        let (uuid, conflict) = deletions[0]
                        XCTAssert(conflict == .LocalUpload)
                        XCTAssert(uuid.UUIDString == testFile.uuidString)
                        
                        let fileAttr = SMSyncServer.session.localFileStatus(testFile.uuid)
                        XCTAssert(fileAttr != nil)
                        XCTAssert(fileAttr!.deleted!)
                        
                        handleConflict(testFile:testFile, ack: acknowledgement)
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

    func testThatDownloadDeletionLocalUploadAcceptWorks() {
        // We should get the idle callback in setupDownloadDeletionLocalUploadConflict after ack is called, so shouldn't need another expectation here.
        
        self.setupDownloadDeletionLocalUploadConflict(fileName: "DownloadDeletionLocalUploadAccept") { testFile, ack in
            
            testFile.remove()
            ack()
        }
    }
    
    func testThatDownloadDeletionLocalUploadRejectWorks() {
    }
    
    // MARK: Download file conflicts
    
    func testThatDownloadFileLocalUploadDeletionAcceptWorks() {
    }
    
    func testThatDownloadFileLocalUploadDeletionRejectWorks() {
    }

    func testThatDownloadFileLocalUploadAcceptWorks() {
    }
    
    func testThatDownloadFileLocalUploadRejectWorks() {
    }
}
