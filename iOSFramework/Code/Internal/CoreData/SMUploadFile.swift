//
//  SMUploadFile.swift
//  
//
//  Created by Christopher Prince on 1/18/16.
//
//

import Foundation
import CoreData
import SMCoreLib

/* Core Data model notes:
    1) filePathBaseURLType is the raw value of the SMRelativeLocalURL BaseURLType (nil if file change indicates a deletion).
    2) filePath is the relative path of the URL in the case of a local relative url or the path for other urls (nil if file change indicates a deletion).
*/

@objc(SMUploadFile)
class SMUploadFile: SMUploadFileOperation, CoreDataModel {

    class func entityName() -> String {
        return "SMUploadFile"
    }

    class func newObject() -> NSManagedObject {
        
        let fileChange = CoreData.sessionNamed(SMCoreData.name).newObjectWithEntityName(self.entityName()) as! SMUploadFile
        
        fileChange.operationStage = .ServerUpload

        CoreData.sessionNamed(SMCoreData.name).saveContext()
        
        return fileChange
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
    
    // If the block doesn't indicate deletion, creates upload blocks.
    func addUploadBlocks() {
        let uploadBlocks = NSMutableOrderedSet()
        var fileSizeRemaining = FileStorage.fileSize(self.fileURL!.path)
        var currBlockStartOffset:UInt = 0
        
        while fileSizeRemaining > 0 {
            var currBlockSize:UInt
            if fileSizeRemaining >= SMSyncServer.BLOCK_SIZE_BYTES {
                currBlockSize = SMSyncServer.BLOCK_SIZE_BYTES
            }
            else {
                currBlockSize = fileSizeRemaining
            }
            
            let uploadBlock = SMUploadBlock.newObject() as! SMUploadBlock
            uploadBlock.numberBytes = currBlockSize
            uploadBlock.startByteOffset = currBlockStartOffset
            uploadBlocks.addObject(uploadBlock)
            
            fileSizeRemaining -= currBlockSize
            currBlockStartOffset += currBlockSize
        }
        
        self.blocks = uploadBlocks
        
        CoreData.sessionNamed(SMCoreData.name).saveContext()
    }
    
    override func removeObject() {
        // We can't iterate over self.blocks! and delete the blocks within there because the deletion itself changes the contents of self.blocks and causes this to fail.
        let blocksToDelete = NSOrderedSet(orderedSet: self.blocks!)
        for elem in blocksToDelete {
            let block = elem as? SMUploadBlock
            Assert.If(nil == block, thenPrintThisString: "Didn't have an SMUploadBlock object")
            block!.removeObject()
        }
        
        super.removeObject()
    }
}
