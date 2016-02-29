//
//  DownloadRecovery.swift
//  Tests
//
//  Created by Christopher Prince on 2/26/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import XCTest
@testable import Tests
@testable import SMSyncServer
import SMCoreLib

class DownloadRecovery: BaseClass {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    // Tests based on simulated failure points at various sync server API calls. This simulates, for example, network failure on the API calls.
    func recoveryBasedOnTestContextWorks(testContext:SMTestContext) {
        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Upload Complete")
        let singleUploadExpectation = self.expectationWithDescription("Single Upload Complete")
        let singleDownloadExpectation = self.expectationWithDescription("Single Download or No Download Complete")
        let allDownloadsCompleteExpectation = self.expectationWithDescription("All Downloads Complete")

        self.extraServerResponseTime = 30
        var numberInboundTransfers = 0
        var noDownloads = false
        
        self.waitUntilSyncServerUserSignin() {
            
            let testFile = TestBasics.session.createTestFile("RecoveryBasedOnTestContext" + testContext.rawValue)
            
            SMSyncServer.session.uploadImmutableFile(testFile.url, withFileAttributes: testFile.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile.uuidString)
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(testFile.uuidString, size: testFile.sizeInBytes) {
                    uploadCompleteCallbackExpectation.fulfill()
                    
                    // Unlock only applies to situations where there are no files to download.
                    if testContext == .Unlock {
                        noDownloads = true
                    }
                    else {
                        // Now, forget locally about that uploaded file so we can download it.
                        SMSyncServer.session.resetMetaData(forUUID:testFile.uuid)
                    }
                    
                    SMTest.session.doClientFailureTest(testContext)
                    
                    if testContext == .InboundTransferRecovery {
                        // In order to get the .InboundTransferRecovery failure, we need to make a primary failure, first.
                        SMTest.session.doClientFailureTest(.InboundTransfer)
                    }
                    
                    SMDownloadFiles.session.checkForDownloads()
                }
            }
            
            self.singleRecoveryCallback =  { mode in
                self.numberOfRecoverySteps += 1
            }
            
            self.singleInboundTransferCallback = { numberOperations in
                numberInboundTransfers += 1
            }

            self.singleDownload.append() { (downloadedFile:NSURL, downloadedFileAttr: SMSyncAttributes) in
                XCTAssert(downloadedFileAttr.uuid.UUIDString == testFile.uuidString)
                let filesAreTheSame = SMFiles.compareFiles(file1: testFile.url, file2: downloadedFile)
                XCTAssert(filesAreTheSame)
                singleDownloadExpectation.fulfill()
            }
            
            self.noDownloadsCallbacks.append() {
                singleDownloadExpectation.fulfill()
                allDownloadsCompleteExpectation.fulfill()
            }
            
            self.downloadsCompleteCallbacks.append() {
                // With .CheckOperationStatus server API failure, the "recovery" process consists of just trying to check the operation status again, which doesn't get reflected in the number of recovery steps.
                if testContext != .CheckOperationStatus {
                    XCTAssert(self.numberOfRecoverySteps >= 1)
                    
                    if testContext == .InboundTransferRecovery {
                        // At least two-- because of primary then secondary failure.
                        XCTAssert(self.numberOfRecoverySteps >= 2)
                    }
                }
                
                if !noDownloads {
                    XCTAssert(numberInboundTransfers >= 1)
                }
                allDownloadsCompleteExpectation.fulfill()
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    func testThatRecoveryBasedOnLockContextWorks() {
        self.recoveryBasedOnTestContextWorks(.Lock)
    }
    
    func testThatRecoveryBasedOnUnlockContextWorks() {
        self.recoveryBasedOnTestContextWorks(.Unlock)
    }

    func testThatRecoveryBasedOnGetFileIndexContextWorks() {
        self.recoveryBasedOnTestContextWorks(.GetFileIndex)
    }

    func testThatRecoveryBasedOnInboundTransferContextWorks() {
        self.recoveryBasedOnTestContextWorks(.InboundTransfer)
    }

    func testThatRecoveryBasedOnDownloadFilesContextWorks() {
        self.recoveryBasedOnTestContextWorks(.DownloadFiles)
    }

    func testThatRecoveryBasedOnCheckOperationStatusContextWorks() {
        self.recoveryBasedOnTestContextWorks(.CheckOperationStatus)
    }
    
    func testThatRecoveryBasedOnRemoveOperationIdContextWorks() {
        self.recoveryBasedOnTestContextWorks(.RemoveOperationId)
    }

    func testThatRecoveryBasedOnInboundTransferRecoveryContextWorks() {
        self.recoveryBasedOnTestContextWorks(.InboundTransferRecovery)
    }
    
    // TODO: Download recovery after 0 files (of 1) transferred inbound from cloud storage.
    
    // TODO: Download recovery after 1 files (of 2) transferred inbound from cloud storage.

    // TODO: Download recovery after the inbound transfer and then before 0 files (of 1) downloaded from cloud storage.

    // TODO: Recovery after 1 of 1 inbound transferred and an app crash immediately after that (and before any files downloaded).

    // TODO: Download recovery on app restart. Cause app to crash after the 1st of 2 downloads. Restart the app and ensure that the download recovers/finishes.
    
    // When we get network access back, should treat this like an app launch and see if we need to do recovery. When we get network access back, do the same procedure/method as during app launch. Start a download, cause it to fail because of network loss, then immediately bring the network back online and do the recovery.
    func testThatRecoveryFromNetworkLossWorks() {
        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Upload Complete")
        let singleUploadExpectation = self.expectationWithDescription("Single Upload Complete")
        let singleDownloadExpectation = self.expectationWithDescription("Single Download Complete")
        let allDownloadsCompleteExpectation = self.expectationWithDescription("All Downloads Complete")

        self.extraServerResponseTime = 30
        var shouldDoNetworkFailure = true
        
        self.waitUntilSyncServerUserSignin() {
            
            let testFile = TestBasics.session.createTestFile("NetworkDownloadRecovery1")
            
            SMSyncServer.session.uploadImmutableFile(testFile.url, withFileAttributes: testFile.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile.uuidString)
                singleUploadExpectation.fulfill()
            }
            
            Network.session().connectionStateCallbacks.addTarget!(self, withSelector: "recoveryFromNetworkLossAction")
            
            self.singleRecoveryCallback =  { mode in
                self.numberOfRecoverySteps += 1
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(testFile.uuidString, size: testFile.sizeInBytes) {
                    uploadCompleteCallbackExpectation.fulfill()
                    
                    // Now, forget locally about that uploaded file so we can download it.
                    SMSyncServer.session.resetMetaData(forUUID:testFile.uuid)
                    
                    SMDownloadFiles.session.checkForDownloads()
                }
            }
            
            self.singleInboundTransferCallback = { numberOperations in
                Network.session().debugNetworkOff = shouldDoNetworkFailure
                shouldDoNetworkFailure = false
            }
            
            self.singleDownload.append() { (downloadedFile:NSURL, downloadedFileAttr: SMSyncAttributes) in
                XCTAssert(downloadedFileAttr.uuid.UUIDString == testFile.uuidString)
                let filesAreTheSame = SMFiles.compareFiles(file1: testFile.url, file2: downloadedFile)
                XCTAssert(filesAreTheSame)
                singleDownloadExpectation.fulfill()
            }
            
            self.downloadsCompleteCallbacks.append() {
                XCTAssert(self.numberOfRecoverySteps >= 1)
                allDownloadsCompleteExpectation.fulfill()
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

}
