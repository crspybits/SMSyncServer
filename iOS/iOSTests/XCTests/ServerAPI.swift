//
//  ServerAPI.swift
//  NetDb
//
//  Created by Christopher Prince on 1/14/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import XCTest
// The @testable notation lets us access "internal" classes within our project.
@testable import SMSyncServer
import SMCoreLib
@testable import Tests

class ServerAPI: BaseClass {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testThatFileIndexDoesNotFail() {
        let getFileIndex = self.expectationWithDescription("FileIndex Complete")

        self.waitUntilSyncServerUserSignin() {
            
            SMServerAPI.session.getFileIndex() { (fileIndex, fileIndexVersion, apiResult) in
                XCTAssert(apiResult.error == nil)
                XCTAssert(fileIndexVersion != nil)
                
                getFileIndex.fulfill()
            }
        }
        
        self.waitForExpectations()
    }
    
    func testThatFinishUploadsDoesNotFail() {
        let finishUploads = self.expectationWithDescription("FinishUploads Complete")
        
        self.waitUntilSyncServerUserSignin() {

            SMServerAPI.session.getFileIndex() { (fileIndex, fileIndexVersion, apiResult) in
                XCTAssert(apiResult.error == nil)
                XCTAssert(fileIndexVersion != nil)
                
                SMServerAPI.session.finishUploads(fileIndexVersion: fileIndexVersion!) { apiResult in
                    XCTAssert(apiResult.error == nil)

                    finishUploads.fulfill()
                }
            }
        }
        
        self.waitForExpectations()
    }
    
    func singleFileUploadUsingServerAPI(giveExpectedFileIndexVersion giveExpectedFileIndexVersion:Bool, fileName:String) {
        let uploadComplete = self.expectationWithDescription("Upload Complete")
        
        self.waitUntilSyncServerUserSignin() {
            let testFile = TestBasics.session.createTestFile(fileName)
            let serverFile = SMServerFile(uuid: testFile.uuid, remoteFileName: testFile.remoteFile, mimeType: testFile.mimeType, appMetaData: nil, version: 0)
            serverFile.localURL = testFile.url
            
            SMServerAPI.session.getFileIndex() { (fileIndex, fileIndexVersion, apiResult) in
                XCTAssert(apiResult.error == nil)
                XCTAssert(fileIndexVersion != nil)
                
                SMServerAPI.session.uploadFile(serverFile) { apiResult in
                    XCTAssert(apiResult.error == nil)
                    
                    var fileIndexVersionToSend = fileIndexVersion!
                    if !giveExpectedFileIndexVersion {
                        fileIndexVersionToSend = -1
                    }
                    
                    SMServerAPI.session.finishUploads(fileIndexVersion: fileIndexVersionToSend) { apiResult in
                    
                        if giveExpectedFileIndexVersion {
                            XCTAssert(apiResult.error == nil)

                            TestBasics.session.failure = {
                                XCTFail("Failed on testThatSingleFileUploadUsingServerAPIWorks")
                            }
                            
                            TestBasics.session.checkFileSize(testFile.uuidString, size: testFile.sizeInBytes) {
                                uploadComplete.fulfill()
                            }
                        }
                        else {
                            XCTAssert(apiResult.error != nil)
                            uploadComplete.fulfill()
                        }
                    }
                }
            }
        }
        
        self.waitForExpectations()
    }

    func testThatSingleFileUploadUsingServerAPIWorks() {
        let fileName = "SingleFileUploadUsingServerAPI"
        singleFileUploadUsingServerAPI(giveExpectedFileIndexVersion:true, fileName:fileName)
    }
    
    func testThatSingleFileUploadUsingServerAPIUsingIncorrectVersionFails() {
        let fileName = "SingleFileUploadUsingServerAPIUsingIncorrectVersion"
        singleFileUploadUsingServerAPI(giveExpectedFileIndexVersion:false, fileName:fileName)
    }
    
    // TODO: Do the same two tests-- but with upload-deletion.
    
    // Calling the deleteFiles API interface twice with the same file(s) should work, and not cause an error the second time.
    func testThatDoubleDeletionOfASingleFileWorks() {
        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Commit Complete")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")
        let idleExpectation = self.expectationWithDescription("Idle")
        let deletionExpectation = self.expectationWithDescription("Delete")
        
        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            let testFile = TestBasics.session.createTestFile("DoubleDeletionOfASingleFile")
            
            try! SMSyncServer.session.uploadImmutableFile(testFile.url, withFileAttributes: testFile.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile.uuidString)
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                uploadCompleteCallbackExpectation.fulfill()
            }
            
            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation.fulfill()
                
                let serverFile = SMServerFile(uuid: testFile.uuid, remoteFileName: testFile.remoteFile, mimeType: testFile.mimeType, appMetaData: nil, version: 0)
            
                SMServerAPI.session.deleteFiles([serverFile]) { apiResult in
                    XCTAssert(apiResult.error == nil)

                    SMServerAPI.session.deleteFiles([serverFile]) { apiResult in
                        XCTAssert(apiResult.error == nil)

                        SMServerAPI.session.cleanup(){ cleanupResult in
                            XCTAssert(cleanupResult.error == nil)
                            
                            deletionExpectation.fulfill()
                        }
                    }
                }
            }
            
            try! SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    func testThatDoubleUploadOfASingleFileWorks() {
        let uploadExpectation = self.expectationWithDescription("Upload")

        self.waitUntilSyncServerUserSignin() {
            let testFile = TestBasics.session.createTestFile("DoubleUploadOfASingleFile")
            let serverFile = SMServerFile(uuid: testFile.uuid, remoteFileName: testFile.remoteFile, mimeType: testFile.mimeType, appMetaData: nil, version: 0)
            serverFile.localURL = testFile.url
        
            SMServerAPI.session.uploadFile(serverFile) { apiResult in
                XCTAssert(apiResult.error == nil)

                SMServerAPI.session.uploadFile(serverFile) { apiResult in
                    XCTAssert(apiResult.error == nil)

                    SMServerAPI.session.cleanup(){ cleanupResult in
                        XCTAssert(cleanupResult.error == nil)
                        
                        uploadExpectation.fulfill()
                    }
                }
            }
        }
        
        self.waitForExpectations()
    }
    
    func testThatSetupInboundTransferWithNoLockFails() {
        let afterStartExpectation = self.expectationWithDescription("After Start")
        
        let noServerFiles = [SMServerFile]()
        
        self.waitUntilSyncServerUserSignin() {
            SMServerAPI.session.setupInboundTransfer(noServerFiles) {  apiResult  in
            
                XCTAssert(apiResult.error != nil)
                XCTAssert(apiResult.returnCode == SMServerConstants.rcServerAPIError)
                afterStartExpectation.fulfill()
            }
        }
        
        self.waitForExpectations()
    }
    
    func testThatSetupInboundTransferWith0FilesFails() {
        let afterStartExpectation = self.expectationWithDescription("After Cleanup")
        
        let noServerFiles = [SMServerFile]()
        
        self.waitUntilSyncServerUserSignin() {
                
            SMServerAPI.session.setupInboundTransfer(noServerFiles) { (sitResult)  in
            
                XCTAssert(sitResult.error != nil)
                XCTAssert(sitResult.returnCode == SMServerConstants.rcServerAPIError)
                
                // Get rid of the lock.
                SMServerAPI.session.cleanup(){ cleanupResult in
                    XCTAssert(cleanupResult.error == nil)
                    
                    afterStartExpectation.fulfill()
                }
            }
        }
        
        self.waitForExpectations()
    }
    
    /*
    func DISABLED_testThatStartInboundTransferWith1FileWorks() {
        let afterStartExpectation = self.expectationWithDescription("After Cleanup")
        
        var serverFiles = [SMServerFile]()
        let uuid = NSUUID(UUIDString: "A8111BC9-D01B-4D77-A1A2-4447F63015DC")
        let file = SMServerFile(uuid: uuid!)
        serverFiles.append(file)
        
        self.waitUntilSyncServerUserSignin() {
            SMServerAPI.session.lock() { lockResult in
                XCTAssert(lockResult.error == nil)
                
                SMServerAPI.session.startInboundTransfer(serverFiles) { (serverOperationId, sitResult)  in
                
                    XCTAssert(sitResult.error == nil)
                    XCTAssert(serverOperationId != nil)
                    XCTAssert(sitResult.returnCode == SMServerConstants.rcOK)
                    
                    afterStartExpectation.fulfill()
                }
            }
        }
        
        self.waitForExpectations()
    }
    */
 
    // Test downloading of a random UUID from the server. Should fail because that file is not on the server/ready to download.
    func testThatDownloadOfRandomUUIDFails() {
        let downloadExpectation = self.expectationWithDescription("Handler called")
        //let noDownloads = self.expectationWithDescription("Handler called")

        self.waitUntilSyncServerUserSignin() {

            let downloadFileURL = SMRelativeLocalURL(withRelativePath: "download1A", toBaseURLType: .DocumentsDirectory)
            
            let serverFile = SMServerFile(uuid: NSUUID())
            serverFile.localURL = downloadFileURL
            
            /*
            self.noDownloadsCallbacks.append() {
                noDownloads.fulfill()
            }
            */
            
            SMServerAPI.session.downloadFile(serverFile) { apiResult in
                XCTAssert(apiResult.error != nil)
                downloadExpectation.fulfill()
            }
        }
        
        self.waitForExpectations()
    }
    
    // Start a download directly, using the SMServerAPI method, and have a lock. This should fail-- because we always download files in an unlocked state.
    func testThatDownloadWithLockFails() {
        let expectation = self.expectationWithDescription("Handler called")

        self.waitUntilSyncServerUserSignin() {
            let downloadFileURL = SMRelativeLocalURL(withRelativePath: "download1B", toBaseURLType: .DocumentsDirectory)
            
            let serverFile = SMServerFile(uuid: NSUUID())
            serverFile.localURL = downloadFileURL
        
            SMServerAPI.session.downloadFile(serverFile) { downloadResult in
                // Should get an error here.
                XCTAssert(downloadResult.error != nil)
                expectation.fulfill()

            }
        }
        
        self.waitForExpectations()
    }
}
