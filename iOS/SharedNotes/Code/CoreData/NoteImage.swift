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
            CoreData.setSMRelativeLocalURL(newValue, toCoreDataProperty: &self.internalRelativeLocalURL, coreDataSessionName: CoreDataExtras.sessionName)
        }
    }
    
    class func entityName() -> String {
        return "NoteImage"
    }

    static let mimeType = "image/jpeg"

    // Does not do a commit.
    func upload() throws {
        Log.msg("NoteImage upload")
        
        // See https://www.sitepoint.com/web-foundations/mime-types-complete-list/
        let attr = SMSyncAttributes(withUUID: NSUUID(UUIDString: self.uuid!)!, mimeType: NoteImage.mimeType, andRemoteFileName: self.uuid! + ".jpg")
        
        attr.appMetaData = SMAppMetaData()
        attr.appMetaData![CoreDataExtras.objectDataTypeKey] = CoreDataExtras.objectDataTypeNoteImage
        attr.appMetaData![CoreDataExtras.ownedByNoteUUIDKey] = self.note!.uuid!

        try SMSyncServer.session.uploadImmutableFile(self.fileURL!, withFileAttributes: attr)
    }
    
    // Does not do a commit. Only can throw if makeUUIDAndUpload is true
    class func newObjectAndMakeUUID(withURL url: SMRelativeLocalURL?=nil, ownedBy note:Note?=nil, makeUUIDAndUpload: Bool) throws -> NSManagedObject {
        let noteImage = CoreData.sessionNamed(CoreDataExtras.sessionName).newObjectWithEntityName(self.entityName()) as! NoteImage
        
        if makeUUIDAndUpload {
            noteImage.uuid = UUID.make()
        }
        
        noteImage.fileURL = url
        noteImage.note = note
        
        CoreData.sessionNamed(CoreDataExtras.sessionName).saveContext()

        if makeUUIDAndUpload {
            try noteImage.upload()
        }
        
        return noteImage
    }
    
    class func newObject() -> NSManagedObject {
        return try! self.newObjectAndMakeUUID(makeUUIDAndUpload: false)
    }
    
    // Returns nil if no NoteImage found.
    class func fetch(withUUID uuid:NSUUID) -> NoteImage? {
        return CoreData.fetchObjectWithUUID(uuid.UUIDString, usingUUIDKey: UUID_KEY, fromEntityName: self.entityName(), coreDataSession: CoreData.sessionNamed(CoreDataExtras.sessionName)) as? NoteImage
    }

    // Also removes the file at the fileURL. Does not do a SMSyncServer commit. Only can throw if updateServer is true
    func removeObject(andUpdateServer updateServer:Bool) throws {
        let uuid = self.uuid!
        let fileURL = self.fileURL!
        
        CoreData.sessionNamed(CoreDataExtras.sessionName).removeObject(self)
        
        if CoreData.sessionNamed(CoreDataExtras.sessionName).saveContext() {
        
            let fileMgr = NSFileManager.defaultManager()
            do {
                try fileMgr.removeItemAtURL(fileURL)
            } catch (let error) {
                Log.error("Error removing file: \(error)")
            }
            
            if updateServer {
                try SMSyncServer.session.deleteFile(NSUUID(UUIDString: uuid)!)
            }
        }
    }
}
