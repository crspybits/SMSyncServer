//
//  SMDownloadFile.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 4/4/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import CoreData
import SMCoreLib

class SMDownloadFile: SMDownloadFileOperation, CoreDataModel {

    class func entityName() -> String {
        return "SMDownloadFile"
    }

    class func newObject() -> NSManagedObject {
        
        let fileChange = CoreData.sessionNamed(SMCoreData.name).newObjectWithEntityName(self.entityName()) as! SMDownloadFile
        
        CoreData.sessionNamed(SMCoreData.name).saveContext()
        
        return fileChange
    }
    
    // localFileMetaData will be nil in the case when, after the download the SMLocalFile meta data needs to be created-- the file doesn't yet exist locally.
    class func newObject(fromServerFile serverFile:SMServerFile, andLocalFileMetaData localFileMetaData:SMLocalFile?) -> SMDownloadFile {
        let downloadFileChange = self.newObject() as! SMDownloadFile
        
        // Need to give the download (not download-deletion) a local file where the download will be placed.
        let localRelativeFile = SMFiles.createTemporaryRelativeFile()
        Assert.If(localRelativeFile == nil, thenPrintThisString: "Could not create temporary file")
        downloadFileChange.fileURL = localRelativeFile
        
        downloadFileChange.localFile = localFileMetaData
        
        Assert.If(serverFile.sizeBytes == nil, thenPrintThisString: "No sizeBytes given in SMServerFile")
        
        // addDownloadBlocks saves the context, so we don't have to do that again.
        downloadFileChange.addDownloadBlocks(givenFileSizeInbytes: UInt(serverFile.sizeBytes!))
        
        return downloadFileChange
    }
    
    override func removeObject() {
        let blocksToDelete = NSOrderedSet(orderedSet: self.blocks!)

        for elem in blocksToDelete {
            let block = elem as? SMDownloadBlock
            Assert.If(nil == block, thenPrintThisString: "Didn't have an SMDownloadBlock object")
            block!.removeObject()
        }
        
        super.removeObject()
    }
    
    // Returns nil if the file change indicates a deletion. Don't use self.internalRelativeLocalURL directly.
    var fileURL: SMRelativeLocalURL? {
        get {
            if nil == self.internalRelativeLocalURL {
                return nil
            }
            
            let url = NSKeyedUnarchiver.unarchiveObjectWithData(self.internalRelativeLocalURL!) as? SMRelativeLocalURL
            Assert.If(url == nil, thenPrintThisString: "Yikes: No URL!")
            return url
        }
        
        set {
            if newValue == nil {
                self.internalRelativeLocalURL = nil
            }
            else {
                self.internalRelativeLocalURL = NSKeyedArchiver.archivedDataWithRootObject(newValue!)
            }
            
            CoreData.sessionNamed(SMCoreData.name).saveContext()
        }
    }
    
    // If the block doesn't indicate deletion, creates download blocks.
    func addDownloadBlocks(givenFileSizeInbytes fileSizeBytes:UInt) {
        let downloadBlocks = NSMutableOrderedSet()
        var fileSizeRemaining = fileSizeBytes
        var currBlockStartOffset:UInt = 0
        
        while fileSizeRemaining > 0 {
            var currBlockSize:UInt
            if fileSizeRemaining >= SMSyncServer.BLOCK_SIZE_BYTES {
                currBlockSize = SMSyncServer.BLOCK_SIZE_BYTES
            }
            else {
                currBlockSize = fileSizeRemaining
            }
            
            let downloadBlock = SMDownloadBlock.newObject() as! SMDownloadBlock
            downloadBlock.numberBytes = currBlockSize
            downloadBlock.startByteOffset = currBlockStartOffset
            downloadBlocks.addObject(downloadBlock)
            
            fileSizeRemaining -= currBlockSize
            currBlockStartOffset += currBlockSize
        }
        
        self.blocks = downloadBlocks
        
        CoreData.sessionNamed(SMCoreData.name).saveContext()
    }
}
