//
//  Download.swift
//  NetDb
//
//  Created by Christopher Prince on 1/14/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import XCTest
@testable import SMSyncServer

class Download: BaseClass {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    // TODO: Server files which already exist on the app/client and have the same version, i.e., there are no files to download.
    
    // Download a single server file which doesn't yet exist on the app/client.
    func testThatDownloadOfOneFileWorks() {
        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Commit Complete")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")
        let singleDownloadExpectation = self.expectationWithDescription("Single Download")
        
        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            
            let fileName = "DownloadOfOneFile"
            let (file, fileSizeBytes) = self.createFile(withName: fileName)
            let fileAttributes = SMSyncAttributes(withUUID: NSUUID(UUIDString: file.uuid!)!, mimeType: "text/plain", andRemoteFileName: fileName)
            
            SMSyncServer.session.uploadImmutableFile(file.url(), withFileAttributes: fileAttributes)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file.uuid!)
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                self.checkFileSize(file.uuid!, size: fileSizeBytes) {
                    uploadCompleteCallbackExpectation.fulfill()
                    
                    // Now, forget locally about that uploaded file so we can download it.
                    SMSyncServer.session.resetMetaData()
                    
                    SMDownloadFiles.session.checkForDownloads()
                }
            }
            
            self.downloadCallbacks.append() {
                singleDownloadExpectation.fulfill()
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    // TODO: Download two server files which don't yet exist on the app/client.

    // TODO: Start one download, and immediately after starting that download, commit an upload.

    // TODO: Server files which are updated versions of those on app/client.
    
    /* TODO:
        Each of the conflict cases: update conflict, and the two deletion conflicts.
    */
}
