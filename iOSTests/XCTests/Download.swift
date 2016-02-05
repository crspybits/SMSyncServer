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
    
    // Download two server files which don't yet exist on the app/client.
    func testThatDownloadOfTwoFilesWorks() {
        let fileName1 = "DownloadOfTwoFilesA"
        let (originalFile1, fileSizeBytes1) = self.createFile(withName: fileName1)
        let file1UUID = NSUUID(UUIDString: originalFile1.uuid!)!
        let fileAttributes1 = SMSyncAttributes(withUUID: file1UUID, mimeType: "text/plain", andRemoteFileName: fileName1)
        
        let fileName2 = "DownloadOfTwoFilesB"
        let (originalFile2, fileSizeBytes2) = self.createFile(withName: fileName2)
        let file2UUID = NSUUID(UUIDString: originalFile2.uuid!)!
        let fileAttributes2 = SMSyncAttributes(withUUID: file2UUID, mimeType: "text/plain", andRemoteFileName: fileName2)

        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Commit Complete")
        let singleUploadExpectation1 = self.expectationWithDescription("Upload1 Complete")
        let singleUploadExpectation2 = self.expectationWithDescription("Upload2 Complete")

        let singleDownloadExpectation1 = self.expectationWithDescription("Single1 Download")
        let singleDownloadExpectation2 = self.expectationWithDescription("Single2 Download")

        let allDownloadsCompleteExpectation = self.expectationWithDescription("All Downloads Complete")
        var numberDownloads = 0
        
        self.extraServerResponseTime = 60
        
        self.waitUntilSyncServerUserSignin() {
            SMSyncServer.session.uploadImmutableFile(originalFile1.url(), withFileAttributes: fileAttributes1)
            SMSyncServer.session.uploadImmutableFile(originalFile2.url(), withFileAttributes: fileAttributes2)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == fileAttributes1.uuid.UUIDString)
                singleUploadExpectation1.fulfill()
            }

            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == fileAttributes2.uuid.UUIDString)
                singleUploadExpectation2.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 2)
                self.checkFileSize(fileAttributes1.uuid.UUIDString, size: fileSizeBytes1) {
                    self.checkFileSize(fileAttributes2.uuid.UUIDString, size: fileSizeBytes2) {
                
                        uploadCompleteCallbackExpectation.fulfill()
                        
                        let fileAttr1 = SMSyncServer.session.fileStatus(file1UUID)
                        XCTAssert(fileAttr1 != nil)
                        XCTAssert(!fileAttr1!.deleted!)

                        let fileAttr2 = SMSyncServer.session.fileStatus(file2UUID)
                        XCTAssert(fileAttr2 != nil)
                        XCTAssert(!fileAttr2!.deleted!)
                        
                        // Now, forget locally about the uploaded files so we can download them.
                        SMSyncServer.session.resetMetaData(forUUIDString:fileAttributes1.uuid.UUIDString)
                        SMSyncServer.session.resetMetaData(forUUIDString:fileAttributes2.uuid.UUIDString)
                        
                        SMDownloadFiles.session.checkForDownloads()
                    }
                }
            }
            
            // The ordering of the following two downloads isn't really well specified, but guessing it'll be in the same order as uploaded. Could make the check for download more complicated and order invariant...
            
            self.downloadCallbacks.append() { (downloadedFile:NSURL, downloadedFileAttr: SMSyncAttributes) in
                XCTAssert(downloadedFileAttr.uuid.UUIDString == fileAttributes1.uuid.UUIDString)
                let filesAreTheSame = SMFiles.compareFiles(file1: originalFile1.url(), file2: downloadedFile)
                XCTAssert(filesAreTheSame)
                numberDownloads++
                singleDownloadExpectation1.fulfill()
            }
            
            self.downloadCallbacks.append() { (downloadedFile:NSURL, downloadedFileAttr: SMSyncAttributes) in
                XCTAssert(downloadedFileAttr.uuid.UUIDString == fileAttributes2.uuid.UUIDString)
                let filesAreTheSame = SMFiles.compareFiles(file1: originalFile2.url(), file2: downloadedFile)
                XCTAssert(filesAreTheSame)
                numberDownloads++
                singleDownloadExpectation2.fulfill()
            }
            
            self.allDownloadsCompleteCallbacks.append() {
                XCTAssert(numberDownloads == 2)
                
                let fileAttr1 = SMSyncServer.session.fileStatus(file1UUID)
                XCTAssert(fileAttr1 != nil)
                XCTAssert(!fileAttr1!.deleted!)

                let fileAttr2 = SMSyncServer.session.fileStatus(file2UUID)
                XCTAssert(fileAttr2 != nil)
                XCTAssert(!fileAttr2!.deleted!)
                
                allDownloadsCompleteExpectation.fulfill()
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    // Start one download, and immediately after starting that download, commit an upload. Expect that download should finish, and then upload should start, serially, after the download.
    func testThatDownloadOfOneFileFollowedByAnUploadWorks() {
        // Upload, then download this file.
        let fileName1 = "DownloadOfOneFileFollowedByAnUploadA"
        let (originalFile1, fileSizeBytes1) = self.createFile(withName: fileName1)
        let file1UUID = NSUUID(UUIDString: originalFile1.uuid!)!
        let fileAttributes1 = SMSyncAttributes(withUUID: file1UUID, mimeType: "text/plain", andRemoteFileName: fileName1)
        
        // Upload this one after the download.
        let fileName2 = "DownloadOfOneFileFollowedByAnUploadB"
        let (originalFile2, fileSizeBytes2) = self.createFile(withName: fileName2)
        let file2UUID = NSUUID(UUIDString: originalFile2.uuid!)!
        let fileAttributes2 = SMSyncAttributes(withUUID: file2UUID, mimeType: "text/plain", andRemoteFileName: fileName2)

        let uploadCompleteCallbackExpectation1 = self.expectationWithDescription("Commit1 Complete")
        let uploadCompleteCallbackExpectation2 = self.expectationWithDescription("Commit2 Complete")

        let singleUploadExpectation1 = self.expectationWithDescription("Upload1 Complete")
        let singleUploadExpectation2 = self.expectationWithDescription("Upload2 Complete")

        let singleDownloadExpectation = self.expectationWithDescription("Single Download")

        let allDownloadsCompleteExpectation = self.expectationWithDescription("All Downloads Complete")
        var numberDownloads = 0
        var expectSecondUpload = false
        
        self.extraServerResponseTime = 60
        
        self.waitUntilSyncServerUserSignin() {
            SMSyncServer.session.uploadImmutableFile(originalFile1.url(), withFileAttributes: fileAttributes1)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == fileAttributes1.uuid.UUIDString)
                singleUploadExpectation1.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                self.checkFileSize(fileAttributes1.uuid.UUIDString, size: fileSizeBytes1) {
                
                    uploadCompleteCallbackExpectation1.fulfill()
                    
                    let fileAttr1 = SMSyncServer.session.fileStatus(file1UUID)
                    XCTAssert(fileAttr1 != nil)
                    XCTAssert(!fileAttr1!.deleted!)
                    
                    // Now, forget locally about the uploaded file so we can download it.
                    SMSyncServer.session.resetMetaData(forUUIDString:fileAttributes1.uuid.UUIDString)
                    
                    SMDownloadFiles.session.checkForDownloads()
                    
                    SMSyncServer.session.uploadImmutableFile(originalFile2.url(), withFileAttributes: fileAttributes2)
                    
                    SMSyncServer.session.commit()
                }
            }
 
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(expectSecondUpload)
                
                XCTAssert(uuid.UUIDString == fileAttributes2.uuid.UUIDString)
                singleUploadExpectation2.fulfill()
            }

            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                self.checkFileSize(fileAttributes2.uuid.UUIDString, size: fileSizeBytes2) {
                
                    let fileAttr2 = SMSyncServer.session.fileStatus(file2UUID)
                    XCTAssert(fileAttr2 != nil)
                    XCTAssert(!fileAttr2!.deleted!)
                    
                    uploadCompleteCallbackExpectation2.fulfill()
                }
            }
            
            self.downloadCallbacks.append() { (downloadedFile:NSURL, downloadedFileAttr: SMSyncAttributes) in
                XCTAssert(downloadedFileAttr.uuid.UUIDString == fileAttributes1.uuid.UUIDString)
                let filesAreTheSame = SMFiles.compareFiles(file1: originalFile1.url(), file2: downloadedFile)
                XCTAssert(filesAreTheSame)
                numberDownloads++
                singleDownloadExpectation.fulfill()
            }
            
            self.allDownloadsCompleteCallbacks.append() {
                XCTAssert(numberDownloads == 1)
                
                let fileAttr1 = SMSyncServer.session.fileStatus(file1UUID)
                XCTAssert(fileAttr1 != nil)
                XCTAssert(!fileAttr1!.deleted!)
                
                expectSecondUpload = true
                
                allDownloadsCompleteExpectation.fulfill()
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }

    // Start download of two files, and immediately after starting that download, commit an upload. Expect that both downloads should finish, and then upload should start, serially, after the downloads.
    func testThatDownloadOfTwoFilesFollowedByUploadWorks() {
        let fileName1 = "DownloadOfTwoFilesFollowedByUploadA"
        let (originalFile1, fileSizeBytes1) = self.createFile(withName: fileName1)
        let file1UUID = NSUUID(UUIDString: originalFile1.uuid!)!
        let fileAttributes1 = SMSyncAttributes(withUUID: file1UUID, mimeType: "text/plain", andRemoteFileName: fileName1)
        
        let fileName2 = "DownloadOfTwoFilesFollowedByUploadB"
        let (originalFile2, fileSizeBytes2) = self.createFile(withName: fileName2)
        let file2UUID = NSUUID(UUIDString: originalFile2.uuid!)!
        let fileAttributes2 = SMSyncAttributes(withUUID: file2UUID, mimeType: "text/plain", andRemoteFileName: fileName2)

        let fileName3 = "DownloadOfTwoFilesFollowedByUploadC"
        let (originalFile3, fileSizeBytes3) = self.createFile(withName: fileName3)
        let file3UUID = NSUUID(UUIDString: originalFile3.uuid!)!
        let fileAttributes3 = SMSyncAttributes(withUUID: file3UUID, mimeType: "text/plain", andRemoteFileName: fileName3)

        let uploadCompleteCallbackExpectation1 = self.expectationWithDescription("Commit1 Complete")
        let uploadCompleteCallbackExpectation2 = self.expectationWithDescription("Commit2 Complete")

        let singleUploadExpectation1 = self.expectationWithDescription("Upload1 Complete")
        let singleUploadExpectation2 = self.expectationWithDescription("Upload2 Complete")
        let singleUploadExpectation3 = self.expectationWithDescription("Upload3 Complete")

        let singleDownloadExpectation1 = self.expectationWithDescription("Single1 Download")
        let singleDownloadExpectation2 = self.expectationWithDescription("Single2 Download")

        let allDownloadsCompleteExpectation = self.expectationWithDescription("All Downloads Complete")
        var numberDownloads = 0
        var expectThirdUpload = false
        
        self.extraServerResponseTime = 60
        
        self.waitUntilSyncServerUserSignin() {
            SMSyncServer.session.uploadImmutableFile(originalFile1.url(), withFileAttributes: fileAttributes1)
            SMSyncServer.session.uploadImmutableFile(originalFile2.url(), withFileAttributes: fileAttributes2)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == fileAttributes1.uuid.UUIDString)
                singleUploadExpectation1.fulfill()
            }

            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == fileAttributes2.uuid.UUIDString)
                singleUploadExpectation2.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 2)
                self.checkFileSize(fileAttributes1.uuid.UUIDString, size: fileSizeBytes1) {
                    self.checkFileSize(fileAttributes2.uuid.UUIDString, size: fileSizeBytes2) {
                
                        uploadCompleteCallbackExpectation1.fulfill()
                        
                        let fileAttr1 = SMSyncServer.session.fileStatus(file1UUID)
                        XCTAssert(fileAttr1 != nil)
                        XCTAssert(!fileAttr1!.deleted!)

                        let fileAttr2 = SMSyncServer.session.fileStatus(file2UUID)
                        XCTAssert(fileAttr2 != nil)
                        XCTAssert(!fileAttr2!.deleted!)
                        
                        // Now, forget locally about the uploaded files so we can download them.
                        SMSyncServer.session.resetMetaData(forUUIDString:fileAttributes1.uuid.UUIDString)
                        SMSyncServer.session.resetMetaData(forUUIDString:fileAttributes2.uuid.UUIDString)
                        
                        SMDownloadFiles.session.checkForDownloads()
                        
                        SMSyncServer.session.uploadImmutableFile(originalFile3.url(), withFileAttributes: fileAttributes3)
                        SMSyncServer.session.commit()
                    }
                }
            }
            
            // The ordering of the following two downloads isn't really well specified, but guessing it'll be in the same order as uploaded. Could make the check for download more complicated and order invariant...
            
            self.downloadCallbacks.append() { (downloadedFile:NSURL, downloadedFileAttr: SMSyncAttributes) in
                XCTAssert(downloadedFileAttr.uuid.UUIDString == fileAttributes1.uuid.UUIDString)
                let filesAreTheSame = SMFiles.compareFiles(file1: originalFile1.url(), file2: downloadedFile)
                XCTAssert(filesAreTheSame)
                numberDownloads++
                singleDownloadExpectation1.fulfill()
            }
            
            self.downloadCallbacks.append() { (downloadedFile:NSURL, downloadedFileAttr: SMSyncAttributes) in
                XCTAssert(downloadedFileAttr.uuid.UUIDString == fileAttributes2.uuid.UUIDString)
                let filesAreTheSame = SMFiles.compareFiles(file1: originalFile2.url(), file2: downloadedFile)
                XCTAssert(filesAreTheSame)
                numberDownloads++
                singleDownloadExpectation2.fulfill()
            }
            
            self.allDownloadsCompleteCallbacks.append() {
                XCTAssert(numberDownloads == 2)
                
                let fileAttr1 = SMSyncServer.session.fileStatus(file1UUID)
                XCTAssert(fileAttr1 != nil)
                XCTAssert(!fileAttr1!.deleted!)

                let fileAttr2 = SMSyncServer.session.fileStatus(file2UUID)
                XCTAssert(fileAttr2 != nil)
                XCTAssert(!fileAttr2!.deleted!)
                
                expectThirdUpload = true
                
                allDownloadsCompleteExpectation.fulfill()
            }
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(expectThirdUpload)
                
                XCTAssert(uuid.UUIDString == fileAttributes3.uuid.UUIDString)
                singleUploadExpectation3.fulfill()
            }

            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                self.checkFileSize(fileAttributes3.uuid.UUIDString, size: fileSizeBytes3) {
                
                    let fileAttr3 = SMSyncServer.session.fileStatus(file3UUID)
                    XCTAssert(fileAttr3 != nil)
                    XCTAssert(!fileAttr3!.deleted!)
                    
                    uploadCompleteCallbackExpectation2.fulfill()
                }
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    // TODO: Server files which are updated versions of those on app/client.
    
    // TODO: Server file has been deleted, so download causes deletion of file on app/client. NOTE: This isn't yet handled by SMFileDiffs.
    
    // TODO: Each of the conflict cases: update conflict, and the two deletion conflicts. NOTE: This isn't yet handled by SMFileDiffs.
}
