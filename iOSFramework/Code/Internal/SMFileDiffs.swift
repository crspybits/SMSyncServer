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
    private var fileChanges = [SMFileChange]()
    
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
                        Log.msg("local file has changed: \(fileChange!.localFileNameWithPath)")
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
    
    internal func filesToDelete() -> (files:[SMServerFile]?, error:NSError?) {
        Assert.If(self.initType! != InitType.LocalChanges, thenPrintThisString: "Yikes: Didn't init for .LocalChanges")
        
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
            
            if nil == serverFile {
                // No file with this UUID on the server. This must be a new file.
                serverFile = SMServerFile(uuid: NSUUID(UUIDString: localFile.uuid!)!,localURL: nil, remoteFileName: localFile.remoteFileName! as String, mimeType: localFile.mimeType!, appFileType:localFile.appFileType, version: Int(localFile.localVersion!.intValue))
                
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
            serverFile!.localURL = NSURL(fileURLWithPath: fileChange.localFileNameWithPath!)
            result += [serverFile!]
        }
        
        return (files: result, error:nil)
    }
    
    /* Need to compare our local files against the server files to see which we need to download. Cases:
    1) Server files which don't yet exist on the app/client.
        i.e., the UUID isn't on the client.
    2) Server files which are updated versions of those on app/client.
        i.e., client version is N, server version is N+M, M > 0.
        The simplest case of this is the client has version N, and the server has version N+1. This means that another client, with the same cloud storage user info, has made an update to the file.
        If the server version is N+2, then it just means that two updates have occurred from other client(s).
        Etc.
    3) Server files which are in update conflict with those on the app/client.
        This can be detected when the app/client file has changed (current version is N, which should be uploaded as N+1 to the server) but there is also an update on the server. To have no conflict with the server, the server file version should currently be N. A conflict is detected when the server version is N+M, M > 0.
    4) Files which are in deletion conflict with those on the app/client. This can happen in one of two ways:
        a) The file has been deleted on the server, but updated on the client.
        b) The file has been updated on the server, but deleted on the client.
        (Notes: The case of update on the server and update on the client is an update conflict, see case 3. The case of deletion on the client and deletion on the server poses no conflict-- the file needs to be deleted on the client.)
    */
    // This handles cases 1) and 2) from above.
    // TODO: Handle update and deletion conflicts.
    // Returns nil if there are no files to download.
    internal func filesToDownload() -> [SMServerFile]? {
        var result = [SMServerFile]()
    
        // Awwww. Can't directly compare .RemoteChanges even though I did the Equatable above... :(.
        switch self.initType! {
        case .LocalChanges:
            Assert.badMojo(alwaysPrintThisString: "Yikes: Must use .RemoteChanges")
            
        case .RemoteChanges (let serverFileIndex):
            
                result = [SMServerFile]()
                
                for serverFile in serverFileIndex {
                    if serverFile.deleted! {
                        // File was deleted on the server.
                        // TODO: We need to check to see if this file is marked as deleted in the local meta data, if we know about its UUID. If we know about its UUID, but it's not marked as deleted, we can mark it as deleted. 
                        // TODO: WE ALSO need to give a delegate callback for this to tell the SMSyncServer Framework client that the file was deleted.
                        continue
                    }
                    
                    let localFile = SMLocalFile.fetchObjectWithUUID(serverFile.uuid!.UUIDString)
                    if localFile == nil {
                        // Case 1) Server file doesn't yet exist on the app/client.
                        result.append(serverFile)
                    }
                    else {
                        Assert.If(nil == serverFile.version, thenPrintThisString: "No version on server file.")
                        
                        // TODO: handle conflict case
                        Assert.If(localFile!.locallyChanged, thenPrintThisString: "Need to handle conflict case.")
                        
                        // TODO: Handle (to be implemented) deleted flag on SMServerFile
                        
                        let (serverVersion, localVersion) = (serverFile.version!, localFile!.localVersion!.integerValue)
                        
                        if serverVersion == localVersion {
                            // No update. No need to download.
                            continue
                        }
                        else if serverVersion > localVersion {
                            // Case 2) Server file is updated version of that on app/client.
                            // Server version is greater. Need to download.
                            result.append(serverFile)
                        } else { // serverVersion < localVersion
                            Assert.badMojo(alwaysPrintThisString: "This should never happen.")
                        }
                    }
                }
        }
        
        if result.count == 0 {
            return nil
        }
        else {
            return result
        }
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
