//
//  UploadRecovery.swift
//  Tests
//
//  Created by Christopher Prince on 2/29/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import XCTest
@testable import Tests
@testable import SMSyncServer
import SMCoreLib

class UploadRecovery: BaseClass {
        
    // Flag so I can get ordering of expectations right.
    var doneRecovery = false
    
    private static var crashUUIDString1 = SMPersistItemString(name: "SMUploadFiles.crashUUIDString1", initialStringValue: "", persistType: .UserDefaults)

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
        
        // Put setup code here. This method is called before the invocation of each test method in the class.
        self.doneRecovery = false
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    //MARK: Recovery tests
    
    // When we get network access back, should treat this like an app launch and see if we need to do recovery. To test this: Create a new test case where, when we get network access back, do the same procedure/method as during app launch. The test case will consist of something like testThatRecoveryAfterAppCrashWorks(): Start an upload, cause it to fail because of network loss, then immediately bring the network back online and do the recovery.
    func testThatRecoveryFromNetworkLossWorks() {
        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Upload Complete")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")

        self.extraServerResponseTime = 30

        self.waitUntilSyncServerUserSignin() {
            
            let testFile = TestBasics.session.createTestFile("NetworkRecovery1")
            
            SMSyncServer.session.uploadImmutableFile(testFile.url, withFileAttributes: testFile.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile.uuidString)
                Network.session().debugNetworkOff = true
                singleUploadExpectation.fulfill()
            }
            
            Network.session().connectionStateCallbacks.addTarget!(self, withSelector: "recoveryFromNetworkLossAction")
            
            // I'm not putting a recovery expectation in here because internally this recovery goes through a number of steps -- it waits to try to make sure the operation doesn't switch from Not Started to In Progress.
            self.singleRecoveryCallback =  { mode in
                self.numberOfRecoverySteps += 1
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(self.numberOfRecoverySteps >= 1)
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(testFile.uuidString, size: testFile.sizeInBytes) {
                    uploadCompleteCallbackExpectation.fulfill()
                }
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    // This method applies to the above test only. If I just turn the network back on, immediately, I will not get this test to work. Because the network being off will never be detected immediately after the upload. So, instead, I'm delaying the network coming back on for a few seconds.
    func recoveryFromNetworkLossAction() {
        if !Network.connected() {
            TimedCallback.withDuration(5) {
                Network.session().debugNetworkOff = false
            }
        }
    }
    
    // The error is client side, determined by context.
    func doTestThatUploadRecoveryWorks(inContext context:SMTestContext, withFileName fileName: String) {
        // [1]. Have to create the expectations before the wait for signin too. Or XCTests doesn't know there are expectations to wait for.
        let progressCallbackExpectation = self.expectationWithDescription("Progress Callback")
        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Upload Complete")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")

        // [1].
        self.waitUntilSyncServerUserSignin() {
            
            SMTest.session.doClientFailureTest(context)
            
            let testFile = TestBasics.session.createTestFile(fileName)

            SMSyncServer.session.uploadImmutableFile(testFile.url, withFileAttributes: testFile.attr)
            
            self.singleRecoveryCallback = { mode in
                // Not going to worry about which particular recovery mode we're in now. That's too internal to the sync server.
                XCTAssertTrue(!self.doneRecovery)
                self.doneRecovery = true
                progressCallbackExpectation.fulfill()
            }
            
            self.singleUploadCallbacks.append() { (uuid:NSUUID) in
                XCTAssert(uuid.UUIDString == testFile.uuidString)
                
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssertTrue(self.doneRecovery)
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(testFile.uuidString, size: testFile.sizeInBytes) {
                    uploadCompleteCallbackExpectation.fulfill()
                }
            }
            
            SMSyncServer.session.commit()
            
            // Expecting that we'll get delegate callback on progress and then delegate callback on uploadComplete, without an error.
        }
        
        self.waitForExpectations()
    }
    
    func testThatStartFileChangesRecoveryWorks() {
        self.doTestThatUploadRecoveryWorks(inContext: .Lock, withFileName: SMTestContext.Lock.rawValue)
    }
    
    func testThatGetFileIndexRecoveryWorks() {
        self.doTestThatUploadRecoveryWorks(inContext: .GetFileIndex, withFileName: SMTestContext.GetFileIndex.rawValue)
    }
    
    func testThatUploadFilesRecoveryWorks() {
        self.doTestThatUploadRecoveryWorks(inContext: .UploadFiles, withFileName: SMTestContext.UploadFiles.rawValue)
    }
    
    func testThatCommitChangesRecoveryWorks() {
        self.doTestThatUploadRecoveryWorks(inContext: .OutboundTransfer, withFileName: SMTestContext.OutboundTransfer.rawValue + "A")
    }
    
    // TODO: [3]. Create a test case where we exceed the number of successive times we can try to recover from the same error (.FileChangesRecovery).
    
    // Server-side detailed testing following from CommitChanges
    func testThatServerCommitChangesTestCaseWorks() {
        let context = SMTestContext.OutboundTransfer
        let serverTestCase = SMServerConstants.dbTcCommitChanges
        let fileName = context.rawValue + String(serverTestCase)

        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Upload Complete")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")

        // [1].
        self.waitUntilSyncServerUserSignin() {

            SMTest.session.serverDebugTest = serverTestCase
            
            let testFile = TestBasics.session.createTestFile(fileName)

            SMSyncServer.session.uploadImmutableFile(testFile.url, withFileAttributes: testFile.attr)
            
            self.singleRecoveryCallback = { mode in
                // So we don't get the error test cases on the server again
                SMTest.session.serverDebugTest = nil
        
                // Not going to worry about which particular recovery mode we're in now. That's too internal to the sync server.
                self.numberOfRecoverySteps += 1
            }
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile.uuidString)
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(self.numberOfRecoverySteps >= 1)
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(testFile.uuidString, size: testFile.sizeInBytes) {
                    uploadCompleteCallbackExpectation.fulfill()
                }
            }
            
            SMSyncServer.session.commit()
            
            // Expecting that we'll get delegate callback on progress and then delegate callback on uploadComplete, without an error.
        }
        
        self.waitForExpectations()
    }
    
    // Server-side detailed testing of Transfer Recovery.
    func transferRecovery(transferTestCase serverTestCase:Int) {
        
        self.extraServerResponseTime = 60
        
        let context = SMTestContext.OutboundTransfer
        let fileName = context.rawValue + String(serverTestCase)

        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Upload Complete")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")

        // [1].
        self.waitUntilSyncServerUserSignin() {

            SMTest.session.serverDebugTest = serverTestCase
            
            let testFile = TestBasics.session.createTestFile(fileName)

            SMSyncServer.session.uploadImmutableFile(testFile.url, withFileAttributes: testFile.attr)

            self.singleRecoveryCallback = { mode in
                // So we don't get the error test cases on the server again
                SMTest.session.serverDebugTest = nil
        
                // Not going to worry about which particular recovery mode we're in now. That's too internal to the sync server.
                // Also not going to worry about exact number of recovery steps. For the same reason.
                self.numberOfRecoverySteps += 1
            }
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile.uuidString)
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(self.numberOfRecoverySteps >= 1)
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(testFile.uuidString, size: testFile.sizeInBytes) {
                    uploadCompleteCallbackExpectation.fulfill()
                }
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    // Simulate a failure while transferring files to cloud storage.
    func testThatServerSendFilesTestCaseWorks() {
        self.transferRecovery(transferTestCase: SMServerConstants.dbTcTransferFiles)
    }
    
    func testThatServerRemoveLockAfterCloudStorageTransferTestCaseWorks() {
        self.transferRecovery(transferTestCase: SMServerConstants.dbTcRemoveLockAfterCloudStorageTransfer)
    }
    
    // Simulate a failure while updating collections on the server during transfer to cloud storage-- this is important so that we know that the log scheme I'm using on the server can enable recovery.
    func testThatServerSendFilesUpdateOneFileTestCaseWorks() {
        self.transferRecovery(transferTestCase: SMServerConstants.dbTcSendFilesUpdate)
    }
    
    // Same as previous, but with two files. This test will cause a failure immediately after the first file is transferred to cloud storage.
    func testThatServerSendFilesUpdateTwoFilesTestCaseWorks() {
        
        self.extraServerResponseTime = 60
        
        let serverTestCase = SMServerConstants.dbTcSendFilesUpdate
        let context = SMTestContext.OutboundTransfer
        let fileName1 = context.rawValue + String(serverTestCase) + "A"
        let fileName2 = context.rawValue + String(serverTestCase) + "B"
        
        //let progressCallbackExpectation1 = self.expectationWithDescription("Progress Callback1")
        //let progressCallbackExpectation2 = self.expectationWithDescription("Progress Callback2")

        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Upload Complete")
        let uploadExpectation1 = self.expectationWithDescription("Upload1 Complete")
        let uploadExpectation2 = self.expectationWithDescription("Upload2 Complete")

        // [1].
        self.waitUntilSyncServerUserSignin() {

            SMTest.session.serverDebugTest = serverTestCase
            
            let testFile1 = TestBasics.session.createTestFile(fileName1)

            SMSyncServer.session.uploadImmutableFile(testFile1.url, withFileAttributes: testFile1.attr)
            
            let testFile2 = TestBasics.session.createTestFile(fileName2)

            SMSyncServer.session.uploadImmutableFile(testFile2.url, withFileAttributes: testFile2.attr)

            self.singleRecoveryCallback = { mode in
                // So we don't get the error test cases on the server again
                SMTest.session.serverDebugTest = nil
        
                // Not going to worry about which particular recovery mode we're in now. That's too internal to the sync server.
                self.numberOfRecoverySteps += 1
            }
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile1.uuidString)
                uploadExpectation1.fulfill()
            }
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile2.uuidString)
                uploadExpectation2.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(self.numberOfRecoverySteps >= 1)
                XCTAssert(numberUploads == 2)
                TestBasics.session.checkFileSize(testFile1.uuidString, size: testFile1.sizeInBytes) {
                    TestBasics.session.checkFileSize(testFile2.uuidString, size: testFile2.sizeInBytes) {
                        uploadCompleteCallbackExpectation.fulfill()
                    }
                }
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }

    // App crashes mid-way through the upload operation. This is a relevant test because it seems likely that the network can be lost by the mobile device during an extended upload.
    // This test will intentionally fail the first time through (due to the app crash), and you have to manually run it a 2nd time to get it to succeed.
    // I am leaving this test normally disabled in XCTests in Xcode so that I can enable it, manually run it as needed, and then disable it again.
    func testThatRecoveryAfterAppCrashWorks() {
        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Upload Completion Callback")
        let progressCallbackExpected = self.expectationWithDescription("Progress Callback")

        // Don't need to wait for sign in the second time through because the delay for recovery is imposed in SMSyncServer appLaunchSetup-- after sign in, the recovery will automatically start.
        if Upload.recoveryAfterAppCrash1.boolValue {
            Upload.recoveryAfterAppCrash1.boolValue = false
            
            let singleUploadExpectation = self.expectationWithDescription("Upload Callback")

            self.waitUntilSyncServerUserSignin() {

                // This will fake a failure immediately after .UploadFiles, but it will have really succeeded on uploading the file.
                SMTest.session.doClientFailureTest(.UploadFiles)
                
                let testFile = TestBasics.session.createTestFile("RecoveryAfterAppCrash")

                SMSyncServer.session.uploadImmutableFile(testFile.url, withFileAttributes: testFile.attr)
                
                self.singleUploadCallbacks.append() { uuid in
                    XCTAssert(uuid.UUIDString == testFile.uuidString)
                    singleUploadExpectation.fulfill()
                }
            
                self.singleRecoveryCallback = { mode in
                    // Not going to worry about which particular recovery mode we're in now. That's too internal to the sync server.
                    progressCallbackExpected.fulfill()

                    SMTest.session.crash()
                    // NOTE: XCTFail has no actual effect on the running app itself. I.e., it doesn't cause the app to crash or fail. I need the app to crash because otherwise, the recovery process will proceed within fileChangesRecovery() in SMUploadFiles.
                    // XCTFail(msg)
                }
            
                SMSyncServer.session.commit()
            }
        }
        else {
            // 2nd run of test.
            
            self.singleRecoveryCallback = { mode in
                // Not going to worry about which particular recovery mode we're in now. That's too internal to the sync server.
                progressCallbackExpected.fulfill()
            }
            
            // 2nd run we don't get an upload because the upload actually happened the first time around.
            /*
            self.singleUploadCallbacks.append() { uuid in
                singleUploadExpectation.fulfill()
            }*/
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssertEqual(numberUploads, 1)
                // NOTE: We could do a file size check here, after the commit succeeds, but I'd have to persist the file size across app launches, or go back to the file and see what size it is.
                uploadCompleteCallbackExpectation.fulfill()
            }
        }
        
        self.waitForExpectations()
    }
    
    // App crashes after uploading 1 of 2 files. This is a relevant test because the recovery has to determine that one file has already been uploaded, and only upload the second one.
    // This test will intentionally fail the first time through (due to the app crash), and you have to manually run it a 2nd time to get it to succeed.
    // I am leaving this test normally disabled in XCTests in Xcode so that I can enable it, manually run it as needed, and then disable it again.
    func testThatRecoveryAfter1Of2UploadsAppCrashWorks() {
        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Upload Completion Callback")
        let progressCallbackExpected = self.expectationWithDescription("Progress Callback")
        
        let testFileNameBase = "RecoveryAfter1Of2UploadsAppCrash"
        let testFileName1 = testFileNameBase + ".1"
        let testFileName2 = testFileNameBase + ".2"

        // Don't need to wait for sign in the second time through because the delay for recovery is imposed in SMSyncServer appLaunchSetup-- after sign in, the recovery will automatically start.
        if Upload.recoveryAfterAppCrash2.boolValue {
            Upload.recoveryAfterAppCrash2.boolValue = false

            self.waitUntilSyncServerUserSignin() {
                
                let testFile1 = TestBasics.session.createTestFile(testFileName1)
                let testFile2 = TestBasics.session.createTestFile(testFileName2)
                UploadRecovery.crashUUIDString1.stringValue = testFile2.uuidString

                SMSyncServer.session.uploadImmutableFile(testFile1.url, withFileAttributes: testFile1.attr)
                SMSyncServer.session.uploadImmutableFile(testFile2.url, withFileAttributes: testFile2.attr)
                
                self.singleUploadCallbacks.append() { uuid in
                    XCTAssert(uuid.UUIDString == testFile1.uuidString)
                    
                    // Can't check file size -- while the upload has finished, the outbound transfer may not yet have.
                    SMTest.session.crash()
                }
            
                self.singleRecoveryCallback = { mode in
                    // Not going to worry about which particular recovery mode we're in now. That's too internal to the sync server.
                    progressCallbackExpected.fulfill()
                }
            
                SMSyncServer.session.commit()
            }
        }
        else {
            // 2nd run of test.
            let testFile2 = TestBasics.session.recreateTestFile(fromUUID: UploadRecovery.crashUUIDString1.stringValue)
            
            let secondUploadExpectation = self.expectationWithDescription("Upload Callback")

            self.singleRecoveryCallback = { mode in
                // Not going to worry about which particular recovery mode we're in now. That's too internal to the sync server.
                progressCallbackExpected.fulfill()
            }
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile2.uuidString)
                secondUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssertEqual(numberUploads, 2)
                TestBasics.session.checkFileSize(testFile2.uuidString, size: testFile2.sizeInBytes) {
                    uploadCompleteCallbackExpectation.fulfill()
                }
            }
        }
        
        self.waitForExpectations()
    }
}