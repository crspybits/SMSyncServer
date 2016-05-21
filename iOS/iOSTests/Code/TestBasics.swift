//
//  TestBasics.swift
//  Tests
//
//  Created by Christopher Prince on 2/7/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import SMCoreLib
@testable import SMSyncServer

public struct TestFile {
    private var _url:SMRelativeLocalURL?
    
    public var appFile:AppFile!
    public var sizeInBytes:Int!
    public var mimeType:String!
    public var fileName:String! // local
    public var remoteFileName:String?
    
    public var uuid:NSUUID {
        return NSUUID(UUIDString: self.appFile.uuid!)!
    }
    
    public var uuidString:String {
        return self.appFile.uuid!
    }
    
    public var remoteFile:String {
        var remoteFile = self.fileName
        if self.remoteFileName != nil {
            remoteFile = self.remoteFileName
        }
        return remoteFile
    }
    
    public var attr:SMSyncAttributes {
        return SMSyncAttributes(withUUID: self.uuid, mimeType: self.mimeType, andRemoteFileName: self.remoteFile)
    }
    
    public var url:SMRelativeLocalURL {
        get {
            if nil == self._url {
                return self.appFile.url()
            }
            else {
                return self._url!
            }
        }
        
        set {
            self._url = newValue
        }
    }
    
    public func remove() {
        self.appFile!.removeObject()
    }
}

public class TestBasics {
    public static let session = TestBasics()
    
    private init() {
    }
    
    public var failure:(()->())!
    
    public func makeNewFile(withFileName fileName: String) -> AppFile {
        let file = AppFile.newObjectAndMakeUUID(true)
        file.fileName = fileName
        
        let path = FileStorage.pathToItem(file.fileName)
        NSFileManager.defaultManager().createFileAtPath(path, contents: nil, attributes: nil)

        CoreData.sessionNamed(CoreDataTests.name).saveContext()
        
        return file
    }
    
    public func createFile(withName fileName: String, andContents contents:String?=nil) -> (file:AppFile, fileSizeInBytes:Int) {
        let file = self.makeNewFile(withFileName: fileName)
        var fileContents:NSString = fileName + "123" // sample data
        if contents != nil {
            fileContents = contents!
        }
        
        let fileSizeBytes = fileContents.length
        
        do {
            try fileContents.writeToURL(file.url(), atomically: true, encoding: NSASCIIStringEncoding)
        } catch {
            self.failure!()
        }
        
        return (file, fileSizeBytes)
    }
    
    public func createTestFile(fileName:String, withContents contents:String?=nil) -> TestFile {
        let (file, fileSizeBytes) = self.createFile(withName: fileName, andContents: contents)
        var result = TestFile()
        result.appFile = file
        result.sizeInBytes = fileSizeBytes
        result.mimeType = "text/plain"
        result.fileName = fileName
        return result
    }
    
    public func recreateTestFile(fromUUID uuidString:String) -> TestFile {
        var testFile = TestFile()
        testFile.appFile = AppFile.fetchObjectWithUUID(uuidString)
        testFile.sizeInBytes = Int(FileStorage.fileSize(testFile.appFile.url().path))
        testFile.mimeType = "text/plain"
        testFile.fileName = testFile.appFile.fileName
        testFile.remoteFileName = testFile.appFile.fileName
        return testFile
    }
    
    // It's possible we'll check and another device with our same userId (same cloud storage creds) will have a lock-- so be willing to try this a number of times.
    private let maxNumberCheckFileSizeAttempts = 10
    
    // Check if a file exists on the server.
    public func checkForFileOnServer(uuid:String, fileExists:(Bool)->()) {
        self.checkForFileOnServer(1, uuid: uuid, fileExists: fileExists)
    }
    
    private func checkForFileOnServer(attemptNumber:Int, uuid:String, fileExists:(Bool)->()) {
        if attemptNumber > maxNumberCheckFileSizeAttempts {
            self.failure!()
            return
        }
        
        SMServerAPI.session.getFileIndex() { (fileIndex, apiResult) in
            if apiResult.error == nil {
                let result = fileIndex!.filter({
                    $0.uuid.UUIDString == uuid
                })
                if result.count == 1 {
                    if result[0].deleted == nil || !result[0].deleted! {
                        fileExists(true)
                    }
                    else {
                        fileExists(false)
                    }
                }
                else {
                    Log.error("Found \(result.count) files")
                    self.failure!()
                }
            }
            else if apiResult.returnCode == SMServerConstants.rcLockAlreadyHeld {
                let attempt = attemptNumber+1
                
                SMServerNetworking.exponentialFallback(forAttempt: attempt) {
                    self.checkForFileOnServer(attempt, uuid: uuid, fileExists: fileExists)
                }
            }
            else {
                Log.error("checkFileSize: Got an error: \(apiResult.error)")
                self.failure!()
            }
        }
    }
    
    // Make sure the file size we got on cloud storage was what we expected.
    public func checkFileSize(uuid:String, size:Int, finish:()->()) {
        self.checkFileSize(1, uuid: uuid, size: size, finish: finish)
    }
    
    private func checkFileSize(attemptNumber:Int, uuid:String, size:Int, finish:()->()) {
        Log.msg("getFileIndex from checkFileSizeAux")
        
        if attemptNumber > maxNumberCheckFileSizeAttempts {
            self.failure!()
            return
        }
        
        SMServerAPI.session.getFileIndex() { (fileIndex, apiResult) in
            if apiResult.error == nil {
                let result = fileIndex!.filter({
                    $0.uuid.UUIDString == uuid
                })
                if result.count == 1 {
                    if result[0].sizeBytes == size {
                        finish()
                    }
                    else {
                        Log.error("Did not find expected \(size) bytes for uuid \(uuid) but found \(result[0].sizeBytes) bytes")
                        self.failure!()
                    }
                }
                else {
                    Log.error("Found \(result.count) files")
                    self.failure!()
                }
            }
            else if apiResult.returnCode == SMServerConstants.rcLockAlreadyHeld {
                let attempt = attemptNumber+1
                
                SMServerNetworking.exponentialFallback(forAttempt: attempt) {
                    self.checkFileSize(attempt, uuid: uuid, size: size, finish: finish)
                }
            }
            else {
                Log.error("checkFileSize: Got an error: \(apiResult.error)")
                self.failure!()
            }
        }
    }
}