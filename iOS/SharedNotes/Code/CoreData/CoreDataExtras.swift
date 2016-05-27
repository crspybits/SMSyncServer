//
//  CoreDataExtras.swift
//  SharedNotes
//
//  Created by Christopher Prince on 5/4/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation

class CoreDataExtras {
    static let sessionName = "SharedNotes"
    
    static let objectDataTypeKey = "DataType"
    // Data type values
    static let objectDataTypeNote = "Note"
    static let objectDataTypeNoteImage = "NoteImage"

    static let ownedByNoteUUIDKey = "OwnedBy"
    // Value is a UUID string
}