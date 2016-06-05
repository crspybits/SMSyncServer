//
//  README_Examples.swift
//  Tests
//
//  Created by Christopher Prince on 6/5/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

// These are the examples in the README.md file. Putting them in here so I can run them and make sure my examples work.

import XCTest
@testable import SMSyncServer
import SMCoreLib
@testable import Tests

class README_Examples: BaseClass {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    // operations are the SMSyncServer upload, commit etc.
    func singleFileUpload(fileUUID:NSUUID, fileContents:String, operations:()->()) {
        let uploadCompleteCallbackExpectation = self.expectationWithDescription("Commit Complete")
        let singleUploadExpectation = self.expectationWithDescription("Upload Complete")
        let idleExpectation = self.expectationWithDescription("Idle")
        
        self.extraServerResponseTime = 30
        
        self.waitUntilSyncServerUserSignin() {
            self.singleUploadCallbacks.append() { uuid in
                XCTAssert(uuid.UUIDString == fileUUID.UUIDString)
                singleUploadExpectation.fulfill()
            }

            self.idleCallbacks.append() {
                idleExpectation.fulfill()
            }
            
            self.commitCompleteCallbacks.append() { numberUploads in
                XCTAssert(numberUploads == 1)
                TestBasics.session.checkFileSize(fileUUID.UUIDString, size: fileContents.characters.count) {
                    let fileAttr = SMSyncServer.session.localFileStatus(fileUUID)
                    XCTAssert(fileAttr != nil)
                    XCTAssert(!fileAttr!.deleted!)
                    uploadCompleteCallbackExpectation.fulfill()
                }
            }

            operations()
        }
        
        self.waitForExpectations()
    }
    
    func testThatREADMEUploadImmutableFileWorks() {
        let url = SMRelativeLocalURL(withRelativePath: "READMEUploadImmutableFile", toBaseURLType: .DocumentsDirectory)!
        
        // Just to put some content in the file. This content would, of course, depend on your app.
        let exampleFileContents = "Hello World!"
        try! exampleFileContents.writeToURL(url, atomically: true, encoding: NSUTF8StringEncoding)
        
         // you would normally store this persistently, e.g., in CoreData. The UUID lets you reference the particular file, later, to the SMSyncServer framework.
        let uuid = NSUUID()
        
        let attr = SMSyncAttributes(withUUID: uuid, mimeType: "text/plain", andRemoteFileName: uuid.UUIDString)
        
        self.singleFileUpload(uuid, fileContents: exampleFileContents) { 
            do {
                try SMSyncServer.session.uploadImmutableFile(url, withFileAttributes: attr)
            } catch (let error) {
                print("Yikes: There was an error with uploadImmutableFile: \(error)")
            }
            
            // You could call uploadImmutableFile (or the other upload or deletion methods) any number of times, to queue up a group of files for upload.
            
            // The commit call actually starts the upload process.
            do {
                try SMSyncServer.session.commit()
            } catch (let error) {
                print("Yikes: There was an error with commit: \(error)")
            }
        }
    }
    
    func testThatREADMEUploadTemporaryFileWorks() {
        let url = SMRelativeLocalURL(withRelativePath: "READMEUploadTemporaryFile", toBaseURLType: .DocumentsDirectory)!
        
        // Just to put some content in the file. This content would, of course, depend on your app.
        let exampleFileContents = "Hello World!"
        try! exampleFileContents.writeToURL(url, atomically: true, encoding: NSUTF8StringEncoding)
        
         // you would normally store this persistently, e.g., in CoreData. The UUID lets you reference the particular file, later, to the SMSyncServer framework.
        let uuid = NSUUID()
        
        let attr = SMSyncAttributes(withUUID: uuid, mimeType: "text/plain", andRemoteFileName: uuid.UUIDString)
        
        self.singleFileUpload(uuid, fileContents: exampleFileContents) { 
            do {
                try SMSyncServer.session.uploadTemporaryFile(url, withFileAttributes: attr)
            } catch (let error) {
                print("Yikes: There was an error with uploadTemporaryFile: \(error)")
            }
            
            // You could call uploadTemporaryFile (or the other upload or deletion methods) any number of times, to queue up a group of files for upload.
            
            // The commit call actually starts the upload process.
            do {
                try SMSyncServer.session.commit()
            } catch (let error) {
                print("Yikes: There was an error with commit: \(error)")
            }
        }
    }
    
    func testThatREADMEUploadDataWorks() {
        // Just example content. This content would, of course, depend on your app.
        let exampleContents = "Hello World!"
        let data = exampleContents.dataUsingEncoding(NSUTF8StringEncoding)!
        
         // you would normally store this persistently, e.g., in CoreData. The UUID lets you reference the particular data object, later, to the SMSyncServer framework.
        let uuid = NSUUID()
        
        let attr = SMSyncAttributes(withUUID: uuid, mimeType: "text/plain", andRemoteFileName: uuid.UUIDString)
        
        self.singleFileUpload(uuid, fileContents: exampleContents) {
            do {
                try SMSyncServer.session.uploadData(data, withDataAttributes: attr)
            } catch (let error) {
                print("Yikes: There was an error with uploadData: \(error)")
            }
            
            // You could call uploadData (or the other upload or deletion methods) any number of times, to queue up a group of files/data for upload.
            
            // The commit call actually starts the upload process.
            do {
                try SMSyncServer.session.commit()
            } catch (let error) {
                print("Yikes: There was an error with commit: \(error)")
            }
        }
    }
    
    func testThatREADMEDeletionWorks() {
    
    }
}
