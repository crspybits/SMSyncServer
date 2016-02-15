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
            
            let testFile = TestBasics.session.createTestFile("FilesInSyncResultsInNoDownloads")
            
            SMSyncServer.session.uploadImmutableFile(testFile.url, withFileAttributes: testFile.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile.uuidString)
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(testFile.uuidString, size: testFile.sizeInBytes) {
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
        let testFile = TestBasics.session.createTestFile("DownloadOfOneFile")
        self.downloadOneFile(testFile)
    }
    
    func downloadOneFile(testFile:TestFile) {

        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Commit Complete")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")
        let singleDownloadExpectation = self.expectationWithDescription("Single Download")
        let allDownloadsCompleteExpectation = self.expectationWithDescription("All Downloads Complete")
        var numberDownloads = 0
        
        self.extraServerResponseTime = 60
        
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
                    
                    // Now, forget locally about that uploaded file so we can download it.
                    SMSyncServer.session.resetMetaData(forUUID:testFile.uuid)
                    
                    SMDownloadFiles.session.checkForDownloads()
                }
            }
            
            self.downloadCallbacks.append() { (downloadedFile:NSURL, downloadedFileAttr: SMSyncAttributes) in
                XCTAssert(downloadedFileAttr.uuid.UUIDString == testFile.uuidString)
                let filesAreTheSame = SMFiles.compareFiles(file1: testFile.url, file2: downloadedFile)
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
        
        var testFile = TestFile()
        testFile.appFile = file
        testFile.sizeInBytes = 917630
        testFile.mimeType = "image/png"
        testFile.fileName = file.fileName
        testFile.url = NSBundle.mainBundle().URLForResource("Kitty", withExtension: "png")!

        self.downloadOneFile(testFile)
    }
    
    // Try to download a file, through the SMServerAPI, that is on the server, but isn't in the PSInboundFile's. i.e., that hasn't been transfered from the cloud to the server.
    func testThatDownloadOfUntransferredServerFileDoesntWork() {
        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Commit Complete")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")
        let unlockExpectation = self.expectationWithDescription("Unlock Complete")

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

                    SMServerAPI.session.lock() { lockResult in
                        XCTAssert(lockResult.error == nil)

                        let downloadFileURL = FileStorage.urlOfItem("download1")
                        let serverFile = SMServerFile(uuid: testFile.uuid)
                        serverFile.localURL = downloadFileURL
                    
                        SMServerAPI.session.downloadFile(serverFile) { downloadResult in
                            // Should get an error here: Because we're trying to download a file that's not in the PSInboundFiles and marked as received. I.e., it hasn't been transferred from the server.
                            XCTAssert(downloadResult.error != nil)
                            
                            SMServerAPI.session.unlock() { unlockResult in
                                XCTAssert(unlockResult.error == nil)
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
        let testFile1 = TestBasics.session.createTestFile("DownloadOfTwoFilesA")
        let testFile2 = TestBasics.session.createTestFile("DownloadOfTwoFilesB")

        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Commit Complete")
        let singleUploadExpectation1 = self.expectationWithDescription("Upload1 Complete")
        let singleUploadExpectation2 = self.expectationWithDescription("Upload2 Complete")

        let singleDownloadExpectation1 = self.expectationWithDescription("Single1 Download")
        let singleDownloadExpectation2 = self.expectationWithDescription("Single2 Download")

        let allDownloadsCompleteExpectation = self.expectationWithDescription("All Downloads Complete")
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
                TestBasics.session.checkFileSize(testFile1.uuidString, size: testFile1.sizeInBytes) {
                    TestBasics.session.checkFileSize(testFile2.uuidString, size: testFile2.sizeInBytes) {
                
                        uploadCompleteCallbackExpectation.fulfill()
                        
                        let fileAttr1 = SMSyncServer.session.fileStatus(testFile1.uuid)
                        XCTAssert(fileAttr1 != nil)
                        XCTAssert(!fileAttr1!.deleted!)

                        let fileAttr2 = SMSyncServer.session.fileStatus(testFile2.uuid)
                        XCTAssert(fileAttr2 != nil)
                        XCTAssert(!fileAttr2!.deleted!)
                        
                        // Now, forget locally about the uploaded files so we can download them.
                        SMSyncServer.session.resetMetaData(forUUID:testFile1.uuid)
                        SMSyncServer.session.resetMetaData(forUUID:testFile2.uuid)
                        
                        SMDownloadFiles.session.checkForDownloads()
                    }
                }
            }
            
            // The ordering of the following two downloads isn't really well specified, but guessing it'll be in the same order as uploaded. Could make the check for download more complicated and order invariant...
            
            self.downloadCallbacks.append() { (downloadedFile:NSURL, downloadedFileAttr: SMSyncAttributes) in
                XCTAssert(downloadedFileAttr.uuid.UUIDString == testFile1.uuidString)
                let filesAreTheSame = SMFiles.compareFiles(file1: testFile1.url, file2: downloadedFile)
                XCTAssert(filesAreTheSame)
                numberDownloads++
                singleDownloadExpectation1.fulfill()
            }
            
            self.downloadCallbacks.append() { (downloadedFile:NSURL, downloadedFileAttr: SMSyncAttributes) in
                XCTAssert(downloadedFileAttr.uuid.UUIDString == testFile2.uuidString)
                let filesAreTheSame = SMFiles.compareFiles(file1: testFile2.url, file2: downloadedFile)
                XCTAssert(filesAreTheSame)
                numberDownloads++
                singleDownloadExpectation2.fulfill()
            }
            
            self.allDownloadsCompleteCallbacks.append() {
                XCTAssert(numberDownloads == 2)
                
                let fileAttr1 = SMSyncServer.session.fileStatus(testFile1.uuid)
                XCTAssert(fileAttr1 != nil)
                XCTAssert(!fileAttr1!.deleted!)

                let fileAttr2 = SMSyncServer.session.fileStatus(testFile2.uuid)
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
        let testFile1 = TestBasics.session.createTestFile("DownloadOfOneFileFollowedByAnUploadA")
        
        // Upload this one after the download.
        let testFile2 = TestBasics.session.createTestFile("DownloadOfOneFileFollowedByAnUploadB")

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
            SMSyncServer.session.uploadImmutableFile(testFile1.url, withFileAttributes: testFile1.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile1.uuidString)
                singleUploadExpectation1.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(testFile1.uuidString, size: testFile1.sizeInBytes) {
                
                    uploadCompleteCallbackExpectation1.fulfill()
                    
                    let fileAttr1 = SMSyncServer.session.fileStatus(testFile1.uuid)
                    XCTAssert(fileAttr1 != nil)
                    XCTAssert(!fileAttr1!.deleted!)
                    
                    // Now, forget locally about the uploaded file so we can download it.
                    SMSyncServer.session.resetMetaData(forUUID: testFile1.uuid)
                    
                    SMDownloadFiles.session.checkForDownloads()
                    
                    SMSyncServer.session.uploadImmutableFile(testFile2.url, withFileAttributes: testFile2.attr)
                    
                    SMSyncServer.session.commit()
                }
            }
 
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(expectSecondUpload)
                
                XCTAssert(uuid.UUIDString == testFile2.uuidString)
                singleUploadExpectation2.fulfill()
            }

            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(testFile2.uuidString, size: testFile2.sizeInBytes) {
                
                    let fileAttr2 = SMSyncServer.session.fileStatus(testFile2.uuid)
                    XCTAssert(fileAttr2 != nil)
                    XCTAssert(!fileAttr2!.deleted!)
                    
                    uploadCompleteCallbackExpectation2.fulfill()
                }
            }
            
            self.downloadCallbacks.append() { (downloadedFile:NSURL, downloadedFileAttr: SMSyncAttributes) in
                XCTAssert(downloadedFileAttr.uuid.UUIDString == testFile1.uuidString)
                let filesAreTheSame = SMFiles.compareFiles(file1: testFile1.url, file2: downloadedFile)
                XCTAssert(filesAreTheSame)
                numberDownloads++
                singleDownloadExpectation.fulfill()
            }
            
            self.allDownloadsCompleteCallbacks.append() {
                XCTAssert(numberDownloads == 1)
                
                let fileAttr1 = SMSyncServer.session.fileStatus(testFile1.uuid)
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
                        
                        let fileAttr1 = SMSyncServer.session.fileStatus(testFile1.uuid)
                        XCTAssert(fileAttr1 != nil)
                        XCTAssert(!fileAttr1!.deleted!)

                        let fileAttr2 = SMSyncServer.session.fileStatus(testFile2.uuid)
                        XCTAssert(fileAttr2 != nil)
                        XCTAssert(!fileAttr2!.deleted!)
                        
                        // Now, forget locally about the uploaded files so we can download them.
                        SMSyncServer.session.resetMetaData(forUUID: testFile1.uuid)
                        SMSyncServer.session.resetMetaData(forUUID: testFile2.uuid)
                        
                        SMDownloadFiles.session.checkForDownloads()
                        
                        SMSyncServer.session.uploadImmutableFile(testFile3.url, withFileAttributes: testFile3.attr)
                        SMSyncServer.session.commit()
                    }
                }
            }
            
            // The ordering of the following two downloads isn't really well specified, but guessing it'll be in the same order as uploaded. Could make the check for download more complicated and order invariant...
            
            self.downloadCallbacks.append() { (downloadedFile:NSURL, downloadedFileAttr: SMSyncAttributes) in
                XCTAssert(downloadedFileAttr.uuid.UUIDString == testFile1.uuidString)
                let filesAreTheSame = SMFiles.compareFiles(file1: testFile1.url, file2: downloadedFile)
                XCTAssert(filesAreTheSame)
                numberDownloads++
                singleDownloadExpectation1.fulfill()
            }
            
            self.downloadCallbacks.append() { (downloadedFile:NSURL, downloadedFileAttr: SMSyncAttributes) in
                XCTAssert(downloadedFileAttr.uuid.UUIDString == testFile2.uuidString)
                let filesAreTheSame = SMFiles.compareFiles(file1: testFile2.url, file2: downloadedFile)
                XCTAssert(filesAreTheSame)
                numberDownloads++
                singleDownloadExpectation2.fulfill()
            }
            
            self.allDownloadsCompleteCallbacks.append() {
                XCTAssert(numberDownloads == 2)
                
                let fileAttr1 = SMSyncServer.session.fileStatus(testFile1.uuid)
                XCTAssert(fileAttr1 != nil)
                XCTAssert(!fileAttr1!.deleted!)

                let fileAttr2 = SMSyncServer.session.fileStatus(testFile2.uuid)
                XCTAssert(fileAttr2 != nil)
                XCTAssert(!fileAttr2!.deleted!)
                
                expectThirdUpload = true
                
                allDownloadsCompleteExpectation.fulfill()
            }
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(expectThirdUpload)
                
                XCTAssert(uuid.UUIDString == testFile3.uuidString)
                singleUploadExpectation3.fulfill()
            }

            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(testFile3.uuidString, size: testFile3.sizeInBytes) {
                
                    let fileAttr3 = SMSyncServer.session.fileStatus(testFile3.uuid)
                    XCTAssert(fileAttr3 != nil)
                    XCTAssert(!fileAttr3!.deleted!)
                    
                    uploadCompleteCallbackExpectation2.fulfill()
                }
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
        
    // TODO: Server file has been deleted, so download causes deletion of file on app/client. NOTE: This isn't yet handled by SMFileDiffs.
    
    // TODO: Each of the conflict cases: update conflict, and the two deletion conflicts. NOTE: This isn't yet handled by SMFileDiffs.
}
