//
//  SMExtras.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 5/28/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation

class SMExtras {
    /* Running into an issue here when I try to convert the fileVersion out of the dictionary directly to an Int:
    
    2015-12-10 07:17:32 +0000: [fg0,0,255;Didn't get an Int for fileVersion: Optional<AnyObject>[; [create(fromDictionary:) in SMSyncServer.swift, line 69]
    2015-12-10 07:17:32 +0000: [fg0,0,255;Error: Optional(Error Domain= Code=0 "Bad file index object!" UserInfo={NSLocalizedDescription=Bad file index object!})[; [getFileIndexAction() in Settings.swift, line 82]
    
    Apparently, an Int is not an object in Swift http://stackoverflow.com/questions/25449080/swift-anyobject-is-not-convertible-to-string-int
    And actually, despite the way it looks:
    {
        cloudFileName = "upload.txt";
        deleted = 0;
        fileId = "ADB50CE8-E254-44A0-B8C4-4A3A8240CCB5";
        fileVersion = 8;
        lastModified = "2015-12-09T04:55:05.866Z";
        mimeType = "text/plain";
    }
    fileVersion is really a string in the dictionary. Odd. http://stackoverflow.com/questions/32616309/convert-anyobject-to-an-int
    */
    class func getIntFromDictValue(responseValue:AnyObject?) -> Int? {
        // Don't know why but sometimes I'm getting a NSString value back from the server, and sometimes I'm getting an NSNumber value back. Try both.
        
        if let intString = responseValue as? NSString {
            return intString.integerValue
        }
        
        if let intNumber = responseValue as? NSNumber {
            return intNumber.integerValue
        }
        
        return nil
    }
}