//
//  DownloadDeletion.swift
//  Tests
//
//  Created by Christopher Prince on 3/3/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import XCTest

class DownloadDeletion: BaseClass {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
            
    // TODO: Server file has been deleted, so download causes deletion of file on app/client. NOTE: This isn't yet handled by SMFileDiffs.
}
