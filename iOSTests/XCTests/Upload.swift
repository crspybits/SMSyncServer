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
    
    override func setUp() {
        super.setUp()
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
        let idleExpectation = self.expectationWithDescription("Idle")
        
        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            let testFile = TestBasics.session.createTestFile("SingleFileUpload")
            
            SMSyncServer.session.uploadImmutableFile(testFile.url, withFileAttributes: testFile.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile.uuidString)
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(testFile.uuidString, size: testFile.sizeInBytes) {
                    let fileAttr = SMSyncServer.session.localFileStatus(testFile.uuid)
                    XCTAssert(fileAttr != nil)
                    XCTAssert(!fileAttr!.deleted!)
                
                    uploadCompleteCallbackExpectation.fulfill()
                }
            }
            
            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation.fulfill()
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    func testThatSingleTemporaryFileUploadWorks() {
        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Upload Complete")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")
        let idleExpectation = self.expectationWithDescription("Idle")

        self.waitUntilSyncServerUserSignin() {
            let testFile = TestBasics.session.createTestFile("SingleTemporaryFileUpload")
            
            SMSyncServer.session.uploadTemporaryFile(testFile.url, withFileAttributes: testFile.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile.uuidString)
                
                // Test for file existence so later testing for non-existence makes sense.
                XCTAssert(FileStorage.itemExists(testFile.fileName))
                
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                
                // File should have been deleted by now.
                XCTAssert(!FileStorage.itemExists(testFile.fileName))
                
                let fileAttr = SMSyncServer.session.localFileStatus(testFile.uuid)
                XCTAssert(fileAttr != nil)
                XCTAssert(!fileAttr!.deleted!)
                
                TestBasics.session.checkFileSize(testFile.uuidString, size: testFile.sizeInBytes) {
                    uploadCompleteCallbackExpectation.fulfill()
                }
            }
            
            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation.fulfill()
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    func testThatSingleDataUploadWorks() {
        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Upload Complete")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")
        let idleExpectation = self.expectationWithDescription("Idle")
        
        self.extraServerResponseTime = 30

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
                
                TestBasics.session.checkFileSize(fileUUIDString!, size: strData.length) {
                    uploadCompleteCallbackExpectation.fulfill()
                    
                    let fileAttr = SMSyncServer.session.localFileStatus(fileUUID)
                    XCTAssert(fileAttr != nil)
                    XCTAssert(!fileAttr!.deleted!)
                }
            }
            
            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation.fulfill()
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    func testThatPNGFileUploadWorks() {
        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Upload Complete")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")
        let idleExpectation = self.expectationWithDescription("Idle")

        self.extraServerResponseTime = 60
        let sizeInBytesExpectedOnServer = 917630
        
        self.waitUntilSyncServerUserSignin() {
            
            let file = AppFile.newObjectAndMakeUUID(true)
            file.fileName =  "Kitty.png"
            let remoteFileName = "KittyKat.png" // avoiding remote name conflict with download test case.
            CoreData.sessionNamed(CoreDataTests.name).saveContext()
            
            // Odd that this has to be in app bundle not testing bundle...
            let url = SMRelativeLocalURL(withRelativePath: "Kitty.png", toBaseURLType: .MainBundle)!
        
            // 12/31/15; When I use "image/png" as the mime type with Google Drive, I get the file size changing (increasing!) when I upload it. Still does this when I use "application/octet-stream". What about when I use a .bin file extension? Yes. That did it. Not the preferred way for Google Drive to behave though. It is not specific to Google Drive, though. I get the increased file size just on Node.js.
            // See discussion: http://stackoverflow.com/questions/34517582/how-can-i-prevent-modifications-of-a-png-file-uploaded-using-afnetworking-to-a-n
            // Explicitly putting in the mime type as "application/octet-stream" with AFNetworking doesn't change matters. Explicitly using "image/png" with AFNetworking also results in the same 1.3 MB increased file size.
            // And see https://github.com/AFNetworking/AFNetworking/issues/3252
            // Updating to AFNetworking 3...
            // RESOLUTION: I have now set the COMPRESS_PNG_FILES Build Setting to NO to deal with this.
            // 4/13/16; This lovely issue has raised its head again with Xcode 7.3. Changing the type of file to Data has resolved it again. See https://forums.developer.apple.com/thread/43372
            
            let fileUUID = NSUUID(UUIDString: file.uuid!)!
            let fileAttributes = SMSyncAttributes(withUUID: fileUUID, mimeType: "image/png", andRemoteFileName: remoteFileName)
            
            SMSyncServer.session.uploadImmutableFile(url, withFileAttributes: fileAttributes)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == file.uuid!)
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(file.uuid!, size: sizeInBytesExpectedOnServer) {
                    uploadCompleteCallbackExpectation.fulfill()
                    
                    let fileAttr = SMSyncServer.session.localFileStatus(fileUUID)
                    XCTAssert(fileAttr != nil)
                    XCTAssert(!fileAttr!.deleted!)
                }
            }
            
            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation.fulfill()
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    func testThatTwoFileUploadWorks() {
        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Upload Complete")
        let singleUploadExpectation1 = self.expectationWithDescription("Upload Complete1")
        let singleUploadExpectation2 = self.expectationWithDescription("Upload Complete2")
        let idleExpectation = self.expectationWithDescription("Idle")
        
        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            let testFile1 = TestBasics.session.createTestFile("TwoFileUpload1")
            
            SMSyncServer.session.uploadImmutableFile(testFile1.url, withFileAttributes: testFile1.attr)
            
            let testFile2 = TestBasics.session.createTestFile("TwoFileUpload2")
            
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
                // This double call to the server to check file size is inefficient, but not a big deal here.
                TestBasics.session.checkFileSize(testFile1.uuidString, size: testFile1.sizeInBytes) {
                    TestBasics.session.checkFileSize(testFile2.uuidString, size: testFile2.sizeInBytes) {
                    
                        let fileAttr1 = SMSyncServer.session.localFileStatus(testFile1.uuid)
                        XCTAssert(fileAttr1 != nil)
                        XCTAssert(!fileAttr1!.deleted!)
                        
                        let fileAttr2 = SMSyncServer.session.localFileStatus(testFile2.uuid)
                        XCTAssert(fileAttr2 != nil)
                        XCTAssert(!fileAttr2!.deleted!)
                    
                        uploadCompleteCallbackExpectation.fulfill()
                    }
                }
            }
            
            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation.fulfill()
            }
            
            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    // Call uploadImmutableFile for a file, then call it again for the same uuid but new file, then commit. Only the second file should actually be uploaded.
    func testThatOneFileWithUpdateUploadWorks() {
        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Upload Complete")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")
        let idleExpectation = self.expectationWithDescription("Idle")

        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            let testFile = TestBasics.session.createTestFile("TwoFileUpdateUpload1")
            
            SMSyncServer.session.uploadImmutableFile(testFile.url, withFileAttributes: testFile.attr)
            
            let fileContents:NSString = "TwoFileUpdateUpload2 abcdefg"
            let fileSizeBytes = fileContents.length
            
            let url = SMRelativeLocalURL(withRelativePath: "TwoFileUpdateUpload2", toBaseURLType: .DocumentsDirectory)!
            
            do {
                try fileContents.writeToURL(url, atomically: true, encoding: NSASCIIStringEncoding)
            } catch {
                XCTFail("Failed to write file: \(error)!")
            }
            
            // This is not violating the immutable characteristic of the uploadImmutableFile method because the contents of the file at the above URL haven't changed. Rather, a new file (different URL) is given with the same UUID.
            
            SMSyncServer.session.uploadImmutableFile(url, withFileAttributes: testFile.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile.uuidString)
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(testFile.uuidString, size: fileSizeBytes) {

                    let fileAttr = SMSyncServer.session.localFileStatus(testFile.uuid)
                    XCTAssert(fileAttr != nil)
                    XCTAssert(!fileAttr!.deleted!)

                    uploadCompleteCallbackExpectation.fulfill()
                }
            }
            
            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation.fulfill()
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
        let idleExpectation = self.expectationWithDescription("Idle")

        self.extraServerResponseTime = 30

        self.waitUntilSyncServerUserSignin() {
            
            let testFile1 = TestBasics.session.createTestFile("TwoSeriesFileUpload1")
            
            SMSyncServer.session.uploadImmutableFile(testFile1.url, withFileAttributes: testFile1.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile1.uuidString)
                singleUploadExpectation1.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(testFile1.uuidString, size: testFile1.sizeInBytes) {
                    uploadCompleteCallbackExpectation1.fulfill()
                }
            }
            
            SMSyncServer.session.commit()
            
            let testFile2 = TestBasics.session.createTestFile("TwoSeriesFileUpload2")

            SMSyncServer.session.uploadImmutableFile(testFile2.url, withFileAttributes: testFile2.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                singleUploadExpectation2.fulfill()
                XCTAssert(uuid.UUIDString == testFile2.uuidString)
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(testFile2.uuidString, size: testFile2.sizeInBytes) {
                    uploadCompleteCallbackExpectation2.fulfill()
                }
            }
            
            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation.fulfill()
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
        let idleExpectation = self.expectationWithDescription("Idle")

        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            
            let testFile = TestBasics.session.createTestFile("FirstFileUpload1")
            
            SMSyncServer.session.uploadImmutableFile(testFile.url, withFileAttributes: testFile.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                singleUploadExpectation1.fulfill()
                XCTAssert(uuid.UUIDString == testFile.uuidString)
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(testFile.uuidString, size: testFile.sizeInBytes) {
                    uploadCompleteCallbackExpectation1.fulfill()
                }
            }
            
            SMSyncServer.session.commit()
            
            let fileContents:NSString = "FirstFileUpload.Update smigma"
            let secondFileSize = fileContents.length
            
            let url = SMRelativeLocalURL(withRelativePath: "FirstFileUpload2", toBaseURLType: .DocumentsDirectory)!
            do {
                try fileContents.writeToURL(url, atomically: true, encoding: NSASCIIStringEncoding)
            } catch {
                XCTFail("Failed to write file: \(error)!")
            }
            
            SMSyncServer.session.uploadImmutableFile(url, withFileAttributes: testFile.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile.uuidString)
                singleUploadExpectation2.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(testFile.uuidString, size: secondFileSize) {
                    uploadCompleteCallbackExpectation2.fulfill()
                }
            }
            
            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation.fulfill()
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
        let idleExpectation1 = self.expectationWithDescription("Idle1")
        let idleExpectation2 = self.expectationWithDescription("Idle2")

        self.extraServerResponseTime = 60

        self.waitUntilSyncServerUserSignin() {
            let testFile = TestBasics.session.createTestFile("FirstFileUpload3")
            
            SMSyncServer.session.uploadImmutableFile(testFile.url, withFileAttributes: testFile.attr)
            
            func secondUpload() {
                
                let fileContents:NSString = "FirstFileUpload2.Update smigma"
                let secondFileSize = fileContents.length
                
                let url = SMRelativeLocalURL(withRelativePath: "FirstFileUpload4", toBaseURLType: .DocumentsDirectory)!
                do {
                    try fileContents.writeToURL(url, atomically: true, encoding: NSASCIIStringEncoding)
                } catch {
                    XCTFail("Failed to write file: \(error)!")
                }
                
                SMSyncServer.session.uploadImmutableFile(url, withFileAttributes: testFile.attr)
                
                self.singleUploadCallbacks.append() { uuid in
                    XCTAssert(uuid.UUIDString == testFile.uuidString)
                    singleUploadExpectation2.fulfill()
                }
            
                self.commitCompleteCallbacks.append() { numberUploads in
                    XCTAssert(numberUploads == 1)
                    TestBasics.session.checkFileSize(testFile.uuidString, size: secondFileSize) {
                        uploadCompleteCallbackExpectation2.fulfill()
                    }
                }
                
                // let idleExpectation = self.expectationWithDescription("Idle")
                self.idleCallbacks.append() {
                    idleExpectation2.fulfill()
                }
                
                SMSyncServer.session.commit()
            }
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile.uuidString)
                singleUploadExpectation1.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(testFile.uuidString, size: testFile.sizeInBytes) {
                    uploadCompleteCallbackExpectation1.fulfill()
                    secondUpload()
                }
            }
            
            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation1.fulfill()
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
        let idleExpectation = self.expectationWithDescription("Idle")

        self.waitUntilSyncServerUserSignin() {
            
            var testFile1 = TestBasics.session.createTestFile("SameFileNameUpload1.2")
            testFile1.remoteFileName = "SameFileNameUpload1.2"

            SMSyncServer.session.uploadImmutableFile(testFile1.url, withFileAttributes: testFile1.attr)
            
            var testFile2 = TestBasics.session.createTestFile("SameFileNameUpload2.2")
            testFile2.remoteFileName = testFile1.remoteFileName

            SMSyncServer.session.uploadImmutableFile(testFile2.url, withFileAttributes: testFile2.attr)
            
            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation.fulfill()
            }
            
            // TODO: What is the expectation for this commit? Should it cause the first file to be committed? i.e., the second upload throws an error. What should following operations, such as commmit do?
            SMSyncServer.session.commit()
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile1.uuidString)
                singleUploadExpectation.fulfill()
            }
            
            self.errorCallbacks.append() {
                SMSyncServer.session.cleanupFile(testFile1.uuid)
                SMSyncServer.session.cleanupFile(testFile2.uuid)
                
                CoreData.sessionNamed(CoreDataTests.name).removeObject(
                    testFile1.appFile)
                CoreData.sessionNamed(CoreDataTests.name).removeObject(
                    testFile2.appFile)
                CoreData.sessionNamed(CoreDataTests.name).saveContext()
                
                // Cleanup so we can do the next test.
                SMSyncServer.session.resetFromError() { error in
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
        let idleExpectation = self.expectationWithDescription("Idle")

        self.waitUntilSyncServerUserSignin() {
            let testFile1 = TestBasics.session.createTestFile("NotSameFileNameUpload")
            let testFile2 = TestBasics.session.createTestFile("SameFileNameUpload1")
            var testFile3 = TestBasics.session.createTestFile("SameFileNameUpload2")
            testFile3.remoteFileName = testFile2.fileName
            
            SMSyncServer.session.uploadImmutableFile(testFile1.url, withFileAttributes: testFile1.attr)
            SMSyncServer.session.uploadImmutableFile(testFile2.url, withFileAttributes: testFile2.attr)
            SMSyncServer.session.uploadImmutableFile(testFile3.url, withFileAttributes: testFile3.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile1.uuidString)
                singleUploadExpectation1.fulfill()
            }
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile2.uuidString)
                singleUploadExpectation2.fulfill()
            }
            
            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation.fulfill()
            }
            
            // TODO: Again, what is our expectation here?
            SMSyncServer.session.commit()
            
            self.errorCallbacks.append() {
                SMSyncServer.session.cleanupFile(testFile1.uuid)
                SMSyncServer.session.cleanupFile(testFile2.uuid)
                SMSyncServer.session.cleanupFile(testFile3.uuid)
                
                CoreData.sessionNamed(CoreDataTests.name).removeObject(
                    testFile1.appFile)
                CoreData.sessionNamed(CoreDataTests.name).removeObject(
                    testFile2.appFile)
                CoreData.sessionNamed(CoreDataTests.name).removeObject(
                    testFile3.appFile)
                CoreData.sessionNamed(CoreDataTests.name).saveContext()
                
                SMSyncServer.session.resetFromError() { error in
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
        let idleExpectation = self.expectationWithDescription("Idle")

        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            let testFile1 = TestBasics.session.createTestFile("FirstFileUpload6")
            
            SMSyncServer.session.uploadImmutableFile(testFile1.url, withFileAttributes: testFile1.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile1.uuidString)
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(testFile1.uuidString, size: testFile1.sizeInBytes) {
                    uploadCompleteCallbackExpectation.fulfill()
                }
            }
            
            SMSyncServer.session.commit()
            
            let fileContents:NSString = "FirstFileUpload.Update smigma"
            
            let fileName2 = "FirstFileUpload7"
            let url = SMRelativeLocalURL(withRelativePath: fileName2, toBaseURLType: .DocumentsDirectory)!

            do {
                try fileContents.writeToURL(url, atomically: true, encoding: NSASCIIStringEncoding)
            } catch {
                XCTFail("Failed to write file: \(error)!")
            }
            
            let fileAttributes2 = SMSyncAttributes(withUUID: testFile1.uuid, mimeType: "text/plain", andRemoteFileName: fileName2)

            // Gotta put the error callback before the uploadImmutableFile in this case because the error callback is thrown from uploadImmutableFile.
            self.errorCallbacks.append() {
                // Since this error doesn't occur during an actual upload we don't need to do a resetFromError or a cleanup.
                
                errorCallbackExpectation.fulfill()
            }
            
            SMSyncServer.session.uploadImmutableFile(url, withFileAttributes: fileAttributes2)
                        
            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation.fulfill()
            }

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
        let idleExpectation = self.expectationWithDescription("Idle")

        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            let testFile1 = TestBasics.session.createTestFile("DifferentUUIDButSameCloudName")
            
            SMSyncServer.session.uploadImmutableFile(testFile1.url, withFileAttributes: testFile1.attr)
            
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == testFile1.uuidString)
                singleUploadExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(testFile1.uuidString, size: testFile1.sizeInBytes) {
                    uploadCompleteCallbackExpectation.fulfill()
                }
            }
            
            SMSyncServer.session.commit()
            
            var testFile2 = TestBasics.session.createTestFile("DifferentUUIDButSameCloudName2")
            testFile2.remoteFileName = testFile1.fileName
            
            self.errorCallbacks.append() {
                // file2 was in error and didn't get uploaded-- need to clean it up.
                SMSyncServer.session.cleanupFile(testFile2.uuid)
                
                CoreData.sessionNamed(CoreDataTests.name).removeObject(
                    testFile2.appFile)
                CoreData.sessionNamed(CoreDataTests.name).saveContext()
                
                // Cleanup so we can do the next test.
                SMSyncServer.session.resetFromError() { error in
                    XCTAssert(error == nil)
                    errorCallbackExpectation.fulfill()
                }
            }
            
            SMSyncServer.session.uploadImmutableFile(testFile2.url, withFileAttributes: testFile2.attr)
            
            // let idleExpectation = self.expectationWithDescription("Idle")
            self.idleCallbacks.append() {
                idleExpectation.fulfill()
            }

            SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
}
