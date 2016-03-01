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
    
    private static var crash1 = SMPersistItemBool(name: "SMDownloadFiles.crash1", initialBoolValue: true, persistType: .UserDefaults)
    private static var crash2 = SMPersistItemBool(name: "SMDownloadFiles.crash2", initialBoolValue: true, persistType: .UserDefaults)

    private static var crashUUIDString1 = SMPersistItemString(name: "SMDownloadFiles.crash1UUIDString1", initialStringValue: "", persistType: .UserDefaults)
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    // MARK: Tests based on simulated client side failure points at various sync server API calls. This simulates, for example, network failure on the API calls.
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
    
    // Not using an integer directly here because an integer would imply generality.
    enum NumbrerOfFilesToDownload {
        case One
        case Two
    }
    
    // MARK: Download recovery after server failure when transferring/downloading 1 file.
    func serverDownloadFailureRecovery(serverTestCase:Int, numberOfFilesToDownload:NumbrerOfFilesToDownload = .One) {
        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Upload Complete")
        let singleUploadExpectation = self.expectationWithDescription("Single Upload Complete")
        var singleUploadExpectation2:XCTestExpectation?
        let singleDownloadExpectation = self.expectationWithDescription("Single Download Complete")
        var singleDownloadExpectation2:XCTestExpectation?
        let allDownloadsCompleteExpectation = self.expectationWithDescription("All Downloads Complete")
        
        if numberOfFilesToDownload == .Two {
            singleUploadExpectation2 = self.expectationWithDescription("Single Upload2 Complete")
            singleDownloadExpectation2 = self.expectationWithDescription("Single Download2 Complete")
        }
        
        self.extraServerResponseTime = 30
        var numberInboundTransfers = 0
        
        self.waitUntilSyncServerUserSignin() {
            
            let testFile = TestBasics.session.createTestFile("ServerDownloadFailureRecovery" + String(serverTestCase) + ".1")
            SMSyncServer.session.uploadImmutableFile(testFile.url, withFileAttributes: testFile.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile.uuidString)
                singleUploadExpectation.fulfill()
            }
            
            var testFile2:TestFile?
            if numberOfFilesToDownload == .Two {
                testFile2 = TestBasics.session.createTestFile("ServerDownloadFailureRecovery" + String(serverTestCase) + ".2")
                SMSyncServer.session.uploadImmutableFile(testFile2!.url, withFileAttributes: testFile2!.attr)
                
                self.singleUploadCallbacks.append() { uuid in
                    XCTAssert(uuid.UUIDString == testFile2!.uuidString)
                    singleUploadExpectation2!.fulfill()
                }
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                if numberOfFilesToDownload == .One {
                    XCTAssert(numberUploads == 1)
                }
                else {
                    XCTAssert(numberUploads == 2)
                }
                
                func finish() {
                    uploadCompleteCallbackExpectation.fulfill()
                    SMTest.session.serverDebugTest =  serverTestCase
                    SMDownloadFiles.session.checkForDownloads()
                }
                
                TestBasics.session.checkFileSize(testFile.uuidString, size: testFile.sizeInBytes) {
                    
                    // Forget locally about that uploaded file so we can download it.
                    SMSyncServer.session.resetMetaData(forUUID:testFile.uuid)
                    
                    if numberOfFilesToDownload == .One {
                        finish()
                    }
                    else {
                        TestBasics.session.checkFileSize(testFile2!.uuidString, size: testFile2!.sizeInBytes) {
                            SMSyncServer.session.resetMetaData(forUUID:testFile2!.uuid)
                            finish()
                        }
                    }
                }
            }
            
            self.singleRecoveryCallback =  { mode in
                // So we don't get the error test cases on the server again
                SMTest.session.serverDebugTest = nil
                
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
            
            if numberOfFilesToDownload == .Two {
                self.singleDownload.append() { (downloadedFile:NSURL, downloadedFileAttr: SMSyncAttributes) in
                    XCTAssert(downloadedFileAttr.uuid.UUIDString == testFile2!.uuidString)
                    let filesAreTheSame = SMFiles.compareFiles(file1: testFile2!.url, file2: downloadedFile)
                    XCTAssert(filesAreTheSame)
                    singleDownloadExpectation2!.fulfill()
                }
            }
            
            self.downloadsCompleteCallbacks.append() {
                XCTAssert(self.numberOfRecoverySteps >= 1)
                XCTAssert(numberInboundTransfers >= 1)
                allDownloadsCompleteExpectation.fulfill()
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    // MARK: One file recovery cases

    func testThatServerDownloadSetupFailureRecovery() {
        self.serverDownloadFailureRecovery(SMServerConstants.dbTcSetup)
    }
    
    func testThatServerDownloadInProgressFailureRecovery() {
        self.serverDownloadFailureRecovery(SMServerConstants.dbTcInProgress)
    }
    
    func testThatServerDownloadTransferFilesFailureRecovery() {
        self.serverDownloadFailureRecovery(SMServerConstants.dbTcTransferFiles)
    }

    func testThatServerDownloadRemoveLockAfterCloudStorageTransferFailureRecovery() {
        self.serverDownloadFailureRecovery(SMServerConstants.dbTcRemoveLockAfterCloudStorageTransfer)
    }
    
    func testThatServerDownloadGetLockForDownloadFailureRecovery() {
        self.serverDownloadFailureRecovery(SMServerConstants.dbTcGetLockForDownload)
    }
    
    func testThatServerDownloadGetDownloadFileInfoFailureRecovery() {
        self.serverDownloadFailureRecovery(SMServerConstants.dbTcGetDownloadFileInfo)
    }

    // MARK: Two file recovery cases
    
    func testThatServerDownloadSetupFailure2FileRecovery() {
        self.serverDownloadFailureRecovery(SMServerConstants.dbTcSetup, numberOfFilesToDownload: .Two)
    }
    
    func testThatServerDownloadInProgressFailure2FileRecovery() {
        self.serverDownloadFailureRecovery(SMServerConstants.dbTcInProgress, numberOfFilesToDownload: .Two)
    }
    
    func testThatServerDownloadTransferFilesFailure2FileRecovery() {
        self.serverDownloadFailureRecovery(SMServerConstants.dbTcTransferFiles, numberOfFilesToDownload: .Two)
    }

    func testThatServerDownloadRemoveLockAfterCloudStorageTransferFailure2FileRecovery() {
        self.serverDownloadFailureRecovery(SMServerConstants.dbTcRemoveLockAfterCloudStorageTransfer, numberOfFilesToDownload: .Two)
    }
    
    func testThatServerDownloadGetLockForDownloadFailure2FileRecovery() {
        self.serverDownloadFailureRecovery(SMServerConstants.dbTcGetLockForDownload, numberOfFilesToDownload: .Two)
    }
    
    func testThatServerDownloadGetDownloadFileInfoFailure2FileRecovery() {
        self.serverDownloadFailureRecovery(SMServerConstants.dbTcGetDownloadFileInfo, numberOfFilesToDownload: .Two)
    }
    
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
    
    // Recovery after crash attempting to download 1 file.
    func testThatCrash1RecoveryAfterSingleFileWorks() {
        var uploadCompleteCallbackExpectation:XCTestExpectation?
        var singleUploadExpectation:XCTestExpectation?
        var singleDownloadExpectation:XCTestExpectation?
        var allDownloadsCompleteExpectation:XCTestExpectation?
        
        if DownloadRecovery.crash1.boolValue {
            uploadCompleteCallbackExpectation = self.expectationWithDescription("Upload Complete")
            singleUploadExpectation = self.expectationWithDescription("Single Upload Complete")
        }
        else {
            singleDownloadExpectation = self.expectationWithDescription("Single Download or No Download Complete")
            allDownloadsCompleteExpectation = self.expectationWithDescription("All Downloads Complete")
        }
        
        self.extraServerResponseTime = 30
        var numberInboundTransfers = 0
        
        var testFile:TestFile?
        let testFileName = "RecoveryAfterCrash1OnSingleFile"

        if DownloadRecovery.crash1.boolValue {
            DownloadRecovery.crash1.boolValue = false
                
            self.waitUntilSyncServerUserSignin() {

                testFile = TestBasics.session.createTestFile(testFileName)
                DownloadRecovery.crashUUIDString1.stringValue = testFile!.uuidString
                
                SMSyncServer.session.uploadImmutableFile(testFile!.url, withFileAttributes: testFile!.attr)
                
                self.singleUploadCallbacks.append() { uuid in
                    XCTAssert(uuid.UUIDString == testFile!.uuidString)
                    singleUploadExpectation!.fulfill()
                }
                
                self.commitCompleteCallbacks.append() { numberUploads in
                    XCTAssert(numberUploads == 1)
                    TestBasics.session.checkFileSize(testFile!.uuidString, size: testFile!.sizeInBytes) {
                        
                        // Now, forget locally about that uploaded file so we can download it.
                        SMSyncServer.session.resetMetaData(forUUID:testFile!.uuid)
                        
                        SMDownloadFiles.session.checkForDownloads()
                        
                        SMTest.session.crash()
                        
                        // Will actually never get to here...
                        uploadCompleteCallbackExpectation!.fulfill()
                    }
                }
                
                SMSyncServer.session.commit()
            }
        }
        else {
            // Restart after crash.
            
            testFile = TestBasics.session.recreateTestFile(fromUUID: DownloadRecovery.crashUUIDString1.stringValue)
            
            self.singleRecoveryCallback =  { mode in
                self.numberOfRecoverySteps += 1
            }
            
            self.singleInboundTransferCallback = { numberOperations in
                numberInboundTransfers += 1
            }

            self.singleDownload.append() { (downloadedFile:NSURL, downloadedFileAttr: SMSyncAttributes) in
                XCTAssert(downloadedFileAttr.uuid.UUIDString == testFile!.uuidString)
                let filesAreTheSame = SMFiles.compareFiles(file1: testFile!.url, file2: downloadedFile)
                XCTAssert(filesAreTheSame)
                singleDownloadExpectation!.fulfill()
            }
            
            self.downloadsCompleteCallbacks.append() {
                XCTAssert(self.numberOfRecoverySteps >= 1)
                XCTAssert(numberInboundTransfers >= 1)
                allDownloadsCompleteExpectation!.fulfill()
            }
        }
        
        self.waitForExpectations()
    }
    
    // Same crash, downloading 1 file, but later into sequence.
    func testThatCrash2RecoveryAfterSingleFileWorks() {
        var uploadCompleteCallbackExpectation:XCTestExpectation?
        var singleUploadExpectation:XCTestExpectation?
        var singleDownloadExpectation:XCTestExpectation?
        var allDownloadsCompleteExpectation:XCTestExpectation?
        
        if DownloadRecovery.crash2.boolValue {
            uploadCompleteCallbackExpectation = self.expectationWithDescription("Upload Complete")
            singleUploadExpectation = self.expectationWithDescription("Single Upload Complete")
        }
        
        // These two expectations will *not* be fulfilled the first time through. We'll get the crash instead. They will be fulfilled on the restart after the crash.
        singleDownloadExpectation = self.expectationWithDescription("Single Download or No Download Complete")
        allDownloadsCompleteExpectation = self.expectationWithDescription("All Downloads Complete")
        
        self.extraServerResponseTime = 30
        
        var testFile:TestFile?
        let testFileName = "RecoveryAfterCrash2OnSingleFile"

        if DownloadRecovery.crash2.boolValue {
            DownloadRecovery.crash2.boolValue = false
                
            self.waitUntilSyncServerUserSignin() {

                testFile = TestBasics.session.createTestFile(testFileName)
                DownloadRecovery.crashUUIDString1.stringValue = testFile!.uuidString
                
                SMSyncServer.session.uploadImmutableFile(testFile!.url, withFileAttributes: testFile!.attr)
                
                self.singleUploadCallbacks.append() { uuid in
                    XCTAssert(uuid.UUIDString == testFile!.uuidString)
                    singleUploadExpectation!.fulfill()
                }
                
                self.commitCompleteCallbacks.append() { numberUploads in
                    XCTAssert(numberUploads == 1)
                    TestBasics.session.checkFileSize(testFile!.uuidString, size: testFile!.sizeInBytes) {
                        uploadCompleteCallbackExpectation!.fulfill()
                        
                        // Now, forget locally about that uploaded file so we can download it.
                        SMSyncServer.session.resetMetaData(forUUID:testFile!.uuid)
                        
                        SMDownloadFiles.session.checkForDownloads()
                    }
                }
                
                self.singleInboundTransferCallback = { numberOperations in
                    SMTest.session.crash()
                }
                
                SMSyncServer.session.commit()
            }
        }
        else {
            // Restart after crash.
            
            testFile = TestBasics.session.recreateTestFile(fromUUID: DownloadRecovery.crashUUIDString1.stringValue)
            
            self.singleRecoveryCallback =  { mode in
                self.numberOfRecoverySteps += 1
            }

            self.singleDownload.append() { (downloadedFile:NSURL, downloadedFileAttr: SMSyncAttributes) in
                XCTAssert(downloadedFileAttr.uuid.UUIDString == testFile!.uuidString)
                let filesAreTheSame = SMFiles.compareFiles(file1: testFile!.url, file2: downloadedFile)
                XCTAssert(filesAreTheSame)
                singleDownloadExpectation!.fulfill()
            }
            
            self.downloadsCompleteCallbacks.append() {
                XCTAssert(self.numberOfRecoverySteps >= 1)
                allDownloadsCompleteExpectation!.fulfill()
            }
        }
        
        self.waitForExpectations()
    }
    
    // TODO: Download recovery on app restart. Cause app to crash after the 1st of 2 inbound transfers. Restart the app and ensure that the download recovers/finishes.

    // TODO: Download recovery on app restart. Cause app to crash after the 1st of 2 downloads. Restart the app and ensure that the download recovers/finishes.
}
