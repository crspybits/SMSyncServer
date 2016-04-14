//
//  SMFileDiffs.swift
//  NetDb
//
//  Created by Christopher Prince on 12/24/15.
//  Copyright © 2015 Spastic Muffin, LLC. All rights reserved.
//

// Internal framework class to represent the collection of files that need to be uploaded to the server, or downloaded from the server.

import Foundation
import SMCoreLib

#if false

// TODO: There is a potential race condition with any code that (a) accesses the collection of meta data, and (b) runs in a different thread than the application code. I.e., what happens if the SMLocalFile meta data gets changed while this class is accessing that meta data? It seems best to provide a level of locking where when this class accesses the SMLocalFile meta data, no other thread can access that meta data. E.g., this could be done by providing a lock specific to the SMLocalFile class which must be obtained prior to creating or altering an SMLocalFile's.

internal enum InitType : Equatable {
    // SMLocalFile meta data is used to see if there are any updates needing to be uploaded.
    case LocalChanges
    
    // Provides value for the serverFileIndex member var to the init method.
    case RemoteChanges(serverFileIndex:[SMServerFile])
}

// When you have associated values with an enum, you have to manufacture equality yourself. http://stackoverflow.com/questions/24339807/how-to-test-equality-of-swift-enums-with-associated-values
// This is just a coarse measure of equality-- doesn't take into account associated values of RemoteChanges.
internal func ==(a: InitType, b: InitType) -> Bool {
    switch (a, b) {
    case (.LocalChanges, .LocalChanges):
        return true
        
    case (.RemoteChanges(_), .RemoteChanges(_)):
        return true
        
    default:
        return false
    }
}

internal class SMFileDiffs {
    private let initType:InitType?
    
    // 1/5/16; We're just going to keep references to the SMFileChange objects. Since these refer back to the SMLocalFile, we'll be OK that way. Up until this date, this array was of type SMLocalFile, but we could run into situations where, if we did an upload, commit, quickly followed by an upload and commit on the same file, we'd not get the upload of the first file. Another way of saying this is that we need to call getMostRecentChangeAndFlush at the very beginning of the commit process. See test testThatUpdateAfterUploadWorks().
    private var fileChanges = [SMUploadFileChange]()
    
    internal init(type theInitType:InitType) {
        self.initType = theInitType
        
        switch self.initType! {
        case .LocalChanges:
            // Figure out the collection of changed local files.
            if let fileArray = SMLocalFile.fetchAllObjects() as? [SMLocalFile] {
                for localFile:SMLocalFile in fileArray {
                    if localFile.locallyChanged {
                        let fileChange = localFile.getMostRecentChangeAndFlush()
                        fileChanges.append(fileChange!)
                        Log.msg("local file has changed: \(fileChange!.fileURL)")
                    }
                }
            }
            
        case .RemoteChanges(let fileIndex):
            self.serverFileIndex = fileIndex
        }
    }
    
    // File index from the server. For InitType .LocalChanges, provide this so this class can ensure that the file versions being uploaded are correct.
    internal var serverFileIndex:[SMServerFile]?
    
    // Set this if you have already uploaded some files (i.e., you are doing error recovery).
    // Intended for InitType .LocalChanges
    internal var alreadyUploaded:[SMServerFile]?
    
    // A count of the changed files. Includes files marked for deletion and files that will be uploaded.
    internal var count:Int {
        get {
            Assert.If(self.initType! != InitType.LocalChanges, thenPrintThisString: "Yikes: Didn't init for .LocalChanges")
            return fileChanges.count
        }
    }
    
    // Indicates which remote files need to be deleted.
    internal func filesToDelete() -> (files:[SMServerFile]?, error:NSError?) {
        Assert.If(self.initType! != InitType.LocalChanges, thenPrintThisString: "Yikes: Didn't init for .LocalChanges")
        
        var result = [SMServerFile]()

        for fileChange:SMUploadFileChange in self.fileChanges {
            // Ignore the upload files.
            if !fileChange.deletion!.boolValue {
                continue
            }
            
            Log.msg("\(fileChange)")
            
            let localFile = fileChange.changedFile!
            
            let localVersion:Int = localFile.localVersion!.integerValue
            Log.msg("Local file version: \(localVersion)")
            
            var serverFile:SMServerFile? = self.getFile(fromFiles: self.serverFileIndex, withUUID: NSUUID(UUIDString: localFile.uuid!)!)
            
            if nil == serverFile {
                return (files:nil, error: Error.Create("File you are deleting is not on the server!"))
            }
            
            if serverFile!.deleted!.boolValue {
                return (files:nil, error: Error.Create("The server file you are attempting to delete was already deleted!"))
            }
            
            // Also seems odd to delete a file version that you don't know about.
            if localVersion != serverFile!.version {
                return (files:nil, error: Error.Create("Server file version \(serverFile!.version) not the same as local file version \(localVersion)"))
            }
            
            // I'm making a copy of the serverFile object because serverFile is a reference to an object in self.serverFileIndex, and I don't want that array modified.
            serverFile = serverFile!.copy() as? SMServerFile
            serverFile!.version = localVersion
            serverFile!.localFile = localFile
            result += [serverFile!]
        }
        
        return (files: result, error:nil)
    }
    
    // TODO: Note this doesn't deal with files on the server that are not present locally. This also doesn't deal with files that have changed on server. It assumes that only a single app is uploading changes.
    internal func filesToUpload() -> (files:[SMServerFile]?, error:NSError?) {
        Assert.If(self.initType! != .LocalChanges, thenPrintThisString: "Yikes: Didn't init for .LocalChanges")
        
        var result = [SMServerFile]()

        for fileChange:SMUploadFileChange in self.fileChanges {
            // Ignore the files marked for deletion.
            if fileChange.deletion!.boolValue {
                continue
            }
            
            Log.msg("\(fileChange)")
            
            let localFile = fileChange.changedFile!
            
            if let _ = self.getFile(fromFiles: self.alreadyUploaded, withUUID:  NSUUID(UUIDString: localFile.uuid!)!) {
                // That file was already uploaded. Don't include it.
                continue
            }
            
            // We need to make sure that the current version on the server (if any) is the same as the version locally. This is so that we can be assured that the new version we are updating from locally is logically the next version for the server.
            
            let localVersion:Int = localFile.localVersion!.integerValue
            Log.msg("Local file version: \(localVersion)")
            
            var serverFile:SMServerFile? = self.getFile(fromFiles: self.serverFileIndex, withUUID:  NSUUID(UUIDString: localFile.uuid!)!)
            
            if nil == serverFile {
                // No file with this UUID on the server. This must be a new file.
                serverFile = SMServerFile(uuid: NSUUID(UUIDString: localFile.uuid!)!,remoteFileName: localFile.remoteFileName! as String, mimeType: localFile.mimeType!, appFileType:localFile.appFileType, version: Int(localFile.localVersion!.intValue))
                
                Assert.If(0 != localFile.localVersion, thenPrintThisString: "Yikes: The first version of the file was not 0")
            }
            else {
                if localVersion != serverFile!.version {
                    return (files:nil, error: Error.Create("Server file version \(serverFile!.version) not the same as local file version \(localVersion)"))
                }
                
                if serverFile!.deleted!.boolValue {
                    return (files:nil, error: Error.Create("The server file you are attempting to upload was already deleted!"))
                }
                
                // I'm making a copy of the serverFile object because serverFile is a reference to an object in self.serverFileIndex, and I don't want that array modified.
                serverFile = serverFile!.copy() as? SMServerFile
                serverFile!.version = localVersion + 1
            }
            
            serverFile!.localFile = localFile
            serverFile!.localURL = fileChange.fileURL
            result += [serverFile!]
        }
        
        return (files: result, error:nil)
    }
}

#endif
