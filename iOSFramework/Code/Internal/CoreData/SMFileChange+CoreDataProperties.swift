//
//  SMFileChange+CoreDataProperties.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 3/27/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

import Foundation
import CoreData

extension SMFileChange {

    @NSManaged var deleteLocalFileAfterUpload: NSNumber?
    @NSManaged var deletion: NSNumber?
    @NSManaged var internalRelativeLocalURL: NSData?
    @NSManaged var changedFile: SMLocalFile?

}
