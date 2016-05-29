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
        let idleExpectation1 = self.expectationWithDescription("Idle1")
        let idleExpectation2 = self.expectationWithDescription("Idle2")
       
        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            
            let testFile = TestBasics.session.createTestFile("FilesInSyncResultsInNoDownloads")
            
            SMSyncServer.session.uploadImmutableFile(testFile.url, withFileAttributes: testFile.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile.uuidString)
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads >= 1)
                TestBasics.session.checkFileSize(testFile.uuidString, size: testFile.sizeInBytes) {
                    uploadCompleteCallbackExpectation.fulfill()
                }
            }
            
            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation1.fulfill()
                self.numberOfNoDownloadsCallbacks = 0
                SMSyncControl.session.nextSyncOperation()
            }
            
            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation2.fulfill()
                XCTAssert(self.numberOfNoDownloadsCallbacks == 1)
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    // Download a single server file which doesn't yet exist on the app/client.
    func testThatDownloadOfOneFileWorks() {
        let testFile = TestBasics.session.createTestFile("DownloadOfOneFile")
        self.downloadOneFile(testFile)
    }
    
    func testThatDownloadOfAnEmptyFileWorks() {
        let testFile = TestBasics.session.createTestFile("DownloadOfAnEmptyFile", withContents: "")
        self.downloadOneFile(testFile)
    }
    
    func downloadOneFile(testFile:TestFile) {

        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Commit Complete")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")
        let singleDownloadExpectation = self.expectationWithDescription("Single Download")
        let allDownloadsCompleteExpectation = self.expectationWithDescription("All Downloads Complete")
        let idleExpectation1 = self.expectationWithDescription("Idle1")
        let idleExpectation2 = self.expectationWithDescription("Idle2")

        var numberDownloads = 0
        
        self.extraServerResponseTime = 360
        
        self.waitUntilSyncServerUserSignin() {
            SMSyncServer.session.uploadImmutableFile(testFile.url, withFileAttributes: testFile.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile.uuidString)
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(testFile.uuidString, size: testFile.sizeInBytes) {
                    uploadCompleteCallbackExpectation.fulfill()
                }
            }
            
            self.singleDownload.append() { (downloadedFile:NSURL, downloadedFileAttr: SMSyncAttributes) in
                XCTAssert(downloadedFileAttr.uuid.UUIDString == testFile.uuidString)
                let filesAreTheSame = SMFiles.compareFiles(file1: testFile.url, file2: downloadedFile)
                XCTAssert(filesAreTheSame)
                numberDownloads += 1
                singleDownloadExpectation.fulfill()
            }
            
            self.shouldSaveDownloads.append() { downloadedFiles, ack in
                XCTAssert(numberDownloads == 1)
                XCTAssert(downloadedFiles.count == 1)
                let (_, _) = downloadedFiles[0]
                allDownloadsCompleteExpectation.fulfill()
                ack()
            }
            
            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation1.fulfill()
                
                // Forget locally about the uploaded file so we can download it.
                SMSyncServer.session.resetMetaData(forUUID:testFile.uuid)
                
                // Force the check for downloads.
                SMSyncControl.session.nextSyncOperation()
            }
            
            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation2.fulfill()
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
        
        var testFile = TestFile()
        testFile.appFile = file
        testFile.sizeInBytes = 917630
        testFile.mimeType = "image/png"
        testFile.fileName = file.fileName
        testFile.url = SMRelativeLocalURL(withRelativePath: "Kitty.png", toBaseURLType: .MainBundle)!

        self.downloadOneFile(testFile)
    }
    
    // Try to download a file, through the SMServerAPI, that is on the server, but isn't in the PSInboundFile's. i.e., that hasn't been transfered from the cloud to the server.
    func testThatDownloadOfUntransferredServerFileDoesntWork() {
        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Commit Complete")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")
        let downloadExpectation = self.expectationWithDescription("Download Complete")
        let idleExpectation = self.expectationWithDescription("Idle")

        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            
            let testFile = TestBasics.session.createTestFile("DownloadOfUntransferredServerFile")
            
            SMSyncServer.session.uploadImmutableFile(testFile.url, withFileAttributes: testFile.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile.uuidString)
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(testFile.uuidString, size: testFile.sizeInBytes) {
                    uploadCompleteCallbackExpectation.fulfill()
                }
            }
            
            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation.fulfill()

                let downloadFileURL = SMRelativeLocalURL(withRelativePath: "download1", toBaseURLType: .DocumentsDirectory)
                let serverFile = SMServerFile(uuid: testFile.uuid)
                serverFile.localURL = downloadFileURL
            
                SMServerAPI.session.downloadFile(serverFile) { downloadResult in
                    // Should get an error here: Because we're trying to download a file that's not in the PSInboundFiles and marked as received. I.e., it hasn't been transferred from the server.
                    XCTAssert(downloadResult.error != nil)
                    
                    downloadExpectation.fulfill()
                }
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    // Download two server files which don't yet exist on the app/client.
    func testThatDownloadOfTwoFilesWorks() {
        let testFile1 = TestBasics.session.createTestFile("DownloadOfTwoFilesA")
        let testFile2 = TestBasics.session.createTestFile("DownloadOfTwoFilesB")

        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Commit Complete")
        let singleUploadExpectation1 = self.expectationWithDescription("Upload1 Complete")
        let singleUploadExpectation2 = self.expectationWithDescription("Upload2 Complete")

        let singleDownloadExpectation1 = self.expectationWithDescription("Single1 Download")
        let singleDownloadExpectation2 = self.expectationWithDescription("Single2 Download")

        let allDownloadsCompleteExpectation = self.expectationWithDescription("All Downloads Complete")
        let idleExpectation1 = self.expectationWithDescription("Idle1")
        let idleExpectation2 = self.expectationWithDescription("Idle2")

        var numberDownloads = 0
        
        self.extraServerResponseTime = 60
        
        self.waitUntilSyncServerUserSignin() {
            SMSyncServer.session.uploadImmutableFile(testFile1.url, withFileAttributes: testFile1.attr)
            SMSyncServer.session.uploadImmutableFile(testFile2.url, withFileAttributes: testFile2.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile1.uuidString)
                singleUploadExpectation1.fulfill()
            }

            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile2.uuidString)
                singleUploadExpectation2.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 2)
                uploadCompleteCallbackExpectation.fulfill()
                // Don't put the check size calls here-- will result in a race condition.
            }
            
            // The ordering of the following two downloads isn't really well specified, but guessing it'll be in the same order as uploaded. Could make the check for download more complicated and order invariant...
            
            self.singleDownload.append() { (downloadedFile:NSURL, downloadedFileAttr: SMSyncAttributes) in
                XCTAssert(downloadedFileAttr.uuid.UUIDString == testFile1.uuidString)
                let filesAreTheSame = SMFiles.compareFiles(file1: testFile1.url, file2: downloadedFile)
                XCTAssert(filesAreTheSame)
                numberDownloads += 1
                singleDownloadExpectation1.fulfill()
            }
            
            self.singleDownload.append() { (downloadedFile:NSURL, downloadedFileAttr: SMSyncAttributes) in
                XCTAssert(downloadedFileAttr.uuid.UUIDString == testFile2.uuidString)
                let filesAreTheSame = SMFiles.compareFiles(file1: testFile2.url, file2: downloadedFile)
                XCTAssert(filesAreTheSame)
                numberDownloads += 1
                singleDownloadExpectation2.fulfill()
            }
            
            self.shouldSaveDownloads.append() { downloadedFiles, ack in
                XCTAssert(numberDownloads == 2)
                XCTAssert(downloadedFiles.count == 2)
                
                let fileAttr1 = SMSyncServer.session.localFileStatus(testFile1.uuid)
                XCTAssert(fileAttr1 != nil)
                XCTAssert(!fileAttr1!.deleted!)

                let fileAttr2 = SMSyncServer.session.localFileStatus(testFile2.uuid)
                XCTAssert(fileAttr2 != nil)
                XCTAssert(!fileAttr2!.deleted!)
                
                allDownloadsCompleteExpectation.fulfill()
                ack()
            }
            
            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation1.fulfill()

                TestBasics.session.checkFileSize(testFile1.uuidString, size: testFile1.sizeInBytes) {
                    TestBasics.session.checkFileSize(testFile2.uuidString, size: testFile2.sizeInBytes) {
                        
                        let fileAttr1 = SMSyncServer.session.localFileStatus(testFile1.uuid)
                        XCTAssert(fileAttr1 != nil)
                        XCTAssert(!fileAttr1!.deleted!)

                        let fileAttr2 = SMSyncServer.session.localFileStatus(testFile2.uuid)
                        XCTAssert(fileAttr2 != nil)
                        XCTAssert(!fileAttr2!.deleted!)
                        
                        // We checked for the files. Now, forget locally about the uploaded files so we can download them.
                        SMSyncServer.session.resetMetaData(forUUID:testFile1.uuid)
                        SMSyncServer.session.resetMetaData(forUUID:testFile2.uuid)
                        
                        SMSyncControl.session.nextSyncOperation()
                    }
                }
            }
            
            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation2.fulfill()
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    // Start one download, and immediately after starting that download, commit an upload. Expect that download should finish, and then upload should start, serially, after the download.
    func testThatDownloadOfOneFileFollowedByAnUploadWorks() {
        // Upload, then download this file.
        let testFile1 = TestBasics.session.createTestFile("DownloadOfOneFileFollowedByAnUploadA")
        
        // Upload this one after the download.
        let testFile2 = TestBasics.session.createTestFile("DownloadOfOneFileFollowedByAnUploadB")

        let uploadCompleteCallbackExpectation1 = self.expectationWithDescription("Commit1 Complete")
        let uploadCompleteCallbackExpectation2 = self.expectationWithDescription("Commit2 Complete")

        let singleUploadExpectation1 = self.expectationWithDescription("Upload1 Complete")
        let singleUploadExpectation2 = self.expectationWithDescription("Upload2 Complete")

        let singleDownloadExpectation = self.expectationWithDescription("Single Download")

        let allDownloadsCompleteExpectation = self.expectationWithDescription("All Downloads Complete")
        let idleExpectation1 = self.expectationWithDescription("Idle1")
        let idleExpectation2 = self.expectationWithDescription("Idle2")

        var numberDownloads = 0
        var expectSecondUpload = false
        
        self.extraServerResponseTime = 120
        
        self.waitUntilSyncServerUserSignin() {
            SMSyncServer.session.uploadImmutableFile(testFile1.url, withFileAttributes: testFile1.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile1.uuidString)
                singleUploadExpectation1.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                uploadCompleteCallbackExpectation1.fulfill()
            }
 
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(expectSecondUpload)
                
                XCTAssert(uuid.UUIDString == testFile2.uuidString)
                singleUploadExpectation2.fulfill()
            }

            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(testFile2.uuidString, size: testFile2.sizeInBytes) {
                
                    let fileAttr2 = SMSyncServer.session.localFileStatus(testFile2.uuid)
                    XCTAssert(fileAttr2 != nil)
                    XCTAssert(!fileAttr2!.deleted!)
                    
                    uploadCompleteCallbackExpectation2.fulfill()
                }
            }
            
            self.singleDownload.append() { (downloadedFile:NSURL, downloadedFileAttr: SMSyncAttributes) in
                XCTAssert(downloadedFileAttr.uuid.UUIDString == testFile1.uuidString)
                let filesAreTheSame = SMFiles.compareFiles(file1: testFile1.url, file2: downloadedFile)
                XCTAssert(filesAreTheSame)
                numberDownloads += 1
                singleDownloadExpectation.fulfill()
            }
            
            self.shouldSaveDownloads.append() { downloadedFiles, ack in
                XCTAssert(numberDownloads == 1)
                XCTAssert(downloadedFiles.count == 1)
                
                let fileAttr1 = SMSyncServer.session.localFileStatus(testFile1.uuid)
                XCTAssert(fileAttr1 != nil)
                XCTAssert(!fileAttr1!.deleted!)
                
                expectSecondUpload = true
                
                allDownloadsCompleteExpectation.fulfill()
                ack()
            }
            
            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation1.fulfill()
                
                TestBasics.session.checkFileSize(testFile1.uuidString, size: testFile1.sizeInBytes) {
                    
                    let fileAttr1 = SMSyncServer.session.localFileStatus(testFile1.uuid)
                    XCTAssert(fileAttr1 != nil)
                    XCTAssert(!fileAttr1!.deleted!)
                    
                    // Now, forget locally about the uploaded file so we can download it.
                    SMSyncServer.session.resetMetaData(forUUID: testFile1.uuid)
                    
                    SMSyncControl.session.nextSyncOperation()
                    
                    SMSyncServer.session.uploadImmutableFile(testFile2.url, withFileAttributes: testFile2.attr)
                    
                    // let idleExpectation = self.expectationWithDescription("Idle")
                    self.idleCallbacks.append() {
                        idleExpectation2.fulfill()
                    }
                    
                    SMSyncServer.session.commit()
                }
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }

    // Start download of two files, and immediately after starting that download, commit an upload. Expect that both downloads should finish, and then upload should start, serially, after the downloads.
    func testThatDownloadOfTwoFilesFollowedByUploadWorks() {
        let testFile1 = TestBasics.session.createTestFile("DownloadOfTwoFilesFollowedByUploadA")
        let testFile2 = TestBasics.session.createTestFile("DownloadOfTwoFilesFollowedByUploadB")
        let testFile3 = TestBasics.session.createTestFile("DownloadOfTwoFilesFollowedByUploadC")

        let uploadCompleteCallbackExpectation1 = self.expectationWithDescription("Commit1 Complete")
        let uploadCompleteCallbackExpectation2 = self.expectationWithDescription("Commit2 Complete")

        let singleUploadExpectation1 = self.expectationWithDescription("Upload1 Complete")
        let singleUploadExpectation2 = self.expectationWithDescription("Upload2 Complete")
        let singleUploadExpectation3 = self.expectationWithDescription("Upload3 Complete")

        let singleDownloadExpectation1 = self.expectationWithDescription("Single1 Download")
        let singleDownloadExpectation2 = self.expectationWithDescription("Single2 Download")

        let allDownloadsCompleteExpectation = self.expectationWithDescription("All Downloads Complete")
        let idleExpectation1 = self.expectationWithDescription("Idle1")
        let idleExpectation2 = self.expectationWithDescription("Idle2")

        var numberDownloads = 0
        var expectThirdUpload = false
        
        self.extraServerResponseTime = 60
        
        self.waitUntilSyncServerUserSignin() {
            SMSyncServer.session.uploadImmutableFile(testFile1.url, withFileAttributes: testFile1.attr)
            SMSyncServer.session.uploadImmutableFile(testFile2.url, withFileAttributes: testFile2.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile1.uuidString)
                singleUploadExpectation1.fulfill()
            }

            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile2.uuidString)
                singleUploadExpectation2.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 2)
                TestBasics.session.checkFileSize(testFile1.uuidString, size: testFile1.sizeInBytes) {
                    TestBasics.session.checkFileSize(testFile2.uuidString, size: testFile2.sizeInBytes) {
                
                        uploadCompleteCallbackExpectation1.fulfill()
                        
                        let fileAttr1 = SMSyncServer.session.localFileStatus(testFile1.uuid)
                        XCTAssert(fileAttr1 != nil)
                        XCTAssert(!fileAttr1!.deleted!)

                        let fileAttr2 = SMSyncServer.session.localFileStatus(testFile2.uuid)
                        XCTAssert(fileAttr2 != nil)
                        XCTAssert(!fileAttr2!.deleted!)
                    }
                }
            }
            
            // The ordering of the following two downloads isn't really well specified, but guessing it'll be in the same order as uploaded. Could make the check for download more complicated and order invariant...
            
            self.singleDownload.append() { (downloadedFile:NSURL, downloadedFileAttr: SMSyncAttributes) in
                XCTAssert(downloadedFileAttr.uuid.UUIDString == testFile1.uuidString)
                let filesAreTheSame = SMFiles.compareFiles(file1: testFile1.url, file2: downloadedFile)
                XCTAssert(filesAreTheSame)
                numberDownloads += 1
                singleDownloadExpectation1.fulfill()
            }
            
            self.singleDownload.append() { (downloadedFile:NSURL, downloadedFileAttr: SMSyncAttributes) in
                XCTAssert(downloadedFileAttr.uuid.UUIDString == testFile2.uuidString)
                let filesAreTheSame = SMFiles.compareFiles(file1: testFile2.url, file2: downloadedFile)
                XCTAssert(filesAreTheSame)
                numberDownloads += 1
                singleDownloadExpectation2.fulfill()
            }
            
            self.shouldSaveDownloads.append() { downloadedFiles, ack in
                XCTAssert(numberDownloads == 2)
                XCTAssert(downloadedFiles.count == 2)
                
                let fileAttr1 = SMSyncServer.session.localFileStatus(testFile1.uuid)
                XCTAssert(fileAttr1 != nil)
                XCTAssert(!fileAttr1!.deleted!)

                let fileAttr2 = SMSyncServer.session.localFileStatus(testFile2.uuid)
                XCTAssert(fileAttr2 != nil)
                XCTAssert(!fileAttr2!.deleted!)
                
                expectThirdUpload = true
                
                allDownloadsCompleteExpectation.fulfill()
                ack()
            }
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(expectThirdUpload)
                
                XCTAssert(uuid.UUIDString == testFile3.uuidString)
                singleUploadExpectation3.fulfill()
            }

            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(testFile3.uuidString, size: testFile3.sizeInBytes) {
                
                    let fileAttr3 = SMSyncServer.session.localFileStatus(testFile3.uuid)
                    XCTAssert(fileAttr3 != nil)
                    XCTAssert(!fileAttr3!.deleted!)
                    
                    uploadCompleteCallbackExpectation2.fulfill()
                }
            }
            
            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation1.fulfill()
                       
                // Now, forget locally about the uploaded files so we can download them.
                SMSyncServer.session.resetMetaData(forUUID: testFile1.uuid)
                SMSyncServer.session.resetMetaData(forUUID: testFile2.uuid)
                
                SMSyncControl.session.nextSyncOperation()
                
                SMSyncServer.session.uploadImmutableFile(testFile3.url, withFileAttributes: testFile3.attr)
                
                self.idleCallbacks.append() {
                    idleExpectation2.fulfill()
                }
            
                SMSyncServer.session.commit()
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
}
