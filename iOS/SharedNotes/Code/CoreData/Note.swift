//
//  Note.swift
//  
//
//  Created by Christopher Prince on 5/4/16.
//
//

import Foundation
import CoreData
import SMCoreLib
import SMSyncServer

class Note: NSManagedObject {
    static let DATE_KEY = "internalDateModified"
    static let UUID_KEY = "uuid"

    // Not based on server info-- this is the local time when the data changed.
    var dateModified:NSDate? {
        return self.internalDateModified
    }
    
    // The setter does an upload, but not a commit. When using the setter, must not give a nil value.
    var jsonData:NSData? {
        set {
            self.updateJSON(jsonData: newValue!)
            self.upload()
        }
        
        get {
            return self.internalJSONData
        }
    }

    // See http://stackoverflow.com/questions/477816/what-is-the-correct-json-content-type
    static let mimeType = "application/json"
    
    // Does not do a commit.
    private func upload() {
        Log.msg("Note upload")
        
        // Allowing self.jsonData to be nil so we can sync a new, empty, note to other devices.
        
        let attr = SMSyncAttributes(withUUID: NSUUID(UUIDString: self.uuid!)!, mimeType: Note.mimeType, andRemoteFileName: self.uuid!)
        
        attr.appMetaData = SMAppMetaData()
        attr.appMetaData![CoreDataExtras.objectDataTypeKey] = CoreDataExtras.objectDataTypeNote
        
        SMSyncServer.session.uploadData(self.jsonData, withDataAttributes: attr)
    }
    
    // Call this based on sync-driven changes to the note. Creates the note if needed.
    // TODO: Need some kind of locking here to deal with the possiblity that the user might be modifying the note at the same time as we receive the download.
    class func createOrUpdate(usingUUID uuid:NSUUID, fromFileAtURL fileURL:NSURL) {
        var note = self.fetch(withUUID: uuid)
        if note == nil {
            Log.special("Couldn't find uuid: \(uuid); creating new Note")
            note = (Note.newObjectAndMakeUUID(makeUUIDAndUpload: false) as! Note)
            note!.uuid = uuid.UUIDString
        }
        
        if let jsonData = NSData(contentsOfURL: fileURL) {
            note!.updateJSON(jsonData: jsonData)
        }
        else {
            Log.error("Problem updating note for: \(uuid)")
        }
        
        CoreData.sessionNamed(CoreDataExtras.sessionName).saveContext()
    }
    
    // Also spawns off an upload with the new note contents.
    // TODO: This merge needs to be reconsidered given the JSON structure of the data.
    /*
    func merge(withDownloadedNoteContents downloadedNoteContents:NSURL) {
        guard
            let data = NSData(contentsOfURL: downloadedNoteContents),
            let newNoteContents = String(data: data, encoding: NSUTF8StringEncoding)
        else {
            Assert.badMojo(alwaysPrintThisString: "Could not get note contents!")
            return
        }
        
        let dmp = DiffMatchPatch()
        let mergedResult = dmp.diff_simpleMerge(firstString: self.text!, secondString: newNoteContents)
        print("mergedResult: \(mergedResult)")
        
        // The assignment to .text will also spawn off an upload.
        self.text = mergedResult
    }*/
    
    private func updateJSON(jsonData jsonData:NSData) {
        self.internalJSONData = jsonData
        self.internalDateModified = NSDate()
        CoreData.sessionNamed(CoreDataExtras.sessionName).saveContext()
    }
    
    class func entityName() -> String {
        return "Note"
    }

    class func newObjectAndMakeUUID(makeUUIDAndUpload makeUUIDAndUpload: Bool) -> NSManagedObject {
        let note = CoreData.sessionNamed(CoreDataExtras.sessionName).newObjectWithEntityName(self.entityName()) as! Note
        
        if makeUUIDAndUpload {
            note.uuid = UUID.make()
        }
        
        note.images = NSSet()
        note.internalDateModified = NSDate()
        
        CoreData.sessionNamed(CoreDataExtras.sessionName).saveContext()

        if makeUUIDAndUpload {
            note.upload()
        }
        
        return note
    }
    
    class func newObject() -> NSManagedObject {
        return self.newObjectAndMakeUUID(makeUUIDAndUpload: false)
    }
    
    class func fetchRequestForAllObjects() -> NSFetchRequest? {
        var fetchRequest: NSFetchRequest?
        fetchRequest = CoreData.sessionNamed(CoreDataExtras.sessionName).fetchRequestWithEntityName(self.entityName(), modifyingFetchRequestWith: nil)
        
        if fetchRequest != nil {
            let sortDescriptor = NSSortDescriptor(key: DATE_KEY, ascending: false)
            fetchRequest!.sortDescriptors = [sortDescriptor]
        }
        
        return fetchRequest
    }
    
    // Returns nil if no Note found.
    class func fetch(withUUID uuid:NSUUID) -> Note? {
        return CoreData.fetchObjectWithUUID(uuid.UUIDString, usingUUIDKey: UUID_KEY, fromEntityName: self.entityName(), coreDataSession: CoreData.sessionNamed(CoreDataExtras.sessionName)) as? Note
    }
    
    // Make sure to call this method when removing a Note, so that the change gets propagated to the sync server. In some cases, though the server doesn't need to be updated-- e.g., on a download-deletion.
    func removeObject(andUpdateServer updateServer:Bool) {
        let uuid = self.uuid
        
        // Need to remove any associated images.
        if self.images != nil {
            let images = NSSet(set: self.images!)
            for elem in images {
                let image = elem as! NoteImage
                image.removeObject(andUpdateServer: updateServer)
            }
        }
        
        CoreData.sessionNamed(CoreDataExtras.sessionName).removeObject(self)
        
        if CoreData.sessionNamed(CoreDataExtras.sessionName).saveContext() {
            if updateServer {
                SMSyncServer.session.deleteFile(NSUUID(UUIDString: uuid!)!)
                SMSyncServer.session.commit()
            }
        }
    }
}
