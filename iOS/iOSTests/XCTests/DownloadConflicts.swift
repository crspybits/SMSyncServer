//
//  DownloadConflicts.swift
//  Tests
//
//  Created by Christopher Prince on 4/25/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import XCTest
// The @testable notation lets us access "internal" classes within our project.
@testable import Tests
@testable import SMSyncServer
import SMCoreLib

class DownloadConflicts: BaseClass {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    // MARK: Download deletion conflicts

    func setupDownloadDeletionLocalUploadConflict(fileName fileName: String, keepConflicting:Bool, handleConflict:(conflict: SMSyncServerConflict,
            testFile:TestFile)->()) {
        let singleUploadExpectation = self.expectationWithDescription("Single Upload Complete")
        let commitCompleteUpload = self.expectationWithDescription("Commit Complete Upload")
        let idleExpectationUpload = self.expectationWithDescription("Idle Upload")

        let deletionExpectation = self.expectationWithDescription("Single Deletion Complete")
        let commitCompleteDelete = self.expectationWithDescription("Commit Complete Download")
        let idleExpectationDeletion = self.expectationWithDescription("Idle Deletion")

        let idleAfterShouldDeleteFiles = self.expectationWithDescription("Idle After Should Delete")
        
        var commitCompleteUpload2:XCTestExpectation?
        var upload2:XCTestExpectation?
        
        if keepConflicting {
            commitCompleteUpload2 = self.expectationWithDescription("Commit Complete Upload")
            upload2 = self.expectationWithDescription("Commit Complete Upload")
        }

        self.extraServerResponseTime = 60
        
        self.waitUntilSyncServerUserSignin() {
            var testFile = TestBasics.session.createTestFile(fileName)
            
            self.uploadFiles([testFile], uploadExpectations: [singleUploadExpectation], commitComplete: commitCompleteUpload, idleExpectation: idleExpectationUpload) {
                // Upload done: Now idle
                
                let newFileContents = "Some new file contents"

                self.deleteFiles([testFile], deletionExpectation: deletionExpectation, commitCompleteExpectation: commitCompleteDelete, idleExpectation: idleExpectationDeletion) {
                    // Deletion done: Now idle.
                    
                    SMSyncServer.session.resetMetaData(forUUID: testFile.uuid, resetType: .Undelete)
                    
                    // Our current situation is that, when we next do a sync with the server, there will be a download-deletion.
                    // To generate a LocalUpload conflict, we need to now do an upload for this file.
                    let newFileContentsData = newFileContents.dataUsingEncoding(NSUTF8StringEncoding)
                    SMSyncServer.session.uploadData(newFileContentsData!, withDataAttributes: testFile.attr)
                    
                    self.shouldResolveDeletionConflicts.append() { conflicts in
                        Log.msg("shouldResolveDeletionConflicts")
                        
                        XCTAssert(conflicts.count == 1)
                        let (uuid, conflict) = conflicts[0]
                        XCTAssert(conflict.conflictType == .FileUpload)
                        XCTAssert(uuid.UUIDString == testFile.uuidString)
                        
                        let fileAttr = SMSyncServer.session.localFileStatus(testFile.uuid)
                        XCTAssert(fileAttr != nil)
                        
                        // With conflicts, initially before resolving the conflict, the file will be marked as deleted. This will change if the client decides to resolve the conflict by keeping the update.
                        XCTAssert(fileAttr!.deleted!)
                        
                        handleConflict(conflict:conflict, testFile:testFile)
                    }
                    
                    // The .Idle callback gets called first
                    self.idleCallbacks.append() {
                        if keepConflicting {
                            idleAfterShouldDeleteFiles.fulfill()
                        }
                        else {
                            // Delete conflicting client operations.
                            
                            let attr = SMSyncServer.session.localFileStatus(testFile.uuid)
                            Assert.If(attr == nil, thenPrintThisString: "Yikes: Nil attr")
                            Assert.If(!attr!.deleted!, thenPrintThisString: "Yikes: not deleted!")
                            
                            TestBasics.session.checkForFileOnServer(testFile.uuidString) { fileExists in
                                XCTAssert(!fileExists)
                                testFile.remove()
                                idleAfterShouldDeleteFiles.fulfill()
                            }
                        }
                    }
                    
                    if keepConflicting {
                        self.singleUploadCallbacks.append() { uuid in
                            XCTAssert(uuid.UUIDString == testFile.uuidString)
                            upload2!.fulfill()
                        }
            
                        // Followed by the commit complete callback.
                        self.commitCompleteCallbacks.append() { numberUploads in
                            XCTAssert(numberUploads == 1)
                            testFile.sizeInBytes = newFileContents.characters.count
                            self.checkFileSizes([testFile]) {
                                let attr = SMSyncServer.session.localFileStatus(testFile.uuid)
                                Assert.If(attr == nil, thenPrintThisString: "Yikes: Nil attr")
                                Assert.If(attr!.deleted!, thenPrintThisString: "Yikes: deleted!")
                                commitCompleteUpload2!.fulfill()
                            }
                        }
                    }
                    
                    SMSyncServer.session.commit()
                }
            }
        }
        
        self.waitForExpectations()
    }

    func testThatDownloadDeletionLocalUploadResolveConflictByKeepWorks() {
        // We should get the idle callback in setupDownloadDeletionLocalUploadConflict after ack is called, so shouldn't need another expectation here. We won't get idle callback, and that fulfilled expectation, without the call to ack() below.
        
        self.setupDownloadDeletionLocalUploadConflict(fileName: "DownloadDeletionLocalUploadResolveConflictByKeep", keepConflicting: true) { conflict, testFile in
            conflict.resolveConflict(resolution: .KeepConflictingClientOperations)
        }
    }

    func testThatDownloadDeletionLocalUploadResolveConflictByDeleteWorks() {
        self.setupDownloadDeletionLocalUploadConflict(fileName: "DownloadDeletionLocalUploadResolveConflictByDelete", keepConflicting: false) { conflict, testFile in
            conflict.resolveConflict(resolution: .DeleteConflictingClientOperations)
            // Need to assert that, after all the server operations have completed, the file has been deleted on server, and is marked as deleted in sync server meta data.
        }
    }
    
    func setupDownloadDeletionTwoLocalUploadConflicts(fileName fileName: String, keepConflicting:Bool, handleConflicts:(conflicts:[(SMSyncServerConflict, TestFile)])->()) {
        let singleUploadExpectation1 = self.expectationWithDescription("Single Upload Complete1")
        let singleUploadExpectation2 = self.expectationWithDescription("Single Upload Complete2")

        let commitCompleteUpload = self.expectationWithDescription("Commit Complete Upload")
        let idleExpectationUpload = self.expectationWithDescription("Idle Upload")

        let deletionExpectation = self.expectationWithDescription("Single Deletion Complete")

        let commitCompleteDelete = self.expectationWithDescription("Commit Complete Download")
        let idleExpectationDeletion = self.expectationWithDescription("Idle Deletion")

        let idleAfterShouldDeleteFiles = self.expectationWithDescription("Idle After Should Delete")
        
        var commitCompleteUpload2:XCTestExpectation?
        var upload2:XCTestExpectation?
        var upload3:XCTestExpectation?
        
        if keepConflicting {
            commitCompleteUpload2 = self.expectationWithDescription("Commit Complete Upload")
            upload2 = self.expectationWithDescription("Commit Complete Upload")
            upload3 = self.expectationWithDescription("Commit Complete Upload")
        }

        self.extraServerResponseTime = 60
        
        self.waitUntilSyncServerUserSignin() {
            var testFile1 = TestBasics.session.createTestFile(fileName + ".1")
            var testFile2 = TestBasics.session.createTestFile(fileName + ".2")
           
            self.uploadFiles([testFile1, testFile2], uploadExpectations: [singleUploadExpectation1, singleUploadExpectation2], commitComplete: commitCompleteUpload, idleExpectation: idleExpectationUpload) {
                // Upload done: Now idle
                
                let newFileContents = "Some new file contents"

                self.deleteFiles([testFile1, testFile2], deletionExpectation: deletionExpectation, commitCompleteExpectation: commitCompleteDelete, idleExpectation: idleExpectationDeletion) {
                    // Deletion done: Now idle.
                    
                    SMSyncServer.session.resetMetaData(forUUID: testFile1.uuid, resetType: .Undelete)
                    SMSyncServer.session.resetMetaData(forUUID: testFile2.uuid, resetType: .Undelete)
                    
                    // Our current situation is that, when we next do a sync with the server, there will be a download-deletion.
                    // To generate a LocalUpload conflict, we need to now do an upload for this file.
                    let newFileContentsData = newFileContents.dataUsingEncoding(NSUTF8StringEncoding)
                    SMSyncServer.session.uploadData(newFileContentsData!, withDataAttributes: testFile1.attr)
                    SMSyncServer.session.uploadData(newFileContentsData!, withDataAttributes: testFile2.attr)
                    
                    self.shouldResolveDeletionConflicts.append() { conflicts in
                        XCTAssert(conflicts.count == 2)
                        
                        let (uuid1, conflict1) = conflicts[0]
                        XCTAssert(conflict1.conflictType == .FileUpload)
                        XCTAssert(uuid1.UUIDString == testFile1.uuidString)
                        
                        let fileAttr1 = SMSyncServer.session.localFileStatus(testFile1.uuid)
                        XCTAssert(fileAttr1 != nil)
                        
                        // With conflicts, initially before resolving the conflict, the file will be marked as deleted. This will change if the client decides to resolve the conflict by keeping the update.
                        XCTAssert(fileAttr1!.deleted!)
                        
                        let (uuid2, conflict2) = conflicts[1]
                        XCTAssert(conflict2.conflictType == .FileUpload)
                        XCTAssert(uuid2.UUIDString == testFile2.uuidString)
                        
                        let fileAttr2 = SMSyncServer.session.localFileStatus(testFile2.uuid)
                        XCTAssert(fileAttr2 != nil)
                        
                        // Deleted. As above.
                        XCTAssert(fileAttr2!.deleted!)
                        
                        handleConflicts(conflicts: [(conflict1, testFile1), (conflict2, testFile2)])
                    }
                    
                    // The .Idle callback gets called first
                    self.idleCallbacks.append() {
                        if keepConflicting {
                            idleAfterShouldDeleteFiles.fulfill()
                        }
                        else {
                            // Delete conflicting client operations.
                            
                            let attr1 = SMSyncServer.session.localFileStatus(testFile1.uuid)
                            Assert.If(attr1 == nil, thenPrintThisString: "Yikes: Nil attr")
                            Assert.If(!attr1!.deleted!, thenPrintThisString: "Yikes: not deleted!")

                            let attr2 = SMSyncServer.session.localFileStatus(testFile2.uuid)
                            Assert.If(attr2 == nil, thenPrintThisString: "Yikes: Nil attr")
                            Assert.If(!attr2!.deleted!, thenPrintThisString: "Yikes: not deleted!")
                            
                            TestBasics.session.checkForFileOnServer(testFile1.uuidString) { fileExists in
                                XCTAssert(!fileExists)
                                testFile1.remove()
                                
                                TestBasics.session.checkForFileOnServer(testFile2.uuidString) { fileExists in
                                    XCTAssert(!fileExists)
                                    testFile2.remove()
                                    
                                    idleAfterShouldDeleteFiles.fulfill()
                                }
                            }
                        }
                    }
                    
                    if keepConflicting {
                        self.singleUploadCallbacks.append() { uuid in
                            XCTAssert(uuid.UUIDString == testFile1.uuidString)
                            upload2!.fulfill()
                        }
                        
                        self.singleUploadCallbacks.append() { uuid in
                            XCTAssert(uuid.UUIDString == testFile2.uuidString)
                            upload3!.fulfill()
                        }
                        
                        // Followed by the commit complete callback.
                        self.commitCompleteCallbacks.append() { numberUploads in
                            XCTAssert(numberUploads == 2)
                            testFile1.sizeInBytes = newFileContents.characters.count
                            testFile2.sizeInBytes = newFileContents.characters.count

                            self.checkFileSizes([testFile1, testFile2]) {
                                let attr1 = SMSyncServer.session.localFileStatus(testFile1.uuid)
                                Assert.If(attr1 == nil, thenPrintThisString: "Yikes: Nil attr")
                                Assert.If(attr1!.deleted!, thenPrintThisString: "Yikes: deleted!")
                                
                                let attr2 = SMSyncServer.session.localFileStatus(testFile2.uuid)
                                Assert.If(attr2 == nil, thenPrintThisString: "Yikes: Nil attr")
                                Assert.If(attr2!.deleted!, thenPrintThisString: "Yikes: deleted!")
                                
                                commitCompleteUpload2!.fulfill()
                            }
                        }
                    }
                    
                    SMSyncServer.session.commit()
                }
            }
        }
        
        self.waitForExpectations()
    }
    
    func testThatDownloadDeletionTwoLocalUploadsResolveConflictByKeepWorks() {
        // We should get the idle callback in setupDownloadDeletionLocalUploadConflict after ack is called, so shouldn't need another expectation here. We won't get idle callback, and that fulfilled expectation, without the call to ack() below.
        
        self.setupDownloadDeletionTwoLocalUploadConflicts(fileName: "DownloadDeletionTwoLocalUploadsResolveConflictByKeep", keepConflicting: true) { conflicts in
            for (conflict, _) in conflicts {
                conflict.resolveConflict(resolution: .KeepConflictingClientOperations)
            }
        }
    }

    func testThatDownloadDeletionTwoLocalUploadsResolveConflictByDeleteWorks() {
        self.setupDownloadDeletionTwoLocalUploadConflicts(fileName: "DownloadDeletionTwoLocalUploadsResolveConflictByDelete", keepConflicting: false) { conflicts in
            for (conflict, _) in conflicts {
                conflict.resolveConflict(resolution: .DeleteConflictingClientOperations)
            }
        }
    }
    
    // MARK: Download file conflicts
    
    func setupDownloadFileLocalUploadDeletionConflict(fileName fileName: String, keepConflicting:Bool, handleConflict:(conflict: SMSyncServerConflict,
            testFile:TestFile)->()) {
        let singleUploadExpectation1 = self.expectationWithDescription("Single Upload Complete1")
        let commitCompleteUpload1 = self.expectationWithDescription("Commit Complete Upload1")
        let idleExpectationUpload1 = self.expectationWithDescription("Idle Upload1")

        let singleUploadExpectation2 = self.expectationWithDescription("Single Upload Complete2")
        let commitCompleteUpload2 = self.expectationWithDescription("Commit Complete Upload2")
        let idleExpectationUpload2 = self.expectationWithDescription("Idle Upload2")

        let idleExpectationDeletion = self.expectationWithDescription("Idle Deletion")

        let idleAfterDeleteFiles = self.expectationWithDescription("Idle After Should Delete")
        let commitCompleteUpload3 = self.expectationWithDescription("Commit Complete Upload3")
        let singleDownloadExpectation = self.expectationWithDescription("Single Download")
       
        var commitCompleteDelete:XCTestExpectation?
        var deletionExpectation:XCTestExpectation?
        
        if keepConflicting {
            commitCompleteDelete = self.expectationWithDescription("Commit Complete Download")
            deletionExpectation = self.expectationWithDescription("Single Deletion Complete")
        }

        self.extraServerResponseTime = 90
        
        self.waitUntilSyncServerUserSignin() {
            let testFile = TestBasics.session.createTestFile(fileName)
            
            self.uploadFiles([testFile], uploadExpectations: [singleUploadExpectation1], commitComplete: commitCompleteUpload1, idleExpectation: idleExpectationUpload1) {
                // Upload done: Now idle
                
                // This second upload of the same file will force an increment of the version number of the file on the server.
                self.uploadFiles([testFile], uploadExpectations: [singleUploadExpectation2], commitComplete: commitCompleteUpload2, idleExpectation: idleExpectationUpload2) {
                    // Upload done: Now idle
                    
                    // Decrement the version locally.
                    SMSyncServer.session.resetMetaData(forUUID: testFile.uuid, resetType: .DecrementVersion)
                    
                    // Our current situation is that because the server has a higher version number, with the next sync, we'll do a download-file.
                    
                    // That download file will need the following two callbacks:
                    self.singleDownload.append() { (downloadedFile:NSURL, downloadedFileAttr: SMSyncAttributes) in
                        Log.msg("singleDownload callback")

                        XCTAssert(downloadedFileAttr.uuid.UUIDString == testFile.uuidString)
                        let filesAreTheSame = SMFiles.compareFiles(file1: testFile.url, file2: downloadedFile)
                        XCTAssert(filesAreTheSame)
                        singleDownloadExpectation.fulfill()
                    }
            
                    self.singleInboundTransferCallback = { numberOperations in
                        Log.msg("singleInboundTransferCallback: For download")

                        XCTAssert(numberOperations >= 1)

                        self.checkFileSizes([testFile]) {
                            let attr1 = SMSyncServer.session.localFileStatus(testFile.uuid)
                            Assert.If(attr1 == nil, thenPrintThisString: "Yikes: Nil attr")
                            Assert.If(attr1!.deleted!, thenPrintThisString: "Yikes: deleted!")
                            commitCompleteUpload3.fulfill()
                        }
                    }
                    
                    self.shouldResolveDownloadConflicts.append() { conflicts in
                        Log.msg("shouldResolveDownloadConflicts")
                        XCTAssert(conflicts.count == 1)
                        let (_, attr, conflict) = conflicts[0]
                        XCTAssert(conflict.conflictType == .UploadDeletion)
                        XCTAssert(attr.uuid.UUIDString == testFile.uuidString)
                        
                        let fileAttr = SMSyncServer.session.localFileStatus(testFile.uuid)
                        XCTAssert(fileAttr != nil)
                        
                        // At this point in execution, we have a pending file-download and a pending upload-deletion (i.e., these two combined are what is generating the conflict). Since the upload-deletion hasn't completed yet, the local file meta data hasn't been marked as deleted.
                        XCTAssert(!fileAttr!.deleted!)
                        
                        handleConflict(conflict:conflict, testFile:testFile)
                    }
                    
                    // Instead of calling SMSyncServer.session.sync(), I'll do a deleteFiles (which creates an upload-deletion), which will call a commit, which will internally do a sync. The .Idle callback will be dealt with inside of the .deleteFiles call. The download, however, will occur first.

                    self.deleteFiles([testFile], deletionExpectation: deletionExpectation, commitCompleteExpectation: commitCompleteDelete, idleExpectation: idleExpectationDeletion) {
                        // Deletion done: Now idle.
                        
                        Log.msg("deleteFiles done")

                        var expectThatFileExists:Bool
                        if keepConflicting {
                            // Keep conflicting client operation: File should be deleted.
                            expectThatFileExists = false
                        }
                        else {
                            // Delete conflicting client operations: File should exist.
                            expectThatFileExists = true
                        }
                        
                        let attr = SMSyncServer.session.localFileStatus(testFile.uuid)
                        Assert.If(attr == nil, thenPrintThisString: "Yikes: Nil attr")
                        Assert.If(attr!.deleted! != !expectThatFileExists, thenPrintThisString: "Yikes: unexpected expectThatFileExists value")
                        
                        TestBasics.session.checkForFileOnServer(testFile.uuidString) { fileExists in
                            XCTAssert(fileExists == expectThatFileExists)
                            idleAfterDeleteFiles.fulfill()
                        }
                    }
                }
            }
        }
        
        self.waitForExpectations()
    }
    
    func testThatDownloadFileLocalUploadDeletionResolveConflictByKeepWorks() {
        self.setupDownloadFileLocalUploadDeletionConflict(fileName: "DownloadFileLocalUploadDeletionResolveConflictByKeep", keepConflicting: true) { conflict, testFile in
            conflict.resolveConflict(resolution: .KeepConflictingClientOperations)
        }
    }
    
    func testThatDownloadFileLocalUploadDeletionResolveConflictByDeleteWorks() {
        self.setupDownloadFileLocalUploadDeletionConflict(fileName: "DownloadFileLocalUploadDeletionResolveConflictByDelete", keepConflicting: false) { conflict, testFile in
            conflict.resolveConflict(resolution: .DeleteConflictingClientOperations)
        }
    }

    func setupDownloadFileLocalUploadConflict(fileName fileName: String, keepConflicting:Bool, handleConflict:(conflict: SMSyncServerConflict,
            url:NSURL, testFile:TestFile)->()) {
        let singleUploadExpectation1 = self.expectationWithDescription("Single Upload Complete1")
        let commitCompleteUpload1 = self.expectationWithDescription("Commit Complete Upload1")
        let idleExpectationUpload1 = self.expectationWithDescription("Idle Upload1")

        let singleUploadExpectation2 = self.expectationWithDescription("Single Upload Complete2")
        let commitCompleteUpload2 = self.expectationWithDescription("Commit Complete Upload2")
        let idleExpectationUpload2 = self.expectationWithDescription("Idle Upload2")

        let idleAfterUpload = self.expectationWithDescription("Idle After Upload")
        let commitCompleteUpload3 = self.expectationWithDescription("Commit Complete Upload3")
        let singleDownloadExpectation = self.expectationWithDescription("Single Download")
       
        let idleExpectationUpload3 = self.expectationWithDescription("Idle Upload3")
        var commitComplete:XCTestExpectation?
        var uploadExpectation:XCTestExpectation?
        
        if keepConflicting {
            commitComplete = self.expectationWithDescription("Commit Complete Upload")
            uploadExpectation = self.expectationWithDescription("Single Upload Complete")
        }

        self.extraServerResponseTime = 90
        
        self.waitUntilSyncServerUserSignin() {
            var testFile = TestBasics.session.createTestFile(fileName)
            
            self.uploadFiles([testFile], uploadExpectations: [singleUploadExpectation1], commitComplete: commitCompleteUpload1, idleExpectation: idleExpectationUpload1) {
                // Upload done: Now idle
                
                let downloadNewFileContents = "New file contents for download"
                let uploadNewFileContents = "*** NEW FILE contents for upload"
                
                let downloadData = downloadNewFileContents.dataUsingEncoding(NSUTF8StringEncoding)!
                if !downloadData.writeToURL(testFile.url, atomically: true) {
                    Assert.badMojo(alwaysPrintThisString: "Could not write to file")
                }
                
                // Upload the file with contents: downloadNewFileContents
                testFile.sizeInBytes = downloadNewFileContents.characters.count
                
                // This second upload of the same file will force an increment of the version number of the file on the server.
                self.uploadFiles([testFile], uploadExpectations: [singleUploadExpectation2], commitComplete: commitCompleteUpload2, idleExpectation: idleExpectationUpload2) {
                    // Upload done: Now idle
                    
                    // Decrement the version locally.
                    SMSyncServer.session.resetMetaData(forUUID: testFile.uuid, resetType: .DecrementVersion)
                    
                    // Our current situation is that because the server has a higher version number, with the next sync, we'll do a download-file (contents: downloadNewFileContents).
                    
                    // That download file will need the following two callbacks:
                    self.singleDownload.append() { (downloadedFile:NSURL, downloadedFileAttr: SMSyncAttributes) in
                        Log.msg("singleDownload callback")

                        XCTAssert(downloadedFileAttr.uuid.UUIDString == testFile.uuidString)
                        let filesAreTheSame = SMFiles.compareFile(file: downloadedFile, andString: downloadNewFileContents)
                        XCTAssert(filesAreTheSame)
                        singleDownloadExpectation.fulfill()
                    }
            
                    self.singleInboundTransferCallback = { numberOperations in
                        Log.msg("singleInboundTransferCallback: For download")

                        XCTAssert(numberOperations >= 1)
                        commitCompleteUpload3.fulfill()
                    }
                    
                    self.shouldResolveDownloadConflicts.append() { conflicts in
                        Log.msg("shouldResolveDownloadConflicts")
                        XCTAssert(conflicts.count == 1)
                        let (url, attr, conflict) = conflicts[0]
                        XCTAssert(conflict.conflictType == .FileUpload)
                        XCTAssert(attr.uuid.UUIDString == testFile.uuidString)
                        
                        let fileAttr = SMSyncServer.session.localFileStatus(testFile.uuid)
                        XCTAssert(fileAttr != nil)
                        
                        // At this point in execution, we have a pending file-download and a pending file-upload (i.e., these two combined are generating the conflict).
                        XCTAssert(!fileAttr!.deleted!)
                        
                        handleConflict(conflict:conflict, url:url, testFile:testFile)
                    }
                    
                    // Instead of calling SMSyncServer.session.sync(), I'll do an uploadFiles (which creates a file-upload), which will call a commit, which will internally do a sync. The .Idle callback will be dealt with inside of the .uploadFiles call. The download, however, will occur first.
                    let uploadExpectationArray:[XCTestExpectation]? = uploadExpectation == nil ? nil : [uploadExpectation!]
                    
                    let uploadData = uploadNewFileContents.dataUsingEncoding(NSUTF8StringEncoding)!
                    if !uploadData.writeToURL(testFile.url, atomically: true) {
                        Assert.badMojo(alwaysPrintThisString: "Could not write to file")
                    }
                    
                    testFile.sizeInBytes = uploadNewFileContents.characters.count
                    
                    // Create the conflicting file-upload with contents: uploadNewFileContents
                    self.uploadFiles([testFile], uploadExpectations: uploadExpectationArray, commitComplete: commitComplete, idleExpectation: idleExpectationUpload3) {
                    
                        let attr = SMSyncServer.session.localFileStatus(testFile.uuid)
                        Assert.If(attr == nil, thenPrintThisString: "Yikes: Nil attr")
                        Assert.If(attr!.deleted!, thenPrintThisString: "Yikes: unexpected deleted value")
                        
                        var expectedFileContents:String
                        if keepConflicting {
                            expectedFileContents = uploadNewFileContents
                        }
                        else {
                            expectedFileContents = downloadNewFileContents
                        }
                        
                        let filesAreTheSame = SMFiles.compareFile(file: testFile.url, andString: expectedFileContents)
                        XCTAssert(filesAreTheSame)
                        
                        TestBasics.session.checkForFileOnServer(testFile.uuidString) { fileExists in
                            XCTAssert(fileExists)
                            idleAfterUpload.fulfill()
                        }
                    }
                }
            }
        }
        
        self.waitForExpectations()
    }
    
    func testThatDownloadFileLocalUploadResolveConflictByKeepWorks() {
        self.setupDownloadFileLocalUploadConflict(fileName: "DownloadFileLocalUploadResolveConflictByKeep", keepConflicting: true) {
            (conflict, downloadURL, testFile) in
            
            conflict.resolveConflict(resolution: .KeepConflictingClientOperations)
        }
    }
    
    func testThatDownloadFileLocalUploadResolveConflictByDeleteWorks() {
        self.setupDownloadFileLocalUploadConflict(fileName: "DownloadFileLocalUploadResolveConflictByDelete", keepConflicting: false) {
            (conflict, downloadURL, testFile) in
            
            // Why is there no other shouldSaveDownloads so far in the DownloadConflicts tests?
            /*
            self.shouldSaveDownloads.append() { downloadedFiles, ack in
                XCTAssert(downloadedFiles.count == 1)
                let (downloadedFileURL, downloadedFileAttr) = downloadedFiles[0]
                expectShouldSaveDownloads.fulfill()
                ack()
            }*/
            // AHA! There will be no shouldSaveDownloads callbacks here -- because the download conflict will be the final callback. If you resolve the conflict by using .DeleteConflictingClientOperations, you have to, during the syncServerShouldResolveDownloadConflicts callback, save the file.
            
            // move file at the downloadURL to the testFile.url
            
            let mgr = NSFileManager.defaultManager()
            
            // Remove existing file first. Otherwise we get an error on moveItemAtURL.
            do {
                try mgr.removeItemAtURL(testFile.url)
            } catch (let err) {
                Log.error("removeItemAtURL: \(err)")
            }

            do {
                try mgr.moveItemAtURL(downloadURL, toURL: testFile.url)
            } catch (let err) {
                let errorString = "moveItemAtURL: \(err)"
                Log.error(errorString)
                XCTFail()
            }
            
            conflict.resolveConflict(resolution: .DeleteConflictingClientOperations)
        }
    }
}
