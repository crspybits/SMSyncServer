//
//  SMFileChange+CoreDataProperties.swift
//  
//
//  Created by Christopher Prince on 3/26/16.
//
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

import Foundation
import CoreData

extension SMFileChange {

    @NSManaged var deleteLocalFileAfterUpload: NSNumber?
    @NSManaged var deletion: NSNumber?
    @NSManaged var filePath: String?
    @NSManaged var filePathBaseURLType: NSNumber?
    @NSManaged var changedFile: SMLocalFile?

}
