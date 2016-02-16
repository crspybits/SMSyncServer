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

/* 
This class uses RepeatingTimer. It must have NSObject as a base class.
*/
internal class SMDownloadFiles : NSObject {
    private var checkIfInboundTransferOperationFinishedTimer:RepeatingTimer?
    private static let TIME_INTERVAL_TO_CHECK_IF_OPERATION_SUCCEEDED_S:Float = 5
    private var numberInboundTransfersExpected = 0
    private var filesToDownload:[SMServerFile]?
    
    // This is a singleton because we need centralized control over the file download operations.
    internal static let session = SMDownloadFiles()
    
    override private init() {
        super.init()
    }
    
    private var serverOperationId:String?
    
    internal weak var delegate:SMSyncServerDelegate?
    
    internal func appLaunchSetup() {
        SMServerAPI.session.downloadDelegate = self
    }

    internal func checkForDownloads() {
        SMSync.session.startIf({
            return Network.session().connected()
        }, then: {
            self.checkForDownloadsAux()
        })
    }
    
    private func checkForDownloadsAux() {
        SMServerAPI.session.lock() { lockResult in
            if lockResult.error == nil {
                SMServerAPI.session.getFileIndex() { (fileIndex, gfiResult) in
                    if gfiResult.error == nil {
                        // Need to compare server files against our local meta data and see which if any files need to be downloaded.
                        // TODO: There is also the possiblity of conflicts: I.e., the same file needing to be downloaded also need to be uploaded.
                        let fileDiffs = SMFileDiffs(type: .RemoteChanges(serverFileIndex: fileIndex!))
                        self.filesToDownload = fileDiffs.filesToDownload()
                        if self.filesToDownload != nil {
                            // There were some files to download.
                            self.doInboundTransfers()
                        }
                        else {
                            // No files to download. Release the lock.
                            SMServerAPI.session.unlock() { unlockResult in
                                if unlockResult.error == nil {
                                    self.callSyncServerNoFilesToDownload()
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
            else if lockResult.returnCode == SMServerConstants.rcLockAlreadyHeld {
                Log.error("Lock already held")
                // We're calling the "NoFilesToDownload" delegate callback.In some sense this is expected, or normal operation, and we haven't been able to check for downloads (due to a lock), so the check for downloads will be done again later when, hopefully, a lock will not be held. However, for debugging purposes, we effectively have no files to download, so report that back.
                self.callSyncServerNoFilesToDownload()
            }
            else {
                // No need to do recovery since we just started. It is also possible that the lock is held at this point.
                Log.error("Failed on obtaining lock")
                // TODO: Need to .Stop operations.
            }
        }
    }
    
    private func doInboundTransfers() {
        self.numberInboundTransfersExpected = self.filesToDownload!.count
        
        SMServerAPI.session.startInboundTransfer(self.filesToDownload!) { (theServerOperationId, sitResult) in
            if sitResult.error == nil {
                self.serverOperationId = theServerOperationId
                self.startToPollForOperationFinish()
            }
            else {
                // No need to do recovery since we just started. It is also possible that the lock is held at this point.
                Log.error("Failed on startInboundTransfer")
                // TODO: Need to .Stop operations.
            }
        }
    }
    
    // Start timer to poll the server to check if our operation has succeeded. That check will update our local file meta data if/when the file sync completes successfully.
    private func startToPollForOperationFinish() {
        //SMUploadFiles.setMode(.OutboundTransferRecovery)

        self.checkIfInboundTransferOperationFinishedTimer = RepeatingTimer(interval: SMDownloadFiles.TIME_INTERVAL_TO_CHECK_IF_OPERATION_SUCCEEDED_S, selector: "pollIfFileOperationFinished", andTarget: self)
        self.checkIfInboundTransferOperationFinishedTimer!.start()
    }
    
    // PRIVATE
    // TODO: How do we know if we've been checking for too long?
    internal func pollIfFileOperationFinished() {
        Log.msg("checkIfFileOperationFinished")
        self.checkIfInboundTransferOperationFinishedTimer!.cancel()
        
        SMServerAPI.session.checkOperationStatus(serverOperationId: self.serverOperationId!) {operationResult, cosResult in
            if (cosResult.error != nil) {
                // TODO: How many times to check/recheck and still get an error?
                Log.error("Yikes: Error checking operation status: \(cosResult.error)")
                self.checkIfInboundTransferOperationFinishedTimer!.start()
            }
            else {
                // TODO: Deal with other collection of operation status here.
                
                switch (operationResult!.status) {
                case SMServerConstants.rcOperationStatusInProgress:
                    Log.msg("Operation still in progress")
                    self.checkIfInboundTransferOperationFinishedTimer!.start()
                    
                case SMServerConstants.rcOperationStatusSuccessfulCompletion:
                    self.wrapUpOperation(operationResult!)
                
                case SMServerConstants.rcOperationStatusFailedBeforeTransfer, SMServerConstants.rcOperationStatusFailedDuringTransfer, SMServerConstants.rcOperationStatusFailedAfterTransfer:
                    // This will do more work than necessary (e.g., checking with the server again for operation status), but it handles these three cases.
                    Assert.badMojo(alwaysPrintThisString: "Not implemented yet")
                    
                default:
                    let msg = "Yikes: Unknown operationStatus: \(operationResult!.status)"
                    Log.msg(msg)
                    self.callSyncServerError(Error.Create(msg))
                }
            }
        }
    }
    
    private func wrapUpOperation(operationResult: SMOperationResult) {
        Log.msg("Operation succeeded: \(operationResult.count) cloud storage operations performed")
        
        // This is actually not an error-- it can just reflect a retry of a transfer that failed the first time.
        if operationResult.count == self.numberInboundTransfersExpected {
            Log.msg("Number of inbound transfers: \(operationResult.count)")
        }
        else if (operationResult.count > self.numberInboundTransfersExpected) {
            Log.warning("Number of inbound transfers (\(operationResult.count)) was greater than expected: \(self.numberInboundTransfersExpected)-- server may be doing retries")
        }
        else {
            self.callSyncServerError(Error.Create("Something bad is going on: number inbound transfers expected \(self.numberInboundTransfersExpected) was greater than operation count \(operationResult.count)"))
            return
        }
        
        //SMUploadFiles.setMode(.Normal)
        
        SMServerAPI.session.removeOperationId(serverOperationId: self.serverOperationId!) { roiResult in
        
            self.serverOperationId = nil

            if roiResult.error != nil {
                // Not much of an error, but log it.
                Log.file("Failed removing OperationId from server: \(roiResult.error)")
            }
            
            // Files were transferred from cloud storage to sync server. Download them from the sync server.
            SMServerAPI.session.downloadFiles(self.filesToDownload!) { dfResult in
                if dfResult.error == nil {
                    // Done!
                    self.callSyncServerAllDownloadsComplete()
                }
                else {
                    // TODO: Initiate recovery. Retry download again? We have no evidence this was a server API error, nor is this a recovery error at this point (i.e., so we don't want to just call the delegate error method).
                    Log.error("Failed on downloadFiles")
                }
            }
        }
    }
    
    // MARK: Start: Methods that call delegate methods
    // Don't call the "completion" delegate methods directly; call these methods instead-- so that we ensure serialization/sync is maintained correctly.

    private func callSyncServerSingleFileDownloadComplete(localFile:NSURL, withFileAttributes attr: SMSyncAttributes) {
        Log.msg("Finished downloading file with UUID: \(attr.uuid)")
        self.delegate?.syncServerSingleFileDownloadComplete(localFile, withFileAttributes: attr)
    }
    
    private func callSyncServerAllDownloadsComplete() {
        SMSync.session.startDelayed(currentlyOperating: true)
        self.delegate?.syncServerAllDownloadsComplete()
    }

    private func callSyncServerNoFilesToDownload() {
        SMSync.session.startDelayed(currentlyOperating: true)
#if DEBUG
        self.delegate?.syncServerNoFilesToDownload()
#endif
    }
    
    private func callSyncServerError(error:NSError) {
        // We've had an API error. Don't try to do any pending next operation.
        
        // Set the mode to .NonRecoverableError so that if the app restarts we don't try to recover again. This also has the additional effect of forcing the caller of this class to do something to recover. i.e., at least to call the resetFromError method.
        // SMUploadFiles.setMode(.NonRecoverableError)
        
        SMSync.session.stop()
        self.delegate?.syncServerError(error)
    }
    
    // MARK: End: Methods that call delegate methods
}


// MARK: SMServerAPIDownloadDelegate methods

extension SMDownloadFiles : SMServerAPIDownloadDelegate {
    // SMServerFile parameter used in call must include mimeType, remoteFileName, version and appFileType if on server
    internal func smServerAPIFileDownloaded(file: SMServerFile) {
        var localFileMetaData:SMLocalFile?
        
        Assert.If(nil == file.mimeType, thenPrintThisString: "mimeType not given by server!")
        Assert.If(nil == file.remoteFileName, thenPrintThisString: "remoteFileName not given by server!")
        Assert.If(nil == file.version, thenPrintThisString: "version not given by server!")
        
        // Check to see if we already know about this file
        localFileMetaData = SMLocalFile.fetchObjectWithUUID(file.uuid!.UUIDString)
        
        if nil == localFileMetaData {
            // We need to create meta data to represent the downloaded file locally to the SMSyncServer.
            localFileMetaData = SMLocalFile.newObject() as? SMLocalFile
            localFileMetaData!.uuid = file.uuid.UUIDString
            localFileMetaData!.mimeType = file.mimeType
            localFileMetaData!.appFileType = file.appFileType
            localFileMetaData!.remoteFileName = file.remoteFileName
        }
        
        // Update version in any event.
        localFileMetaData!.localVersion = file.version

        CoreData.sessionNamed(SMCoreData.name).saveContext()
        
        let attr = SMSyncAttributes(withUUID: file.uuid)
        attr.appFileType = file.appFileType
        attr.mimeType = file.mimeType
        attr.remoteFileName = file.remoteFileName
        
        self.callSyncServerSingleFileDownloadComplete(file.localURL!, withFileAttributes: attr)
    }
}
