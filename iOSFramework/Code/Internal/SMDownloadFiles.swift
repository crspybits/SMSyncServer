//
//  SMDownloadFiles.swift
//  NetDb
//
//  Created by Christopher Prince on 1/14/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

// Algorithms for downloading files from the SyncServer.
// This class' resources are either private or internal. It is not intended for use by classes outside of the SMSyncServer framework.

import Foundation
import SMCoreLib

internal class SMDownloadFiles {
    // This is a singleton because we need centralized control over the file download operations.
    internal static let session = SMDownloadFiles()
    
    private var serverOperationId:String?
    
    internal func pollForDownloads() {
        SMServerAPI.session.startDownloads() { (operationId, error) in
            if error == nil {
                self.serverOperationId = operationId
                
                SMServerAPI.session.getFileIndex() { (fileIndex, error) in
                    if error == nil {
                        // Need to compare server files against our local meta data and see which if any files need to be downloaded.
                        // There is also the possiblity of (a) some of our local files needing to be uploaded, and (b) conflicts: I.e., the same file needing to be downloaded also need to be uploaded.
                    }
                    else {
                        // No need to do recovery since we just started. 
                        Log.error("Failed on getFileIndex")
                        // TODO: Need to .Stop operations.
                    }
                }
            }
            else {
                // No need to do recovery since we just started. 
                Log.error("Failed on startDownloads")
                // TODO: Need to .Stop operations.
            }
        }
    }
}
