//
//  SMLocalFile.swift
//  
//
//  Created by Christopher Prince on 1/18/16.
//
//

/*
Property notes:

Storing the appMetaData in Core Data along with the SMLocalFile may not be completely necessary, but it is convenient.
*/

import Foundation
import CoreData
import SMCoreLib

@objc(SMLocalFile)
class SMLocalFile: NSManagedObject, CoreDataModel {
    enum SyncState : String {
        // A new file has been created by the local client API but not yet uploaded to sync server.
        case InitialUpload
        
        // A new file has created by another device, detected on the server, and is in the process of being downloaded to the local device.
        case InitialDownload
        
        // The file has either been uploaded or downloaded at least once.
        case AfterInitialSync
    }
    
    var syncState : SyncState {
        get {
            return SyncState(rawValue: self.internalSyncState!)!
        }
        set {
            self.internalSyncState = newValue.rawValue
            CoreData.sessionNamed(SMCoreData.name).saveContext()
        }
    }
    
    var deletedOnServer:Bool {
        get {
            if self.internalDeletedOnServer == nil {
                return false
            }
            else {
                return self.internalDeletedOnServer!.boolValue
            }
        }
        set {
            self.internalDeletedOnServer = newValue
            CoreData.sessionNamed(SMCoreData.name).saveContext()
        }
    }
    
    var appMetaData:SMAppMetaData? {
        get {
            if self.internalAppMetaData == nil {
                return nil
            }
            else {
                var result:SMAppMetaData?

                do {
                    try result = NSJSONSerialization.JSONObjectWithData(self.internalAppMetaData!, options: NSJSONReadingOptions(rawValue: 0)) as? SMAppMetaData
                } catch (let error) {
                    Log.error("Error converting JSON data: \(error)")
                    return nil
                }
                
                Log.msg("SMLocalFile.appMetaData: \(result)")
                
                return result
            }
        }
        
        // Does a CoreData save context.
        set {
            if newValue == nil {
                self.internalAppMetaData = nil
            }
            else {
                var jsonData:NSData?

                do {
                    try jsonData = NSJSONSerialization.dataWithJSONObject(newValue!, options: NSJSONWritingOptions(rawValue: 0))
                } catch (let error) {
                    Log.error("Error serializing to JSON data: \(error)")
                }
                self.internalAppMetaData = jsonData
            }
            
            CoreData.sessionNamed(SMCoreData.name).saveContext()
        }
    }
    
    static let UUID_KEY = "uuid"
    
    class func entityName() -> String {
        return "SMLocalFile"
    }

    // When an SMLocalFile is created for purposes of uploading, it must have a .localVersion of 0. When it is created for purposes of downloading (i.e., the first version of the file was created on another device), the .localVersion should be nil until just before the callback that indicates to the client app that the file was downloaded (syncServerDownloadsComplete).
    class func newObjectAndMakeUUID(makeUUID: Bool) -> NSManagedObject {
        let localFile = CoreData.sessionNamed(SMCoreData.name).newObjectWithEntityName(self.entityName()) as! SMLocalFile
        
        if makeUUID {
            localFile.uuid = UUID.make()
        }
        
        localFile.internalDeletedOnServer = false
        localFile.pendingUploads = NSOrderedSet()
        
        CoreData.sessionNamed(SMCoreData.name).saveContext()

        return localFile
    }
    
    class func newObject() -> NSManagedObject {
        return self.newObjectAndMakeUUID(false)
    }
    
    func removeObject() {
        SMDownloadOperation.removeObjectsInOrderedSet(self.downloadOperations!)
        SMUploadOperation.removeObjectsInOrderedSet(self.pendingUploads!)
        
        CoreData.sessionNamed(SMCoreData.name).removeObject(self)
        CoreData.sessionNamed(SMCoreData.name).saveContext()
    }
    
    class func fetchAllObjects() -> [AnyObject]? {
        var resultObjects:[AnyObject]? = nil
        
        do {
            try resultObjects = CoreData.sessionNamed(SMCoreData.name).fetchAllObjectsWithEntityName(self.entityName())
        } catch (let error) {
            // Somehow, and sometimes, this is throwing an error if there are no result objects. But I'm not returning an error from fetchAllObjectsWithEntityName. Odd.
            // Some ideas from Chris Chares on dealing with this issue if it keeps cropping up: https://gist.github.com/ChrisChares/aab07590ab28ac8da05e
            // See also the link he passed along: https://developer.apple.com/library/ios/documentation/Swift/Conceptual/BuildingCocoaApps/AdoptingCocoaDesignPatterns.html#//apple_ref/doc/uid/TP40014216-CH7-ID6
            Log.msg("Error in fetchAllObjects: \(error)")
        }
        
        return resultObjects
    }
    
    class func fetchObjectWithUUID(uuid:String) -> SMLocalFile? {
        let managedObject = CoreData.fetchObjectWithUUID(uuid, usingUUIDKey: UUID_KEY, fromEntityName: SMLocalFile.entityName(), coreDataSession: CoreData.sessionNamed(SMCoreData.name))
        return managedObject as? SMLocalFile
    }
    
    func locallyChanged() -> Bool {
        return self.pendingUploads!.count > 0;
    }
    
    func pendingSMUploadFiles() -> [SMUploadFile]? {
        var result = [SMUploadFile]()
        
        if self.pendingUploads != nil {
            for fileChange in self.pendingUploads! {
                if fileChange is SMUploadFile {
                    result.append(fileChange as! SMUploadFile)
                }
            }
        }
        
        return result.count == 0 ? nil : result
    }
    
    // Returns true if any of the .pendingUploads are SMUploadFile's
    func pendingUpload() -> Bool {
        let uploadFiles = self.pendingSMUploadFiles()
        return uploadFiles == nil ? false : true
    }
    
    func pendingSMUploadDeletion(excepting excepting:SMUploadDeletion?=nil) -> SMUploadDeletion? {
        var result = [SMUploadDeletion]()
        
        if self.pendingUploads != nil {
            for fileChange in self.pendingUploads! {
                if let deletion = fileChange as? SMUploadDeletion {
                    if excepting == nil || !excepting!.isEqual(deletion) {
                        result.append(deletion)
                    }
                }
            }
        }
        
        Assert.If(result.count > 1, thenPrintThisString: "Yikes: have more than one pending upload deletion!")
        
        return result.count == 0 ? nil : result[0]
    }
    
    // There is a pending upload-deletion if *any* of the SMUploadFileChange's in the .pendingUploads is an SMUploadDeletion.
    func pendingUploadDeletion(excepting excepting:SMUploadDeletion?=nil) -> Bool {
        let deletion = self.pendingSMUploadDeletion(excepting: excepting)
        return deletion == nil ? false : true
    }
}
