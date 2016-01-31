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
    
    // Server files which already exist on the app/client and have the same version, i.e., there are no files to download.
    func testFilesInSyncResultsInNoDownloadsWorks() {
        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Commit Complete")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")
        let noDownloadExpectation = self.expectationWithDescription("No Downloads")
        
        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            
            let fileName = "FilesInSyncResultsInNoDownloads"
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
                    
                    // Should detect no files available/needed for download.
                    SMDownloadFiles.session.checkForDownloads()
                }
            }
            
            self.noDownloadsCallbacks.append() {
                noDownloadExpectation.fulfill()
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    // Download a single server file which doesn't yet exist on the app/client.
    func testThatDownloadOfOneFileWorks() {
        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Commit Complete")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")
        let singleDownloadExpectation = self.expectationWithDescription("Single Download")
        let allDownloadsCompleteExpectation = self.expectationWithDescription("All Downloads Complete")
        var numberDownloads = 0
        
        self.extraServerResponseTime = 60
        
        self.waitUntilSyncServerUserSignin() {
            
            let fileName = "DownloadOfOneFile"
            let (originalFile, fileSizeBytes) = self.createFile(withName: fileName)
            let fileAttributes = SMSyncAttributes(withUUID: NSUUID(UUIDString: originalFile.uuid!)!, mimeType: "text/plain", andRemoteFileName: fileName)
            
            SMSyncServer.session.uploadImmutableFile(originalFile.url(), withFileAttributes: fileAttributes)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == originalFile.uuid!)
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                self.checkFileSize(originalFile.uuid!, size: fileSizeBytes) {
                    uploadCompleteCallbackExpectation.fulfill()
                    
                    // Now, forget locally about that uploaded file so we can download it.
                    SMSyncServer.session.resetMetaData()
                    
                    SMDownloadFiles.session.checkForDownloads()
                }
            }
            
            self.downloadCallbacks.append() { (downloadedFile:NSURL, downloadedFileAttr: SMSyncAttributes) in
                XCTAssert(downloadedFileAttr.uuid.UUIDString == originalFile.uuid!)
                let filesAreTheSame = SMFiles.compareFiles(file1: originalFile.url(), file2: downloadedFile)
                XCTAssert(filesAreTheSame)
                numberDownloads++
                singleDownloadExpectation.fulfill()
            }
            
            self.allDownloadsCompleteCallbacks.append() {
                XCTAssert(numberDownloads == 1)
                allDownloadsCompleteExpectation.fulfill()
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    // TODO: Try a download of a larger file, such as my Kitty.png file.
    
    // TODO: Try to download a file, through the SMServerAPI, that is on the server, but isn't in the PSInboundFile's.
    
    // TODO: Download two server files which don't yet exist on the app/client.
    
    // TODO: Start one download, and immediately after starting that download, commit an upload. Expect that download should finish, and then upload should start, serially, after the download.
    
    // TODO: Start download that will download two files, and immediately after starting that download, commit an upload. Expect that both downloads should finish, and then upload should start, serially, after the downloads.

    // TODO: Server files which are updated versions of those on app/client.
    
    // TODO: Each of the conflict cases: update conflict, and the two deletion conflicts.
}
