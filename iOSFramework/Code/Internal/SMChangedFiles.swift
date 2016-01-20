//
//  SMChangedFiles.swift
//  NetDb
//
//  Created by Christopher Prince on 12/24/15.
//  Copyright © 2015 Spastic Muffin, LLC. All rights reserved.
//

// Helper class (not for SyncServer public usage)-- to represent the set of changed files that need to be uploaded to the server.
// SMLocalFile meta data is used to see if there are any updates needing to be uploaded.

import Foundation
import SMCoreLib

internal class SMChangedFiles {
    // 1/5/16; We're just going to keep references to the SMFileChange objects. Since these refer back to the SMLocalFile, we'll be OK that way. Up until this date, this array was of type SMLocalFile, but we could run into situations where, if we did an upload, commit, quickly followed by an upload and commit on the same file, we'd not get the upload of the first file. Another way of saying this is that we need to call getMostRecentChangeAndFlush at the very beginning of the commit process. See test testThatUpdateAfterUploadWorks().
    private var fileChanges = [SMFileChange]()
    
    init() {
        // Figure out the collection of changed files.
        if let fileArray = SMLocalFile.fetchAllObjects() as? [SMLocalFile] {
            for localFile:SMLocalFile in fileArray {
                if localFile.locallyChanged {
                    let fileChange = localFile.getMostRecentChangeAndFlush()
                    fileChanges.append(fileChange!)
                    Log.msg("local file has changed: \(fileChange!.localFileNameWithPath)")
                }
            }
        }
    }
    
    // Set this to provide the file index from the server. Provide this so this class can ensure that the file versions being uploaded are correct.
    internal var serverFileIndex:[SMServerFile]?
    
    // Set this if you have already uploaded some files (i.e., you are doing error recovery).
    internal var alreadyUploaded:[SMServerFile]?
    
    // A count of the changed files. Includes files marked for deletion and files that will be uploaded.
    internal var count:Int {
        get {
            return fileChanges.count
        }
    }
    
    internal func filesToDelete() -> (files:[SMServerFile]?, error:NSError?) {
        var result = [SMServerFile]()

        for fileChange:SMFileChange in self.fileChanges {
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
        var result = [SMServerFile]()

        for fileChange:SMFileChange in self.fileChanges {
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
            
            if serverFile != nil && localVersion != serverFile!.version {
                return (files:nil, error: Error.Create("Server file version \(serverFile!.version) not the same as local file version \(localVersion)"))
            }
            
            if nil == serverFile {
                // No file with this UUID on the server. This must be a new file.
                serverFile = SMServerFile(localURL: nil, remoteFileName: localFile.remoteFileName! as String, mimeType: localFile.mimeType!, appFileType:localFile.appFileType, uuid: NSUUID(UUIDString: localFile.uuid!)!, version: Int(localFile.localVersion!.intValue))
                
                Assert.If(0 != localFile.localVersion, thenPrintThisString: "Yikes: The first version of the file was not 0")
            }
            else {
                // I'm making a copy of the serverFile object because serverFile is a reference to an object in self.serverFileIndex, and I don't want that array modified.
                serverFile = serverFile!.copy() as? SMServerFile
                serverFile!.version = localVersion + 1
            }
            
            serverFile!.localFile = localFile
            serverFile!.localURL = NSURL(fileURLWithPath: fileChange.localFileNameWithPath!)
            result += [serverFile!]
        }
        
        return (files: result, error:nil)
    }
    
    private func getFile(fromFiles files:[SMServerFile]?, withUUID uuid: NSUUID) -> SMServerFile? {
        if nil == files || files?.count == 0  {
            return nil
        }
        
        let result = files?.filter({$0.uuid.isEqual(uuid)})
        if result!.count > 0 {
            return result![0]
        }
        else {
            return nil
        }
    }
}
