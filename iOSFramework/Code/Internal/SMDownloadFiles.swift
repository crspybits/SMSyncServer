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
        SMSync.session.startIf({
            return Network.session().connected()
        }, then: {
            self.pollForDownloadsAux()
        })
    }
    
    private func pollForDownloadsAux() {
        SMServerAPI.session.lock() { (error) in
            if error == nil {
                SMServerAPI.session.getFileIndex() { (fileIndex, error) in
                    if error == nil {
                        // Need to compare server files against our local meta data and see which if any files need to be downloaded.
                        // TODO: There is also the possiblity of conflicts: I.e., the same file needing to be downloaded also need to be uploaded.
                        let fileDiffs = SMFileDiffs(type: .RemoteChanges(serverFileIndex: fileIndex!))
                        if let downloadFiles = fileDiffs.filesToDownload() {
                            
                        }
                        else {
                            // No files to download. Release the lock.
                            SMServerAPI.session.unlock() { error in
                                if error == nil {
                                    SMSync.session.startDelayed(
                                        currentlyOperating: true)
                                }
                                else {
                                    Log.error("Failed on unlock")
                                    // TODO: Recovery: Need to remove lock.
                                }
                            }
                        }
                    }
                    else {
                        // TODO: Recovery: Need to remove lock.
                        Log.error("Failed on getFileIndex")
                        // TODO: Need to .Stop operations.
                    }
                }
            }
            else {
                // No need to do recovery since we just started. It is also possible that the lock is held at this point.
                Log.error("Failed on obtaining lock")
                // TODO: Need to .Stop operations.
            }
        }
    }
}
