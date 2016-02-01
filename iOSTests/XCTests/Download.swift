//
//  Download.swift
//  NetDb
//
//  Created by Christopher Prince on 1/14/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import XCTest
@testable import SMSyncServer
@testable import Tests
import SMCoreLib

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
        let fileName = "DownloadOfOneFile"
        let (originalFile, fileSizeBytes) = self.createFile(withName: fileName)
        let fileAttributes = SMSyncAttributes(withUUID: NSUUID(UUIDString: originalFile.uuid!)!, mimeType: "text/plain", andRemoteFileName: fileName)
        
        self.downloadOneFile(originalFileAttr:fileAttributes, originalFileURL: originalFile.url(), originalFileSizeBytes: fileSizeBytes)
    }
    
    func downloadOneFile(originalFileAttr originalFileAttr:SMSyncAttributes, originalFileURL: NSURL, originalFileSizeBytes:Int) {

        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Commit Complete")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")
        let singleDownloadExpectation = self.expectationWithDescription("Single Download")
        let allDownloadsCompleteExpectation = self.expectationWithDescription("All Downloads Complete")
        var numberDownloads = 0
        
        self.extraServerResponseTime = 60
        
        self.waitUntilSyncServerUserSignin() {
            SMSyncServer.session.uploadImmutableFile(originalFileURL, withFileAttributes: originalFileAttr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == originalFileAttr.uuid.UUIDString)
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                self.checkFileSize(originalFileAttr.uuid.UUIDString, size: originalFileSizeBytes) {
                    uploadCompleteCallbackExpectation.fulfill()
                    
                    // Now, forget locally about that uploaded file so we can download it.
                    SMSyncServer.session.resetMetaData(forUUIDString:originalFileAttr.uuid.UUIDString)
                    
                    SMDownloadFiles.session.checkForDownloads()
                }
            }
            
            self.downloadCallbacks.append() { (downloadedFile:NSURL, downloadedFileAttr: SMSyncAttributes) in
                XCTAssert(downloadedFileAttr.uuid.UUIDString == originalFileAttr.uuid.UUIDString)
                let filesAreTheSame = SMFiles.compareFiles(file1: originalFileURL, file2: downloadedFile)
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
    
    // Try a download of a larger file, such as my Kitty.png file.
    func testThatDownloadOfALargerFileWorks() {
        let file = AppFile.newObjectAndMakeUUID(true)
        file.fileName =  "Kitty.png"
        CoreData.sessionNamed(CoreDataTests.name).saveContext()
        
        let url = NSBundle.mainBundle().URLForResource("Kitty", withExtension: "png")
        let fileAttributes = SMSyncAttributes(withUUID: NSUUID(UUIDString: file.uuid!)!, mimeType: "image/png", andRemoteFileName: file.fileName!)
        let sizeInBytesExpectedOnServer = 917630

        self.downloadOneFile(originalFileAttr:fileAttributes, originalFileURL: url!, originalFileSizeBytes: sizeInBytesExpectedOnServer)
    }
    
    // Try to download a file, through the SMServerAPI, that is on the server, but isn't in the PSInboundFile's. i.e., that hasn't been transfered from the cloud to the server.
    func testThatDownloadOfUntransferredServerFileDoesntWork() {
        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Commit Complete")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")
        let unlockExpectation = self.expectationWithDescription("Unlock Complete")

        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            
            let fileName = "DownloadOfUntransferredServerFile"
            let (file, fileSizeBytes) = self.createFile(withName: fileName)
            let fileUUID = NSUUID(UUIDString: file.uuid!)!
            let fileAttributes = SMSyncAttributes(withUUID: fileUUID, mimeType: "text/plain", andRemoteFileName: fileName)
            
            SMSyncServer.session.uploadImmutableFile(file.url(), withFileAttributes: fileAttributes)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file.uuid!)
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                self.checkFileSize(file.uuid!, size: fileSizeBytes) {
                    uploadCompleteCallbackExpectation.fulfill()

                    SMServerAPI.session.lock() { error in
                        XCTAssert(error == nil)

                        let downloadFileURL = FileStorage.urlOfItem("download1")
                        let serverFile = SMServerFile(uuid: fileUUID)
                        serverFile.localURL = downloadFileURL
                    
                        SMServerAPI.session.downloadFile(serverFile) { error in
                            // Should get an error here: Because we're trying to download a file that's not in the PSInboundFiles and marked as received. I.e., it hasn't been transferred from the server.
                            XCTAssert(error != nil)
                            
                            SMServerAPI.session.unlock() { error in
                                XCTAssert(error == nil)
                                unlockExpectation.fulfill()
                            }
                        }
                    }
                }
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    // TODO: Download two server files which don't yet exist on the app/client.
    
    // TODO: Start one download, and immediately after starting that download, commit an upload. Expect that download should finish, and then upload should start, serially, after the download.
    
    // TODO: Start download that will download two files, and immediately after starting that download, commit an upload. Expect that both downloads should finish, and then upload should start, serially, after the downloads.

    // TODO: Server files which are updated versions of those on app/client.
    
    // TODO: Each of the conflict cases: update conflict, and the two deletion conflicts.
}
