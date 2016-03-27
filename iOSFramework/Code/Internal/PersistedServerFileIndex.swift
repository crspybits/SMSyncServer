//
//  PersistedServerFileIndex.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 3/2/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import SMCoreLib

internal class PersistedServerFileIndex {

    // This is a persistent variable. I.e., it will be stored in NSUserDefaults. I normally make these `static` to document the fact that they are not really instance variables, but I'm going to want multiple instances of PersistedServerFileIndex, each with their own persistent values.
    var _serverFileIndex:SMPersistItemArray!
    
    init(withUserDefaultsName userDefaultsName:String) {
        self._serverFileIndex = SMPersistItemArray(name: userDefaultsName, initialArrayValue: [], persistType: .UserDefaults)
    }
    
    // If there are no files, returns nil.
    internal var value:[SMServerFile]? {
        set {
            // Lovely lovely conversion from a Swift array to an NSMutableArray. See also http://stackoverflow.com/questions/25837539/how-can-i-cast-an-nsmutablearray-to-a-swift-array-of-a-specific-type
            // This fails
            /*
            if let mutableArray = newValue! as NSArray as? NSMutableArray {
                SMDownloadFiles._serverFileIndex.arrayValue = mutableArray
            }
            else {
                Assert.badMojo(alwaysPrintThisString: "Could not convert!")
            }
            */
            
            // This is pretty crude. But it works.
            let mutableArray = NSMutableArray()
            if nil != newValue {
                for serverFile in newValue! {
                    mutableArray.addObject(serverFile)
                }
            }
            self._serverFileIndex.arrayValue = mutableArray
        }
        
        get {
            // Interestingly, though-- in contrast to the above setter, the following does work:
            if let serverFiles = self._serverFileIndex.arrayValue as NSArray as? [SMServerFile] {
                if serverFiles.count == 0 {
                    return nil
                }
                else {
                    return serverFiles
                }
            }
            else {
                Assert.badMojo(alwaysPrintThisString: "Could not convert!")
                return nil
            }
        }
    }
}
