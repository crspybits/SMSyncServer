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

class ServerAPI: BaseClass {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testThatStartInboundTransferWithNoLockFails() {
        let afterStartExpectation = self.expectationWithDescription("After Start")
        
        let noServerFiles = [SMServerFile]()
        
        self.waitUntilSyncServerUserSignin() {
            SMServerAPI.session.startInboundTransfer(noServerFiles) { (serverOperationId, apiResult)  in
            
                XCTAssert(serverOperationId == nil)
                XCTAssert(apiResult.error != nil)
                XCTAssert(apiResult.returnCode == SMServerConstants.rcServerAPIError)
                afterStartExpectation.fulfill()
            }
        }
        
        self.waitForExpectations()
    }
    
    func testThatStartInboundTransferWith0FilesFails() {
        let afterStartExpectation = self.expectationWithDescription("After Cleanup")
        
        let noServerFiles = [SMServerFile]()
        
        self.waitUntilSyncServerUserSignin() {
            SMServerAPI.session.lock() { lockResult in
                XCTAssert(lockResult.error == nil)
                
                SMServerAPI.session.startInboundTransfer(noServerFiles) { (serverOperationId, sitResult)  in
                
                    XCTAssert(sitResult.error != nil)
                    XCTAssert(serverOperationId == nil)
                    XCTAssert(sitResult.returnCode == SMServerConstants.rcServerAPIError)
                    
                    // Get rid of the lock.
                    SMServerAPI.session.cleanup(){ cleanupResult in
                        XCTAssert(cleanupResult.error == nil)
                        
                        afterStartExpectation.fulfill()
                    }
                }
            }
        }
        
        self.waitForExpectations()
    }
    
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

            SMServerAPI.session.lock() { lockResult in
                XCTAssert(lockResult.error == nil)

                let downloadFileURL = SMRelativeLocalURL(withRelativePath: "download1B", toBaseURLType: .DocumentsDirectory)
                
                let serverFile = SMServerFile(uuid: NSUUID())
                serverFile.localURL = downloadFileURL
            
                SMServerAPI.session.downloadFile(serverFile) { downloadResult in
                    // Should get an error here.
                    XCTAssert(downloadResult.error != nil)
                    
                    SMServerAPI.session.unlock() { unlockResult in
                        XCTAssert(unlockResult.error == nil)
                        expectation.fulfill()
                    }
                }
            }
        }
        
        self.waitForExpectations()
    }
}
