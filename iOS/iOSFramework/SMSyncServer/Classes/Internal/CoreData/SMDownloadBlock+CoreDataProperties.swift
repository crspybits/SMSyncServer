//
//  SMDownloadBlock+CoreDataProperties.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 4/9/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

import Foundation
import CoreData

extension SMDownloadBlock {

    @NSManaged var numberBytes: NSNumber?
    @NSManaged var startByteOffset: NSNumber?
    @NSManaged var download: SMDownloadFile?

}
