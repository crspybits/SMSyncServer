//
//  NoteImage.swift
//  SharedNotes
//
//  Created by Christopher Prince on 5/22/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import CoreData
import SMCoreLib
import SMSyncServer

class NoteImage: NSManagedObject {
    static let UUID_KEY = "uuid"

    var fileURL: SMRelativeLocalURL? {
        get {
            return CoreData.getSMRelativeLocalURL(fromCoreDataProperty: self.internalRelativeLocalURL)
        }
        
        set {
            CoreData.setSMRelativeLocalURL(newValue, toCoreDataProperty: &self.internalRelativeLocalURL, coreDataSessionName: CoreDataSession.name)
        }
    }
    
    class func entityName() -> String {
        return "NoteImage"
    }

    static let mimeType = "image/jpeg"

    // Does not do a commit.
    func upload() {
        Log.msg("NoteImage upload")
        
        // See https://www.sitepoint.com/web-foundations/mime-types-complete-list/
        let attr = SMSyncAttributes(withUUID: NSUUID(UUIDString: self.uuid!)!, mimeType: NoteImage.mimeType, andRemoteFileName: self.uuid! + ".jpg")
        
        SMSyncServer.session.uploadImmutableFile(self.fileURL!, withFileAttributes: attr)
    }
    
    // Does not do a commit.
    class func newObjectAndMakeUUID(withURL url: SMRelativeLocalURL?=nil, makeUUIDAndUpload: Bool) -> NSManagedObject {
        let noteImage = CoreData.sessionNamed(CoreDataSession.name).newObjectWithEntityName(self.entityName()) as! NoteImage
        
        if makeUUIDAndUpload {
            noteImage.uuid = UUID.make()
        }
        
        noteImage.fileURL = url
        
        CoreData.sessionNamed(CoreDataSession.name).saveContext()

        if makeUUIDAndUpload {
            noteImage.upload()
        }
        
        return noteImage
    }
    
    class func newObject() -> NSManagedObject {
        return self.newObjectAndMakeUUID(makeUUIDAndUpload: false)
    }
    
    // Returns nil if no NoteImage found.
    class func fetch(withUUID uuid:NSUUID) -> NoteImage? {
        return CoreData.fetchObjectWithUUID(uuid.UUIDString, usingUUIDKey: UUID_KEY, fromEntityName: self.entityName(), coreDataSession: CoreData.sessionNamed(CoreDataSession.name)) as? NoteImage
    }

    // Also removes the file at the fileURL. Does not do a SMSyncServer commit.
    func removeObject() {
        let uuid = self.uuid!
        let fileURL = self.fileURL!
        
        CoreData.sessionNamed(CoreDataSession.name).removeObject(self)
        
        if CoreData.sessionNamed(CoreDataSession.name).saveContext() {
        
            let fileMgr = NSFileManager.defaultManager()
            do {
                try fileMgr.removeItemAtURL(fileURL)
            } catch (let error) {
                Log.error("Error removing file: \(error)")
            }
            
            SMSyncServer.session.deleteFile(NSUUID(UUIDString: uuid)!)
        }
    }
}
