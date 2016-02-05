//
//  Upload.swift
//  NetDb
//
//  Created by Christopher Prince on 12/18/15.
//  Copyright © 2015 Spastic Muffin, LLC. All rights reserved.
//

// Test case: Failure after uploading all files, and immediately before transferring, so the recovery doesn't have to do any uploading just needs to redo the commit.

import XCTest
// The @testable notation lets us access "internal" classes within our project.
@testable import Tests
@testable import SMSyncServer
import SMCoreLib

class Upload: BaseClass {
    
    // To enable 2nd part of recovery test after app crash.
    static let recoveryAfterAppCrash = SMPersistItemBool(name: "SMNetDbTestsRecoveryAfterAppCrash", initialBoolValue: true, persistType: .UserDefaults)
    
    // Flag so I can get ordering of expectations right.
    var doneRecovery = false

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
        self.doneRecovery = false
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    //MARK: "Normal" (non-recovery) tests that should succeed. These are the expected use cases.
    
    func testThatEmptyCommitDoesNothing() {
        let afterCommitExpectation = self.expectationWithDescription("After Commit")
        
        self.waitUntilSyncServerUserSignin() {
            SMSyncServer.session.commit()
            XCTAssert(!SMSyncServer.session.isOperating)
            
            afterCommitExpectation.fulfill()
        }
        
        self.waitForExpectations()
    }
    
    func testThatSingleFileUploadWorks() {
        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Commit Complete")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")
        
        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            
            let fileName = "SingleFileUpload"
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
                    let fileAttr = SMSyncServer.session.fileStatus(fileUUID)
                    XCTAssert(fileAttr != nil)
                    XCTAssert(!fileAttr!.deleted!)
                
                    uploadCompleteCallbackExpectation.fulfill()
                }
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    func testThatSingleTemporaryFileUploadWorks() {
        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Upload Complete")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")
        
        self.waitUntilSyncServerUserSignin() {
            
            let fileName = "SingleTemporaryFileUpload"
            let (file, fileSizeBytes) = self.createFile(withName: fileName)
            let fileUUID = NSUUID(UUIDString: file.uuid!)!
            let fileAttributes = SMSyncAttributes(withUUID: fileUUID, mimeType: "text/plain", andRemoteFileName: fileName)
            
            SMSyncServer.session.uploadTemporaryFile(file.url(), withFileAttributes: fileAttributes)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file.uuid!)
                
                // Test for file existence so later testing for non-existence makes sense.
                XCTAssert(FileStorage.itemExists(fileName))
                
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                
                // File should have been deleted by now.
                XCTAssert(!FileStorage.itemExists(fileName))
                
                let fileAttr = SMSyncServer.session.fileStatus(fileUUID)
                XCTAssert(fileAttr != nil)
                XCTAssert(!fileAttr!.deleted!)
                
                self.checkFileSize(file.uuid!, size: fileSizeBytes) {
                    uploadCompleteCallbackExpectation.fulfill()
                }
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    func testThatSingleDataUploadWorks() {
        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Upload Complete")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")
        
        self.waitUntilSyncServerUserSignin() {
            
            let cloudStorageFileName = "SingleDataUpload"
            let fileUUIDString = UUID.make()
            let fileUUID = NSUUID(UUIDString: fileUUIDString)!
            let fileAttributes = SMSyncAttributes(withUUID: fileUUID, mimeType: "text/plain", andRemoteFileName: cloudStorageFileName)
            
            let strData: NSString = "SingleDataUpload file contents"
            let data = strData.dataUsingEncoding(NSUTF8StringEncoding)
            
            SMSyncServer.session.uploadData(data!, withDataAttributes: fileAttributes)
            
            var tempFiles1:NSArray!
            var tempFiles2:NSArray!

            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == fileUUIDString!)
                
                // NOTE: This is using some internal SMSyncServer knowledge of the location of the temporary file.
                tempFiles1 = FileStorage.filesInHomeDirectory("Documents/" + SMAppConstants.tempDirectory)

                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                
                // File should have been deleted by now. 
                tempFiles2 = FileStorage.filesInHomeDirectory("Documents/" + SMAppConstants.tempDirectory)
                XCTAssert(tempFiles1.count == tempFiles2.count + 1)
                
                self.checkFileSize(fileUUIDString!, size: strData.length) {
                    uploadCompleteCallbackExpectation.fulfill()
                    
                    let fileAttr = SMSyncServer.session.fileStatus(fileUUID)
                    XCTAssert(fileAttr != nil)
                    XCTAssert(!fileAttr!.deleted!)
                }
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    func testThatPNGFileUploadWorks() {
        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Upload Complete")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")

        self.extraServerResponseTime = 60
        let sizeInBytesExpectedOnServer = 917630
        
        self.waitUntilSyncServerUserSignin() {
            
            let file = AppFile.newObjectAndMakeUUID(true)
            file.fileName =  "Kitty.png"
            CoreData.sessionNamed(CoreDataTests.name).saveContext()
            
            // Odd that this has to be in app bundle not testing bundle...
            let url = NSBundle.mainBundle().URLForResource("Kitty", withExtension: "png")
        
            // 12/31/15; When I use "image/png" as the mime type with Google Drive, I get the file size changing (increasing!) when I upload it. Still does this when I use "application/octet-stream". What about when I use a .bin file extension? Yes. That did it. Not the preferred way for Google Drive to behave though. It is not specific to Google Drive, though. I get the increased file size just on Node.js.
            // See discussion: http://stackoverflow.com/questions/34517582/how-can-i-prevent-modifications-of-a-png-file-uploaded-using-afnetworking-to-a-n
            // Explicitly putting in the mime type as "application/octet-stream" with AFNetworking doesn't change matters. Explicitly using "image/png" with AFNetworking also results in the same 1.3 MB increased file size.
            // And see https://github.com/AFNetworking/AFNetworking/issues/3252
            // Updating to AFNetworking 3...
            // RESOLUTION: I have now set the COMPRESS_PNG_FILES Build Setting to NO to deal with this.
            
            let fileUUID = NSUUID(UUIDString: file.uuid!)!
            let fileAttributes = SMSyncAttributes(withUUID: fileUUID, mimeType: "image/png", andRemoteFileName: file.fileName!)
            
            SMSyncServer.session.uploadImmutableFile(url!, withFileAttributes: fileAttributes)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file.uuid!)
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                self.checkFileSize(file.uuid!, size: sizeInBytesExpectedOnServer) {
                    uploadCompleteCallbackExpectation.fulfill()
                    
                    let fileAttr = SMSyncServer.session.fileStatus(fileUUID)
                    XCTAssert(fileAttr != nil)
                    XCTAssert(!fileAttr!.deleted!)
                }
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    func testThatTwoFileUploadWorks() {
        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Upload Complete")
        let singleUploadExpectation1 = self.expectationWithDescription("Upload Complete1")
        let singleUploadExpectation2 = self.expectationWithDescription("Upload Complete2")

        self.waitUntilSyncServerUserSignin() {
            
            let fileName1 = "TwoFileUpload1"
            let (file1, fileSizeBytes1) = self.createFile(withName: fileName1)
            let file1UUID = NSUUID(UUIDString: file1.uuid!)!
            let fileAttributes1 = SMSyncAttributes(withUUID: file1UUID, mimeType: "text/plain", andRemoteFileName: fileName1)
            
            SMSyncServer.session.uploadImmutableFile(file1.url(), withFileAttributes: fileAttributes1)
            
            let fileName2 = "TwoFileUpload2"
            let (file2, fileSizeBytes2) = self.createFile(withName: fileName2)
            let file2UUID = NSUUID(UUIDString: file2.uuid!)!
            let fileAttributes2 = SMSyncAttributes(withUUID: file2UUID, mimeType: "text/plain", andRemoteFileName: fileName2)
            
            SMSyncServer.session.uploadImmutableFile(file2.url(), withFileAttributes: fileAttributes2)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file1.uuid!)
                singleUploadExpectation1.fulfill()
            }
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file2.uuid!)
                singleUploadExpectation2.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 2)
                // This double call to the server to check file size is inefficient, but not a big deal here.
                self.checkFileSize(file1.uuid!, size: fileSizeBytes1) {
                    self.checkFileSize(file2.uuid!, size: fileSizeBytes2) {
                    
                        let fileAttr1 = SMSyncServer.session.fileStatus(file1UUID)
                        XCTAssert(fileAttr1 != nil)
                        XCTAssert(!fileAttr1!.deleted!)
                        
                        let fileAttr2 = SMSyncServer.session.fileStatus(file2UUID)
                        XCTAssert(fileAttr2 != nil)
                        XCTAssert(!fileAttr2!.deleted!)
                    
                        uploadCompleteCallbackExpectation.fulfill()
                    }
                }
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    // Call uploadImmutableFile for a file, then call it again for the same uuid but new file, then commit. Only the second file should actually be uploaded.
    func testThatOneFileWithUpdateUploadWorks() {
        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Upload Complete")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")

        self.waitUntilSyncServerUserSignin() {
            
            let fileName = "TwoFileUpdateUpload1"
            let (file1, _) = self.createFile(withName: fileName)
            let fileUUID = NSUUID(UUIDString: file1.uuid!)!
            let fileAttributes = SMSyncAttributes(withUUID: fileUUID, mimeType: "text/plain", andRemoteFileName: fileName)
            
            SMSyncServer.session.uploadImmutableFile(file1.url(), withFileAttributes: fileAttributes)
            
            let fileContents:NSString = "TwoFileUpdateUpload2 abcdefg"
            let fileSizeBytes = fileContents.length
            
            let url = FileStorage.urlOfItem("TwoFileUpdateUpload2")
            do {
                try fileContents.writeToURL(url, atomically: true, encoding: NSASCIIStringEncoding)
            } catch {
                XCTFail("Failed to write file: \(error)!")
            }
            
            // This is not violating the immutable characteristic of the uploadImmutableFile method because the contents of the file at the above URL haven't changed. Rather, a new file (different URL) is given with the same UUID.
            
            SMSyncServer.session.uploadImmutableFile(url, withFileAttributes: fileAttributes)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file1.uuid!)
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                self.checkFileSize(file1.uuid!, size: fileSizeBytes) {

                    let fileAttr = SMSyncServer.session.fileStatus(fileUUID)
                    XCTAssert(fileAttr != nil)
                    XCTAssert(!fileAttr!.deleted!)

                    uploadCompleteCallbackExpectation.fulfill()
                }
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    // Initiate the upload of a file with a commit, and then on the heels of that, do second, with another commit. Expect that (a) the first should complete, and then (b) the second should complete immediately after. 
    // TODO: Set up expectations to ensure that this doesn't kick off multiple concurrent commits (such concurrent commits would be an error).
    func testThatTwoSeriesFileUploadWorks() {
        let uploadCompleteCallbackExpectation1 = self.expectationWithDescription("Upload1 Complete")
        let uploadCompleteCallbackExpectation2 = self.expectationWithDescription("Upload2 Complete")
        let singleUploadExpectation1 = self.expectationWithDescription("Upload Complete1")
        let singleUploadExpectation2 = self.expectationWithDescription("Upload Complete2")

        self.waitUntilSyncServerUserSignin() {
            
            let fileName1 = "TwoSeriesFileUpload1"
            let (file1, fileSize1) = self.createFile(withName: fileName1)
            let fileAttributes = SMSyncAttributes(withUUID: NSUUID(UUIDString: file1.uuid!)!, mimeType: "text/plain", andRemoteFileName: fileName1)
            
            SMSyncServer.session.uploadImmutableFile(file1.url(), withFileAttributes: fileAttributes)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file1.uuid!)
                singleUploadExpectation1.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                self.checkFileSize(file1.uuid!, size: fileSize1) {
                    uploadCompleteCallbackExpectation1.fulfill()
                }
            }
            
            SMSyncServer.session.commit()
            
            let fileName2 = "TwoSeriesFileUpload2"
            let (file2, fileSize2) = self.createFile(withName: "TwoSeriesFileUpload2")
            let fileAttributes2 = SMSyncAttributes(withUUID: NSUUID(UUIDString: file2.uuid!)!, mimeType: "text/plain", andRemoteFileName: fileName2)

            SMSyncServer.session.uploadImmutableFile(file2.url(), withFileAttributes: fileAttributes2)
            
            self.singleUploadCallbacks.append() { uuid in
                singleUploadExpectation2.fulfill()
                XCTAssert(uuid.UUIDString == file2.uuid!)
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                self.checkFileSize(file2.uuid!, size: fileSize2) {
                    uploadCompleteCallbackExpectation2.fulfill()
                }
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    // A test case that uploads a new file, then after that is fully completed and the file has been saved into cloud storage, uploads an update to the file. (This is a relevant test case because at least with Google Drive, these two situations are handled differently with the REST/API for Google Drive). NOTE: This test was *very* worthwhile. It uncovered two significant bugs in the iOS client side, and one on the server side (that crashed the server).
    func testThatUpdateAfterUploadWorks() {
        let uploadCompleteCallbackExpectation1 = self.expectationWithDescription("Upload1 Complete")
        let uploadCompleteCallbackExpectation2 = self.expectationWithDescription("Upload2 Complete")
        let singleUploadExpectation1 = self.expectationWithDescription("Upload Complete1")
        let singleUploadExpectation2 = self.expectationWithDescription("Upload Complete2")

        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            
            let fileName = "FirstFileUpload1"
            let (file1, firstFileSize) = self.createFile(withName: fileName)
            
            let fileAttributes = SMSyncAttributes(withUUID: NSUUID(UUIDString: file1.uuid!)!, mimeType: "text/plain", andRemoteFileName: fileName)
            
            SMSyncServer.session.uploadImmutableFile(file1.url(), withFileAttributes: fileAttributes)
            
            self.singleUploadCallbacks.append() { uuid in
                singleUploadExpectation1.fulfill()
                XCTAssert(uuid.UUIDString == file1.uuid!)
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                self.checkFileSize(file1.uuid!, size: firstFileSize) {
                    uploadCompleteCallbackExpectation1.fulfill()
                }
            }
            
            SMSyncServer.session.commit()
            
            let fileContents:NSString = "FirstFileUpload.Update smigma"
            let secondFileSize = fileContents.length
            
            let url = FileStorage.urlOfItem("FirstFileUpload2")
            do {
                try fileContents.writeToURL(url, atomically: true, encoding: NSASCIIStringEncoding)
            } catch {
                XCTFail("Failed to write file: \(error)!")
            }
            
            SMSyncServer.session.uploadImmutableFile(url, withFileAttributes: fileAttributes)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file1.uuid!)
                singleUploadExpectation2.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                self.checkFileSize(file1.uuid!, size: secondFileSize) {
                    uploadCompleteCallbackExpectation2.fulfill()
                }
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    // Similar to the above, but the update is done after the first commit fully completes.
    func testThatUpdateFullyAfterUploadWorks() {
        let uploadCompleteCallbackExpectation1 = self.expectationWithDescription("Upload1 Complete")
        let uploadCompleteCallbackExpectation2 = self.expectationWithDescription("Upload2 Complete")
        let singleUploadExpectation1 = self.expectationWithDescription("Upload Complete1")
        let singleUploadExpectation2 = self.expectationWithDescription("Upload Complete2")

        self.extraServerResponseTime = 60

        self.waitUntilSyncServerUserSignin() {
            
            let fileName = "FirstFileUpload3"
            let (file1, firstFileSize) = self.createFile(withName: fileName)
            
            let fileAttributes = SMSyncAttributes(withUUID: NSUUID(UUIDString: file1.uuid!)!, mimeType: "text/plain", andRemoteFileName: fileName)
            
            SMSyncServer.session.uploadImmutableFile(file1.url(), withFileAttributes: fileAttributes)
            
            func secondUpload() {
                
                let fileContents:NSString = "FirstFileUpload2.Update smigma"
                let secondFileSize = fileContents.length
                
                let url = FileStorage.urlOfItem("FirstFileUpload4")
                do {
                    try fileContents.writeToURL(url, atomically: true, encoding: NSASCIIStringEncoding)
                } catch {
                    XCTFail("Failed to write file: \(error)!")
                }
                
                SMSyncServer.session.uploadImmutableFile(url, withFileAttributes: fileAttributes)
                
                self.singleUploadCallbacks.append() { uuid in
                    XCTAssert(uuid.UUIDString == file1.uuid!)
                    singleUploadExpectation2.fulfill()
                }
            
                self.commitCompleteCallbacks.append() { numberUploads in
                    XCTAssert(numberUploads == 1)
                    self.checkFileSize(file1.uuid!, size: secondFileSize) {
                        uploadCompleteCallbackExpectation2.fulfill()
                    }
                }
                
                SMSyncServer.session.commit()
            }
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file1.uuid!)
                singleUploadExpectation1.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                self.checkFileSize(file1.uuid!, size: firstFileSize) {
                    uploadCompleteCallbackExpectation1.fulfill()
                    secondUpload()
                }
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    //MARK: "Normal" (non-recovery) tests that are expected to fail. These are use cases where the SMSyncServer client/app user does something wrong, and should fail. E.g., the SMSyncServer user client/app is still in debugging/testing and needs to be fixed.
    
    // I was going to add a test: Same UUID, different cloud file name, in same upload batch. However, uploadImmutableFile won't let this test happen. So, not going to worry about it for now.
    
    // Two different UUID's, but the same remote file name for each.
    func testThatTwoFileSameNameUploadFails() {
        let errorCallbackExpectation = self.expectationWithDescription("Error Callback")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete1")

        self.waitUntilSyncServerUserSignin() {
            
            let remoteFileName = "SameFileNameUpload"
            let (file1, _) = self.createFile(withName: "SameFileNameUpload1")
            let fileAttributes1 = SMSyncAttributes(withUUID: NSUUID(UUIDString: file1.uuid!)!, mimeType: "text/plain", andRemoteFileName: remoteFileName)

            SMSyncServer.session.uploadImmutableFile(file1.url(), withFileAttributes: fileAttributes1)
            
            let (file2, _) = self.createFile(withName: "SameFileNameUpload2")
            let fileAttributes2 = SMSyncAttributes(withUUID: NSUUID(UUIDString: file2.uuid!)!, mimeType: "text/plain", andRemoteFileName: remoteFileName)

            SMSyncServer.session.uploadImmutableFile(file2.url(), withFileAttributes: fileAttributes2)
            
            // TODO: What is the expectation for this commit? Should it cause the first file to be committed? i.e., the second upload throws an error. What should following operations, such as commmit do?
            SMSyncServer.session.commit()
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file1.uuid!)
                singleUploadExpectation.fulfill()
            }
            
            self.errorCallbacks.append() {
                SMSyncServer.session.cleanupFile(NSUUID(UUIDString: file1.uuid!)!)
                SMSyncServer.session.cleanupFile(NSUUID(UUIDString: file2.uuid!)!)
                
                CoreData.sessionNamed(CoreDataTests.name).removeObject(file1)
                CoreData.sessionNamed(CoreDataTests.name).removeObject(file2)
                CoreData.sessionNamed(CoreDataTests.name).saveContext()
                
                SMSyncServer.session.resetFromError()
                
                // A call to cleanup is necessary so we can do the next test.
                SMServerAPI.session.cleanup() { error in
                    XCTAssert(error == nil)
                    errorCallbackExpectation.fulfill()
                }
            }
        }
        
        self.waitForExpectations()
    }
    
    // First two files have different remote names, but the third has one of the remote names of one of the first two. This is to test on the server that we can remove multiple outbound file changes in a cleanup.
    func testThatThreeFileSameNameUploadFails() {
        let errorCallbackExpectation = self.expectationWithDescription("Error Callback")
        let singleUploadExpectation1 = self.expectationWithDescription("Upload Complete")
        let singleUploadExpectation2 = self.expectationWithDescription("Upload Complete")

        self.waitUntilSyncServerUserSignin() {
            
            let fileName1 = "NotSameFileNameUpload"
            let (file1, _) = self.createFile(withName: fileName1)
            let fileAttributes1 = SMSyncAttributes(withUUID: NSUUID(UUIDString: file1.uuid!)!, mimeType: "text/plain", andRemoteFileName: fileName1)

            SMSyncServer.session.uploadImmutableFile(file1.url(), withFileAttributes: fileAttributes1)
            
            let fileName2 = "SameFileNameUpload"
            let (file2, _) = self.createFile(withName: fileName2)
            let fileAttributes2 = SMSyncAttributes(withUUID: NSUUID(UUIDString: file2.uuid!)!, mimeType: "text/plain", andRemoteFileName: fileName2)
            
            SMSyncServer.session.uploadImmutableFile(file2.url(), withFileAttributes: fileAttributes2)

            let (file3, _) = self.createFile(withName: "SameFileNameUpload2")
            let fileAttributes3 = SMSyncAttributes(withUUID: NSUUID(UUIDString: file3.uuid!)!, mimeType: "text/plain", andRemoteFileName: fileName2)

            SMSyncServer.session.uploadImmutableFile(file3.url(), withFileAttributes: fileAttributes3)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file1.uuid!)
                singleUploadExpectation1.fulfill()
            }
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file2.uuid!)
                singleUploadExpectation2.fulfill()
            }
            
            // TODO: Again, what is our expectation here?
            SMSyncServer.session.commit()
            
            self.errorCallbacks.append() {
                SMSyncServer.session.cleanupFile(NSUUID(UUIDString: file1.uuid!)!)
                SMSyncServer.session.cleanupFile(NSUUID(UUIDString: file2.uuid!)!)
                SMSyncServer.session.cleanupFile(NSUUID(UUIDString: file3.uuid!)!)
                
                CoreData.sessionNamed(CoreDataTests.name).removeObject(file1)
                CoreData.sessionNamed(CoreDataTests.name).removeObject(file2)
                CoreData.sessionNamed(CoreDataTests.name).removeObject(file3)
                CoreData.sessionNamed(CoreDataTests.name).saveContext()
                
                SMSyncServer.session.resetFromError()
                
                // A call to cleanup is necessary so we can do the next test.
                SMServerAPI.session.cleanup() { error in
                    XCTAssert(error == nil)
                    errorCallbackExpectation.fulfill()
                }
            }
        }
        
        self.waitForExpectations()
    }
    
    // Upload a file in the normal way, then, later, attempt to upload a file with the same UUID but different cloud name.
    func testThatUploadWithSameUUIDButDifferentCloudNameFails() {
        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Upload Complete")
        let errorCallbackExpectation = self.expectationWithDescription("Error callback")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")

        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            
            let fileName = "FirstFileUpload6"
            let (file1, firstFileSize) = self.createFile(withName: fileName)
            
            let fileAttributes1 = SMSyncAttributes(withUUID: NSUUID(UUIDString: file1.uuid!)!, mimeType: "text/plain", andRemoteFileName: fileName)
            
            SMSyncServer.session.uploadImmutableFile(file1.url(), withFileAttributes: fileAttributes1)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file1.uuid!)
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                self.checkFileSize(file1.uuid!, size: firstFileSize) {
                    uploadCompleteCallbackExpectation.fulfill()
                }
            }
            
            SMSyncServer.session.commit()
            
            let fileContents:NSString = "FirstFileUpload.Update smigma"
            
            let fileName2 = "FirstFileUpload7"
            let url = FileStorage.urlOfItem(fileName2)
            do {
                try fileContents.writeToURL(url, atomically: true, encoding: NSASCIIStringEncoding)
            } catch {
                XCTFail("Failed to write file: \(error)!")
            }
            
            let fileAttributes2 = SMSyncAttributes(withUUID: NSUUID(UUIDString: file1.uuid!)!, mimeType: "text/plain", andRemoteFileName: fileName2)

            // Gotta put the error callback before the uploadImmutableFile in this case because the error callback is thrown from uploadImmutableFile.
            self.errorCallbacks.append() {
                // Since this error doesn't occur during an actual upload we don't need to do a resetFromError or a cleanup.
                /*
                SMSyncServer.session.resetFromError()
                
                // A call to cleanup is necessary so we can do the next test.
                SMServerAPI.session.cleanup() { error in
                    XCTAssert(error == nil)
                    errorCallbackExpectation.fulfill()
                }
                */
                
                errorCallbackExpectation.fulfill()
            }
            
            SMSyncServer.session.uploadImmutableFile(url, withFileAttributes: fileAttributes2)

            // This won't do anything as there are no additional files needing to be uploaded given the error.
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    // Upload a file in the normal way, then, later, attempt to upload a file with the same same cloud name but different UUID.
    func testThatUploadWithDifferentUUIDButSameCloudNameFails() {
        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Upload Complete")
        let errorCallbackExpectation = self.expectationWithDescription("Error callback")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")

        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            
            let fileName1 = "DifferentUUIDButSameCloudName"
            let (file1, firstFileSize) = self.createFile(withName: fileName1)
            let fileAttributes1 = SMSyncAttributes(withUUID: NSUUID(UUIDString: file1.uuid!)!, mimeType: "text/plain", andRemoteFileName: fileName1)
            
            SMSyncServer.session.uploadImmutableFile(file1.url(), withFileAttributes: fileAttributes1)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file1.uuid!)
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                self.checkFileSize(file1.uuid!, size: firstFileSize) {
                    uploadCompleteCallbackExpectation.fulfill()
                }
            }
            
            SMSyncServer.session.commit()
            
            let fileName2 = "DifferentUUIDButSameCloudName2"
            let (file2, _) = self.createFile(withName: fileName2)
            let fileAttributes2 = SMSyncAttributes(withUUID: NSUUID(UUIDString: file2.uuid!)!, mimeType: "text/plain", andRemoteFileName: fileName1)
            
            self.errorCallbacks.append() {
                // file2 was in error and didn't get uploaded-- need to clean it up.
                SMSyncServer.session.cleanupFile(NSUUID(UUIDString: file2.uuid!)!)
                
                CoreData.sessionNamed(CoreDataTests.name).removeObject(file2)
                CoreData.sessionNamed(CoreDataTests.name).saveContext()
                
                SMSyncServer.session.resetFromError()
                
                // A call to cleanup is necessary so we can do the next test.
                SMServerAPI.session.cleanup() { error in
                    XCTAssert(error == nil)
                    errorCallbackExpectation.fulfill()
                }
            }
            
            SMSyncServer.session.uploadImmutableFile(file2.url(), withFileAttributes: fileAttributes2)

            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    //MARK: Recovery tests
    
    // App crashes mid-way through the upload operation. This is a relevant test because it seems likely that the network can be lost by the mobile device during an extended upload.
    // This test will intentionally fail the first time through (due to the app crash), and you have to manually run it a 2nd time to get it to succeed.
    // I am leaving this test normally disabled in XCTests in Xcode so that I can enable it, manually run it as needed, and then disable it again.
    func testThatRecoveryAfterAppCrashWorks() {
        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Upload Completion Callback")
        let progressCallbackExpected = self.expectationWithDescription("Progress Callback")

        // Don't need to wait for sign in the second time through because the delay for recovery is imposed in SMSyncServer appLaunchSetup-- after sign in, the recovery will automatically start.
        if Upload.recoveryAfterAppCrash.boolValue {
            Upload.recoveryAfterAppCrash.boolValue = false
            
            let singleUploadExpectation = self.expectationWithDescription("Upload Callback")

            self.waitUntilSyncServerUserSignin() {

                // This will fake a failure on .UploadFiles, but it will have really succeeded on uploading the file.
                SMTest.session.doClientFailureTest(.UploadFiles)
                
                let fileName = "RecoveryAfterAppCrash"
                let (file, _) = self.createFile(withName: fileName)
                let fileAttributes = SMSyncAttributes(withUUID: NSUUID(UUIDString: file.uuid!)!, mimeType: "text/plain", andRemoteFileName: fileName)

                SMSyncServer.session.uploadImmutableFile(file.url(), withFileAttributes: fileAttributes)
                
                self.singleUploadCallbacks.append() { uuid in
                    XCTAssert(uuid.UUIDString == file.uuid!)
                    singleUploadExpectation.fulfill()
                }
            
                self.progressCallbacks.append() { progress in
                    XCTAssertEqual(progress, SMSyncServerRecovery.Upload)
                    progressCallbackExpected.fulfill()

                    SMTest.session.crash()
                    // NOTE: XCTFail has no actual effect on the running app itself. I.e., it doesn't cause the app to crash or fail. I need the app to crash because otherwise, the recovery process will proceed within fileChangesRecovery() in SMUploadFiles.
                    // XCTFail(msg)
                }
            
                SMSyncServer.session.commit()
            }
        }
        else {
            // 2nd run of test.
            
            self.progressCallbacks.append() { progress in
                XCTAssertEqual(progress, SMSyncServerRecovery.Upload)
                progressCallbackExpected.fulfill()
            }
            
            // 2nd run we don't get an upload because the upload actually happened the first time around.
            /*
            self.singleUploadCallbacks.append() { uuid in
                singleUploadExpectation.fulfill()
            }*/
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssertEqual(numberUploads, 1)
                // NOTE: We could do a file size check here, after the commit succeeds, but I'd have to persist the file size across app launches, or go back to the file and see what size it is.
                uploadCompleteCallbackExpectation.fulfill()
            }
        }
        
        self.waitForExpectations()
    }
    
    // When we get network access back, should treat this like an app launch and see if we need to do recovery. To test this: Create a new test case where, when we get network access back, do the same procedure/method as during app launch. The test case will consist of something like testThatRecoveryAfterAppCrashWorks(): Start an upload, cause it to fail because of network loss, then immediately bring the network back online and do the recovery.
    func testThatRecoveryFromNetworkLossWorks() {
        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Upload Complete")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")

        self.extraServerResponseTime = 30

        self.waitUntilSyncServerUserSignin() {
            
            let fileName = "NetworkRecovery1"
            let (file, fileSizeBytes) = self.createFile(withName: fileName)
            let fileAttributes = SMSyncAttributes(withUUID: NSUUID(UUIDString: file.uuid!)!, mimeType: "text/plain", andRemoteFileName: fileName)
            
            SMSyncServer.session.uploadImmutableFile(file.url(), withFileAttributes: fileAttributes)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file.uuid!)
                Network.session().debugNetworkOff = true
                singleUploadExpectation.fulfill()
            }
            
            Network.session().connectionStateCallbacks.addTarget!(self, withSelector: "recoveryFromNetworkLossAction")
            
            // I'm not putting a recovery expectation in here because internally this recovery goes through a number of steps -- it waits to try to make sure the operation doesn't switch from Not Started to In Progress.
            self.singleProgressCallback =  { progress in
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                self.checkFileSize(file.uuid!, size: fileSizeBytes) {
                    uploadCompleteCallbackExpectation.fulfill()
                }
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
    
    // The error is client side, determined by context.
    func doTestThatUploadRecoveryWorks(inContext context:SMTestContext, withFileName fileName: String) {
        // [1]. Have to create the expectations before the wait for signin too. Or XCTests doesn't know there are expectations to wait for.
        let progressCallbackExpectation = self.expectationWithDescription("Progress Callback")
        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Upload Complete")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")

        // [1].
        self.waitUntilSyncServerUserSignin() {
            
            SMTest.session.doClientFailureTest(context)
            
            let (file, fileSizeInBytes) = self.createFile(withName: fileName)
            let fileAttributes = SMSyncAttributes(withUUID: NSUUID(UUIDString: file.uuid!)!, mimeType: "text/plain", andRemoteFileName: fileName)

            SMSyncServer.session.uploadImmutableFile(file.url(), withFileAttributes: fileAttributes)

            var progressExpected:SMSyncServerRecovery!
            
            switch (context) {
            case .Lock, .GetFileIndex, .UploadFiles:
                progressExpected = .Upload
                
            case .OutboundTransfer:
                progressExpected = .MayHaveCommitted
            }
            
            self.progressCallbacks.append() { progress in
                XCTAssertEqual(progress, progressExpected)
                XCTAssertTrue(!self.doneRecovery)
                self.doneRecovery = true
                progressCallbackExpectation.fulfill()
            }
            
            self.singleUploadCallbacks.append() { (uuid:NSUUID) in
                XCTAssert(uuid.UUIDString == file.uuid!)
                
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssertTrue(self.doneRecovery)
                XCTAssert(numberUploads == 1)
                self.checkFileSize(file.uuid!, size: fileSizeInBytes) {
                    uploadCompleteCallbackExpectation.fulfill()
                }
            }
            
            SMSyncServer.session.commit()
            
            // Expecting that we'll get delegate callback on progress and then delegate callback on uploadComplete, without an error.
        }
        
        self.waitForExpectations()
    }
    
    func testThatStartFileChangesRecoveryWorks() {
        self.doTestThatUploadRecoveryWorks(inContext: .Lock, withFileName: SMTestContext.Lock.rawValue)
    }
    
    func testThatGetFileIndexRecoveryWorks() {
        self.doTestThatUploadRecoveryWorks(inContext: .GetFileIndex, withFileName: SMTestContext.GetFileIndex.rawValue)
    }
    
    func testThatUploadFilesRecoveryWorks() {
        self.doTestThatUploadRecoveryWorks(inContext: .UploadFiles, withFileName: SMTestContext.UploadFiles.rawValue)
    }
    
    func testThatCommitChangesRecoveryWorks() {
        self.doTestThatUploadRecoveryWorks(inContext: .OutboundTransfer, withFileName: SMTestContext.OutboundTransfer.rawValue + "A")
    }
    
    // TODO: [3]. Create a test case where we exceed the number of successive times we can try to recover from the same error (.FileChangesRecovery).
    
    // Server-side detailed testing following from CommitChanges
    func testThatServerCommitChangesTestCaseWorks() {
        // The client goes through two calls to the progress delegate method in the recovery process for SMSyncServerConstants.dbTcCommitChanges.
        
        let context = SMTestContext.OutboundTransfer
        let serverTestCase = SMServerConstants.dbTcCommitChanges
        let fileName = context.rawValue + String(serverTestCase)
        var numberRecoverySteps = 0
        
        let progressCallbackExpectation1 = self.expectationWithDescription("Progress Callback1")
        let progressCallbackExpectation2 = self.expectationWithDescription("Progress Callback2")
        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Upload Complete")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")

        // [1].
        self.waitUntilSyncServerUserSignin() {

            SMTest.session.serverDebugTest = serverTestCase
            
            let (file, fileSizeInBytes) = self.createFile(withName: fileName)
            let fileAttributes = SMSyncAttributes(withUUID: NSUUID(UUIDString: file.uuid!)!, mimeType: "text/plain", andRemoteFileName: fileName)

            SMSyncServer.session.uploadImmutableFile(file.url(), withFileAttributes: fileAttributes)
            
            self.progressCallbacks.append() { progress in
                // So we don't get the error test cases on the server again
                SMTest.session.serverDebugTest = nil
        
                XCTAssertEqual(progress, SMSyncServerRecovery.MayHaveCommitted)
                numberRecoverySteps++
                XCTAssertEqual(numberRecoverySteps, 1)
                progressCallbackExpectation1.fulfill()
            }
            
            self.progressCallbacks.append() { progress in
                XCTAssertEqual(progress, SMSyncServerRecovery.Upload)
                numberRecoverySteps++
                XCTAssertEqual(numberRecoverySteps, 2)
                progressCallbackExpectation2.fulfill()
            }
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file.uuid!)
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssertEqual(numberRecoverySteps, 2)
                XCTAssert(numberUploads == 1)
                self.checkFileSize(file.uuid!, size: fileSizeInBytes) {
                    uploadCompleteCallbackExpectation.fulfill()
                }
            }
            
            SMSyncServer.session.commit()
            
            // Expecting that we'll get delegate callback on progress and then delegate callback on uploadComplete, without an error.
        }
        
        self.waitForExpectations()
    }
    
    // Server-side detailed testing of Transfer Recovery.
    func transferRecovery(transferTestCase serverTestCase:Int) {
        
        self.extraServerResponseTime = 30
        
        let context = SMTestContext.OutboundTransfer
        let fileName = context.rawValue + String(serverTestCase)
        var numberRecoverySteps = 0
        
        let progressCallbackExpectation1 = self.expectationWithDescription("Progress Callback1")
        let progressCallbackExpectation2 = self.expectationWithDescription("Progress Callback2")

        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Upload Complete")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")

        // [1].
        self.waitUntilSyncServerUserSignin() {

            SMTest.session.serverDebugTest = serverTestCase
            
            let (file, fileSizeInBytes) = self.createFile(withName: fileName)
            let fileAttributes = SMSyncAttributes(withUUID: NSUUID(UUIDString: file.uuid!)!, mimeType: "text/plain", andRemoteFileName: fileName)

            SMSyncServer.session.uploadImmutableFile(file.url(), withFileAttributes: fileAttributes)

            self.progressCallbacks.append() { progress in
                // So we don't get the error test cases on the server again
                SMTest.session.serverDebugTest = nil
        
                // Due to the way the recovery works internally, it will go through a .MayHaveCommitted progress state first.
                XCTAssertEqual(progress, SMSyncServerRecovery.MayHaveCommitted)
                numberRecoverySteps++
                XCTAssertEqual(numberRecoverySteps, 1)
                progressCallbackExpectation1.fulfill()
            }
            
            self.progressCallbacks.append() { progress in
                XCTAssertEqual(progress, SMSyncServerRecovery.OutboundTransfer)
                numberRecoverySteps++
                XCTAssertEqual(numberRecoverySteps, 2)
                progressCallbackExpectation2.fulfill()
            }
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file.uuid!)
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssertEqual(numberRecoverySteps, 2)
                XCTAssert(numberUploads == 1)
                self.checkFileSize(file.uuid!, size: fileSizeInBytes) {
                    uploadCompleteCallbackExpectation.fulfill()
                }
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    // Simulate a failure while transferring files to cloud storage.
    func testThatServerSendFilesTestCaseWorks() {
        self.transferRecovery(transferTestCase: SMServerConstants.dbTcTransferFiles)
    }
    
    // Simulate a failure while updating collections on the server during transfer to cloud storage-- this is important so that we know that the log scheme I'm using on the server can enable recovery.
    func testThatServerSendFilesUpdateOneFileTestCaseWorks() {
        self.transferRecovery(transferTestCase: SMServerConstants.dbTcSendFilesUpdate)
    }
    
    // Same as previous, but with two files. This test will cause a failure immediately after the first file is transferred to cloud storage.
    func testThatServerSendFilesUpdateTwoFilesTestCaseWorks() {
        
        self.extraServerResponseTime = 30
        
        let serverTestCase = SMServerConstants.dbTcSendFilesUpdate
        let context = SMTestContext.OutboundTransfer
        let fileName1 = context.rawValue + String(serverTestCase) + "A"
        let fileName2 = context.rawValue + String(serverTestCase) + "B"

        var numberRecoverySteps = 0
        
        let progressCallbackExpectation1 = self.expectationWithDescription("Progress Callback1")
        let progressCallbackExpectation2 = self.expectationWithDescription("Progress Callback2")

        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Upload Complete")
        let uploadExpectation1 = self.expectationWithDescription("Upload1 Complete")
        let uploadExpectation2 = self.expectationWithDescription("Upload2 Complete")

        // [1].
        self.waitUntilSyncServerUserSignin() {

            SMTest.session.serverDebugTest = serverTestCase
            
            let (file1, fileSizeInBytes1) = self.createFile(withName: fileName1)
            let fileAttributes1 = SMSyncAttributes(withUUID: NSUUID(UUIDString: file1.uuid!)!, mimeType: "text/plain", andRemoteFileName: fileName1)

            SMSyncServer.session.uploadImmutableFile(file1.url(), withFileAttributes: fileAttributes1)
            
            let (file2, fileSizeInBytes2) = self.createFile(withName: fileName2)
            let fileAttributes2 = SMSyncAttributes(withUUID: NSUUID(UUIDString: file2.uuid!)!, mimeType: "text/plain", andRemoteFileName: fileName2)

            SMSyncServer.session.uploadImmutableFile(file2.url(), withFileAttributes: fileAttributes2)

            self.progressCallbacks.append() { progress in
                // So we don't get the error test cases on the server again
                SMTest.session.serverDebugTest = nil
        
                // Due to the way the recovery works internally, it will go through a .MayHaveCommitted progress state first.
                XCTAssertEqual(progress, SMSyncServerRecovery.MayHaveCommitted)
                numberRecoverySteps++
                XCTAssertEqual(numberRecoverySteps, 1)
                progressCallbackExpectation1.fulfill()
            }
            
            self.progressCallbacks.append() { progress in
                XCTAssertEqual(progress, SMSyncServerRecovery.OutboundTransfer)
                numberRecoverySteps++
                XCTAssertEqual(numberRecoverySteps, 2)
                progressCallbackExpectation2.fulfill()
            }
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file1.uuid!)
                uploadExpectation1.fulfill()
            }
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file2.uuid!)
                uploadExpectation2.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssertEqual(numberRecoverySteps, 2)
                XCTAssert(numberUploads == 2)
                self.checkFileSize(file1.uuid!, size: fileSizeInBytes1) {
                    self.checkFileSize(file2.uuid!, size: fileSizeInBytes2) {
                        uploadCompleteCallbackExpectation.fulfill()
                    }
                }
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
}
