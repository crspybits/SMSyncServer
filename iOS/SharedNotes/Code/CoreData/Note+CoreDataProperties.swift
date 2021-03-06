//
//  Note+CoreDataProperties.swift
//  SharedNotes
//
//  Created by Christopher Prince on 5/22/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

import Foundation
import CoreData

extension Note {

    @NSManaged var internalDateModified: NSDate?
    @NSManaged var internalJSONData: NSData?
    @NSManaged var uuid: String?
    @NSManaged var images: NSSet?

}
