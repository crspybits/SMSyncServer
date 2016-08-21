//
//  SMFiles.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 1/30/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

// Misc internal file operations.

import Foundation
import SMCoreLib

class SMFiles {

    // Creates a file within the Documents/<SMAppConstants.tempDirectory> directory. If the URL returned is non-nil, the file will have been created, and zero length upon return.
    class func createTemporaryRelativeFile() -> SMRelativeLocalURL? {
        
        // I'm going to use a directory within /Documents and not the NSTemporaryDirectory because I want control over when these files are deleted. It is possible that it will take any number of days for these files to be uploaded. I don't want to take the chance that they will be deleted before I'm done with them.
        
        let tempDirectory = FileStorage.pathToItem(SMAppConstants.tempDirectory)
        let tempDirURL = NSURL(fileURLWithPath: tempDirectory)
        
        // Don't let these temporary files be backed up to iCloud-- Apple doesn't like this (e.g., when reviewing apps).
        if FileStorage.createDirectoryIfNeeded(tempDirURL) {
            let result = FileStorage.addSkipBackupAttributeToItemAtURL(tempDirURL)
            Assert.If(!result, thenPrintThisString: "Could not addSkipBackupAttributeToItemAtURL")
        }
        
        let tempFileName = FileStorage.createTempFileNameInDirectory(tempDirectory, withPrefix: "SMSyncServer", andExtension: "dat")
        let fileNameWithPath = tempDirectory + "/" + tempFileName
        Log.msg(fileNameWithPath);
        
        let relativeLocalFile = SMRelativeLocalURL(withRelativePath: SMAppConstants.tempDirectory + "/" + tempFileName, toBaseURLType: .DocumentsDirectory)

        if NSFileManager.defaultManager().createFileAtPath(relativeLocalFile!.path!, contents: nil, attributes: nil) {
            return relativeLocalFile
        }
        else {
            Log.error("Could not create file: \(fileNameWithPath)")
            return nil
        }
    }
    
#if DEBUG
    // Returns true iff the files are bytewise identical.
    class func compareFiles(file1 file1:NSURL, file2:NSURL) -> Bool {
        // Not the best (consumes lots of RAM), but good enough for now.
        let file1Data = NSData(contentsOfURL: file1)
        let file2Data = NSData(contentsOfURL: file2)
        return file1Data!.isEqualToData(file2Data!)
    }
    
    // Returns true iff the files are bytewise identical.
    class func compareFile(file file:NSURL, andString string:String) -> Bool {
        // Not the best (consumes lots of RAM), but good enough for now.
        let fileData = NSData(contentsOfURL: file)
        let stringData = string.dataUsingEncoding(NSUTF8StringEncoding)
        return fileData!.isEqualToData(stringData!)
    }
#endif
}
