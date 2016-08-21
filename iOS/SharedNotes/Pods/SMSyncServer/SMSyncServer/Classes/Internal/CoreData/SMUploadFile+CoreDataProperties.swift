//
//  SMUploadFile+CoreDataProperties.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 5/10/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

import Foundation
import CoreData

extension SMUploadFile {

    @NSManaged var deleteLocalFileAfterUpload: NSNumber?
    @NSManaged var internalRelativeLocalURL: NSData?
    @NSManaged var internalUndeleteServerFile: NSNumber?
    @NSManaged var blocks: NSOrderedSet?

}
