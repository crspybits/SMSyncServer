//
//  DownloadDeletionRecovery.swift
//  Tests
//
//  Created by Christopher Prince on 4/30/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import XCTest
// The @testable notation lets us access "internal" classes within our project.
@testable import Tests
@testable import SMSyncServer
import SMCoreLib

class DownloadDeletionRecovery: BaseClass {
    private static var crash1 = SMPersistItemBool(name: "DownloadDeletionRecovery.crash1", initialBoolValue: true, persistType: .UserDefaults)
    private static var crashUUIDString1 = SMPersistItemString(name: "DownloadDeletionRecovery.crashUUIDString1", initialStringValue: "", persistType: .UserDefaults)

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    // Network loss
    func testThatDownloadDeletionOfASingleFileThatExistsNetworkLossWorks() {
            
        Network.session().connectionStateCallbacks.addTarget!(self, withSelector: #selector(DownloadDeletionRecovery.recoveryFromNetworkLossAction))
        
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
                    
                    SMSyncServer.session.resetMetaData(forUUID: testFile.uuid, resetType: .Undelete)
                    
                    self.clientShouldDeleteFilesCallbacks.append() { uuids, acknowledgement in
                        XCTAssert(uuids.count == 1)
                        XCTAssert(uuids[0].UUIDString == testFile.uuidString)
                        
                        let fileAttr = SMSyncServer.session.localFileStatus(testFile.uuid)
                        XCTAssert(fileAttr != nil)
                        XCTAssert(fileAttr!.deleted!)
                        
                        acknowledgement()
                        clientShouldDeleteFilesExpectation.fulfill()
                    }
                    
                    self.idleCallbacks.append() {
                        idleAfterShouldDeleteFiles.fulfill()
                    }
                    
                    Network.session().debugNetworkOff = true

                    SMSyncControl.session.nextSyncOperation()
                }
            }
        }
        
        self.waitForExpectations()
    }
    
    @objc private func recoveryFromNetworkLossAction() {
        if !Network.connected() {
            TimedCallback.withDuration(5) {
                Network.session().debugNetworkOff = false
            }
        }
    }

    // Download deletion of a single file: A file that exists, and hasn't been deleted locally.
    // Crash before calling acknowledge; do acknowledge on relaunch.
    func testThatDownloadDeletionOfASingleFileThatExistsCrashBeforeAcknowledgeWorks() {

        let clientShouldDeleteFilesExpectation = self.expectationWithDescription("Should Delete Files")
        let idleAfterShouldDeleteFiles = self.expectationWithDescription("Idle After Should Delete")
        
        if DownloadDeletionRecovery.crash1.boolValue {
            DownloadDeletionRecovery.crash1.boolValue = false
            
            let singleUploadExpectation = self.expectationWithDescription("Single Upload Complete")
            let commitCompleteUpload = self.expectationWithDescription("Commit Complete Upload")
            let idleExpectationUpload = self.expectationWithDescription("Idle Upload")

            let deletionExpectation = self.expectationWithDescription("Single Deletion Complete")
            let commitCompleteDelete = self.expectationWithDescription("Commit Complete Download")
            let idleExpectationDeletion = self.expectationWithDescription("Idle Deletion")
        
            self.extraServerResponseTime = 60
            
            self.waitUntilSyncServerUserSignin() {
                let testFile = TestBasics.session.createTestFile(
                    "DownloadDeletionOfASingleFileThatExistsCrashBeforeAcknowledge")
                DownloadDeletionRecovery.crashUUIDString1.stringValue = testFile.uuidString
                
                self.uploadFiles([testFile], uploadExpectations: [singleUploadExpectation], commitComplete: commitCompleteUpload, idleExpectation: idleExpectationUpload) {
                    // Upload done: Now idle
                    
                    self.deleteFiles([testFile], deletionExpectation: deletionExpectation, commitComplete: commitCompleteDelete, idleExpectation: idleExpectationDeletion) {
                        // Deletion done: Now idle.
                        
                        // Our situation now is that the file has been deleted on the server, and we've marked the file as deleted locally.
                        // HOWEVER, since what we're trying to test is download-deletion, we now need to fake the local meta data state and mark the file as *not* deleted locally, then do another server sync-- which should result in a download-deletion.
                        
                        SMSyncServer.session.resetMetaData(forUUID: testFile.uuid, resetType: .Undelete)
                        
                        self.clientShouldDeleteFilesCallbacks.append() { uuids, acknowledgement in
                            // Crash without calling acknowledgement
                            SMTest.session.crash()
                        }
                        
                        SMSyncControl.session.nextSyncOperation()
                    }
                }
            }
        }
        else {
            // Restart after crash.
            self.processModeChanges = true

            let testFile = TestBasics.session.recreateTestFile(fromUUID: DownloadDeletionRecovery.crashUUIDString1.stringValue)
            
            self.clientShouldDeleteFilesCallbacks.append() { uuids, acknowledgement in
                XCTAssert(uuids.count == 1)
                XCTAssert(uuids[0].UUIDString == testFile.uuidString)
                
                let fileAttr = SMSyncServer.session.localFileStatus(testFile.uuid)
                XCTAssert(fileAttr != nil)
                XCTAssert(fileAttr!.deleted!)
                
                acknowledgement()
                clientShouldDeleteFilesExpectation.fulfill()
            }
            
            self.idleCallbacks.append() {
                idleAfterShouldDeleteFiles.fulfill()
            }
        }
        
        self.waitForExpectations()
    }
}
