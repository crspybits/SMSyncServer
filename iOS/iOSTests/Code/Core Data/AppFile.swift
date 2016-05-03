//
//  AppFile.swift
//  Tests
//
//  Created by Christopher Prince on 2/22/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import SMCoreLib

// I had UUID_KEY as a class static let member, but this caused a linker error: "A declaration cannot be both 'final' and 'dynamic'"
// See also http://stackoverflow.com/questions/29814706/a-declaration-cannot-be-both-final-and-dynamic-error-in-swift-1-2
private let UUID_KEY = "uuid"

extension AppFile {
    class func fetchObjectWithUUID(uuid:String) -> AppFile? {
        let managedObject = CoreData.fetchObjectWithUUID(uuid, usingUUIDKey: UUID_KEY, fromEntityName: AppFile.entityName(), coreDataSession: CoreData.sessionNamed(CoreDataTests.name))
        return managedObject as? AppFile
    }
}