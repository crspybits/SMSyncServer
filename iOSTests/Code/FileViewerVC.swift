//
//  FileViewerVC.swift
//  NetDb
//
//  Created by Christopher Prince on 12/9/15.
//  Copyright © 2015 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import SMSyncServer
import SMCoreLib

class FileViewerVC : UIViewController {
    // Set this before viewWillAppear
    var file:AppFile?
    var textViewHasChanged = false
    
    private let textView = UITextView()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = UIColor.whiteColor()
        
        self.textView.frame = self.view.frame
        self.textView.font = UIFont.systemFontOfSize(20)
        self.view.addSubview(self.textView)
        self.textView.delegate = self
    }
    
    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Write file with text view contents.
        
        if (self.textViewHasChanged) {
            do {
                try self.textView.text.writeToURL(self.file!.url(), atomically: true, encoding: NSASCIIStringEncoding)
            } catch {
                Log.error("Failed to write file: \(error)!")
            }
            
            let remoteFileName = self.file!.url().lastPathComponent
            let fileAttributes = SMSyncAttributes(withUUID: NSUUID(UUIDString: self.file!.uuid!)!, mimeType: "text/plain", andRemoteFileName: remoteFileName!)
            SMSyncServer.session.uploadImmutableFile(self.file!.url(), withFileAttributes: fileAttributes)
            Log.msg("File \(self.file!.fileName) has changed")
        }
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        
        self.title = self.file!.fileName
        
        // Need to load the file.
        
        let fileContents: String?
        do {
            try fileContents = NSString(contentsOfURL: self.file!.url(), encoding: NSASCIIStringEncoding) as String
        } catch _ {
            fileContents = nil
            Log.error("Failed to read file!")
        }
        
        self.textView.text = fileContents
    }
}

extension FileViewerVC : UITextViewDelegate {
    func textViewDidChange(textView: UITextView) {
        self.textViewHasChanged = true
    }
}

