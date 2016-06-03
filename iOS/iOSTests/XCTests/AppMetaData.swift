//
//  AppMetaData.swift
//  Tests
//
//  Created by Christopher Prince on 5/24/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import XCTest
@testable import SMSyncServer
@testable import Tests
import SMCoreLib

// Having problems equating dictionaries, so made more specialized methods. Methods suggested here: http://stackoverflow.com/questions/32365654/how-do-i-compare-two-dictionaries-in-swift did not work. The data from the constant dictionary seems to be quite different from that we get back from the JSON conversion, back from the server-- when I look at it in the debugger.
// Actually, the problem is different. The problem is that numbers uploaded come back down from the server as strings.

class AppMetaData: BaseClass {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func downloadOneFile(testFile:TestFile, dictionaryTest:(dict:[String:AnyObject])->(Bool)) {

        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Commit Complete")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")
        let singleDownloadExpectation = self.expectationWithDescription("Single Download")
        let allDownloadsCompleteExpectation = self.expectationWithDescription("All Downloads Complete")
        let idleExpectation1 = self.expectationWithDescription("Idle1")
        let idleExpectation2 = self.expectationWithDescription("Idle2")

        var numberDownloads = 0
        
        self.extraServerResponseTime = 360
        
        self.waitUntilSyncServerUserSignin() {
            try! SMSyncServer.session.uploadImmutableFile(testFile.url, withFileAttributes: testFile.attr)
            
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
                
                XCTAssert(downloadedFileAttr.appMetaData != nil)
                
                XCTAssert(dictionaryTest(dict: downloadedFileAttr.appMetaData!))
                
                singleDownloadExpectation.fulfill()
            }
            
            self.shouldSaveDownloads.append() { downloadedFiles, ack in
                XCTAssert(numberDownloads == 1)
                XCTAssert(downloadedFiles.count == 1)
                
                let (_, attr) = downloadedFiles[0]
                XCTAssert(attr.appMetaData != nil)
                
                XCTAssert(dictionaryTest(dict: attr.appMetaData!))

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
                let attr = SMSyncServer.session.localFileStatus(testFile.uuid)
                XCTAssert(attr != nil)
                XCTAssert(attr!.appMetaData != nil)
                
                XCTAssert(dictionaryTest(dict: attr!.appMetaData!))
                
                idleExpectation2.fulfill()
            }
            
            try! SMSyncServer.session.commit()
        }
        
        self.waitForExpectations()
    }
    
    // Upload a file with simple meta data attribute; one key, and download that file. Assert that you can get the attributes on download both from the download delegate and the SMSyncServer call to get attributes.
    func testThatUploadDownloadOfOneFileWithSimpleMetaDataWorks() {
        var testFile = TestBasics.session.createTestFile(
            "UploadDownloadOfOneFileWithSimpleMetaData")
        testFile.appMetaData = ["Test" : "Attribute"]
        self.downloadOneFile(testFile) { dict in
            if let str = dict["Test"] as? String {
                return str == "Attribute"
            }
            else {
                return false
            }
        }
    }
    
    // More complicated dictionary.
    func testThatUploadDownloadOfOneFileWithComplicatedMetaDataWorks() {
        var testFile = TestBasics.session.createTestFile(
            "UploadDownloadOfOneFileWithComplicatedMetaData")
        testFile.appMetaData = [
            "FileType"  : "Image",
            "Fruit"     : ["Apples", "Oranges", "Bananas"],
            "Number"    : 100,
            "Numbers"   : [1, 2, 3, 4, 5],
            "Dictionary" : ["a":"b", "c": "d"]
        ]
        self.downloadOneFile(testFile) { dict in
            let fileType = dict["FileType"] as? String
            let fruit = dict["Fruit"] as? [String]
            let number = dict["Number"] as? String
            let numbers = dict["Numbers"] as? [String]
            let dictionary = dict["Dictionary"] as? [String:String]

            if fileType != nil && fruit != nil && number != nil && numbers != nil && dictionary != nil {
                return fileType! == "Image" &&
                    fruit! == ["Apples", "Oranges", "Bananas"] &&
                    number! == "100" &&
                    numbers! == ["1", "2", "3", "4", "5"] &&
                    dictionary! == ["a":"b", "c": "d"]
            }
            else {
                return false
            }
        }
    }
    
    func testThatSecondUploadCanChangeMetaData() {
        let uploadExpectation1 = self.expectationWithDescription("Upload1")
        let commitComplete1 = self.expectationWithDescription("Commit Complete1")
        let idleExpectation1 = self.expectationWithDescription("Idle1")
        let uploadExpectation2 = self.expectationWithDescription("Upload2")
        let commitComplete2 = self.expectationWithDescription("Commit Complete2")
        let idleExpectation2 = self.expectationWithDescription("Idle2")
        
        var testFile = TestBasics.session.createTestFile(
            "SecondUploadCanChangeMetaData")
        testFile.appMetaData = ["Test" : 1]
        
        self.waitUntilSyncServerUserSignin() {
            self.uploadFiles([testFile], uploadExpectations: [uploadExpectation1], commitComplete: commitComplete1, idleExpectation: idleExpectation1) {
                let attr = SMSyncServer.session.localFileStatus(testFile.uuid)
                XCTAssert(attr != nil)
                XCTAssert(attr!.appMetaData != nil)
                
                let number = SMExtras.getIntFromDictValue(attr!.appMetaData!["Test"])
                XCTAssert(number == 1)
                
                testFile.appMetaData = ["Test" : 2]
                
                 self.uploadFiles([testFile], uploadExpectations: [uploadExpectation2], commitComplete: commitComplete2, idleExpectation: idleExpectation2) {
                    let attr = SMSyncServer.session.localFileStatus(testFile.uuid)
                    XCTAssert(attr != nil)
                    XCTAssert(attr!.appMetaData != nil)
                    
                    let number = SMExtras.getIntFromDictValue(attr!.appMetaData!["Test"])
                    XCTAssert(number == 2)
                }
            }
        }
        
        self.waitForExpectations()  
    }
}
