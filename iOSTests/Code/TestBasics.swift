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
    private var _url:NSURL?
    
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
    
    public var attr:SMSyncAttributes {
        var remoteFile = self.fileName
        if self.remoteFileName != nil {
            remoteFile = self.remoteFileName
        }
        
        return SMSyncAttributes(withUUID: self.uuid, mimeType: self.mimeType, andRemoteFileName: remoteFile)
    }
    
    public var url:NSURL {
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
    
    public func createFile(withName fileName: String) -> (file:AppFile, fileSizeInBytes:Int) {
        let file = self.makeNewFile(withFileName: fileName)
        let fileContents:NSString = fileName + "123" // sample data
        let fileSizeBytes = fileContents.length
        
        do {
            try fileContents.writeToURL(file.url(), atomically: true, encoding: NSASCIIStringEncoding)
        } catch {
            self.failure!()
        }
        
        return (file, fileSizeBytes)
    }
    
    public func createTestFile(fileName:String) -> TestFile {
        let (file, fileSizeBytes) = self.createFile(withName: fileName)
        var result = TestFile()
        result.appFile = file
        result.sizeInBytes = fileSizeBytes
        result.mimeType = "text/plain"
        result.fileName = fileName
        return result
    }
    
    // It's possible we'll check and another device with our same userId (same cloud storage creds) will have a lock-- so be willing to try this a number of times.
    private let maxNumberCheckFileSizeAttempts = 10
    
    // Make sure the file size we got on cloud storage was what we expected.
    public func checkFileSize(uuid:String, size:Int, finish:()->()) {
        self.checkFileSizeAux(1, uuid: uuid, size: size, finish: finish)
    }
    
    private func checkFileSizeAux(attemptNumber:Int, uuid:String, size:Int, finish:()->()) {
        if attemptNumber > maxNumberCheckFileSizeAttempts {
            self.failure!()
            return
        }
        
        SMServerAPI.session.getFileIndex() { (fileIndex, apiResult) in
            if apiResult.error == nil {
                let result = fileIndex!.filter({
                    $0.uuid.UUIDString == uuid && $0.sizeBytes == Int32(size)
                })
                if result.count == 1 {
                    finish()
                }
                else {
                    Log.error("Did not find expected \(size) bytes for uuid \(uuid)")
                    self.failure!()
                }
            }
            else if apiResult.returnCode == SMServerConstants.rcLockAlreadyHeld {
                let attempt = attemptNumber+1
                let duration = SMServerNetworking.exponentialFallbackDuration(forAttempt: attempt)

                TimedCallback.withDuration(duration) {
                    self.checkFileSizeAux(attempt, uuid: uuid, size: size, finish: finish)
                }
            }
            else {
                Log.error("checkFileSize: Got an error: \(apiResult.error)")
                self.failure!()
            }
        }
    }
}