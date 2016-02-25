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
    
    private var fileDiffs:SMFileDiffs?
    private var filesToDownload:[SMServerFile]?
    
    static private let maxTimesToTryRecovery = 3
    static private var numberTimesTriedRecovery:Int = 0
    
    // This is a singleton because we need centralized control over the file download operations.
    internal static let session = SMDownloadFiles()
    
    override private init() {
        super.init()
    }
    
    private var serverOperationId:String?

    private class var mode:SMClientMode {
        set {
            SMSyncServer.mode = newValue
            self.numberTimesTriedRecovery = 0

            switch (newValue) {
            case .InboundTransferRecovery, .DownloadRecovery:
                break
            case .Normal, .NonRecoverableError:
                break
                
            default:
                Assert.badMojo(alwaysPrintThisString: "Yikes: Bad mode value for SMDownloadFiles!")
            }
        }
        
        get {
            return SMSyncServer.mode
        }
    }
    
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
        SMDownloadFiles.mode = .InboundTransferRecovery
        
        SMServerAPI.session.lock() { lockResult in
            if lockResult.error == nil {
                SMServerAPI.session.getFileIndex() { (fileIndex, gfiResult) in
                    if gfiResult.error == nil {
                        // Need to compare server files against our local meta data and see which if any files need to be downloaded.
                        // TODO: There is also the possibility of conflicts: I.e., the same file needing to be downloaded also need to be uploaded.
                        self.fileDiffs = SMFileDiffs(type: .RemoteChanges(serverFileIndex: fileIndex!))
                        self.filesToDownload = self.fileDiffs!.filesToDownload
                        if self.filesToDownload != nil {
                            // There were some files to download. Do the transfer(s) from cloud storage in to the sync server.
                            self.doInboundTransfers()
                        }
                        else {
                            // No files to download. Release the lock.
                            SMServerAPI.session.unlock() { unlockResult in
                                if unlockResult.error == nil {
                                    self.callSyncServerNoFilesToDownload()
                                }
                                else {
                                    Log.error("Failed on unlock: \(unlockResult.error)")
                                    self.recovery()
                                }
                            }
                        }
                    }
                    else {
                        Log.error("Failed on getting file index: \(gfiResult.error)")
                        self.recovery()
                    }
                }
            }
            else if lockResult.returnCode == SMServerConstants.rcLockAlreadyHeld {
                Log.error("Lock already held")
                // We're calling the "NoFilesToDownload" delegate callback. In some sense this is expected, or normal operation, and we haven't been able to check for downloads (due to a lock), so the check for downloads will be done again later when, hopefully, a lock will not be held. However, for debugging purposes, we effectively have no files to download, so report that back.
                self.callSyncServerNoFilesToDownload()
            }
            else {
                // No need to do recovery since we just started. HOWEVER, it is also possible that the lock is held at this point, but we just failed on getting the return code from the server.
                Log.error("Failed on obtaining lock: \(lockResult.error)")
                self.recovery()
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
                Log.error("Failed on startInboundTransfer: \(sitResult.error)")
                self.recovery()
            }
        }
    }
    
    // Start timer to poll the server to check if our operation has succeeded. That check will update our local file meta data if/when the file sync completes successfully.
    private func startToPollForOperationFinish() {
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
                    self.doDownloads(operationResult!)
                
                case SMServerConstants.rcOperationStatusFailedBeforeTransfer, SMServerConstants.rcOperationStatusFailedDuringTransfer, SMServerConstants.rcOperationStatusFailedAfterTransfer:
                    self.recovery()
                    
                default:
                    let msg = "Yikes: Unknown operationStatus: \(operationResult!.status)"
                    Log.msg(msg)
                    self.callSyncServerError(Error.Create(msg))
                }
            }
        }
    }
    
    private func doDownloads(operationResult: SMOperationResult) {
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
        
        SMServerAPI.session.removeOperationId(serverOperationId: self.serverOperationId!) { roiResult in
        
            self.serverOperationId = nil

            if roiResult.error != nil {
                // Not much of an error, but log it.
                Log.error("Failed removing OperationId from server: \(roiResult.error)")
            }

            SMDownloadFiles.mode = .DownloadRecovery

            // Files were transferred from cloud storage to sync server. Download them from the sync server.
            self.doDownloadsAux()
        }
    }
    
    private func doDownloadsAux() {
        // Make a copy of the files to download because in the smServerAPIFileDownloaded delegate method below (see [1]), we're going to remove a file from self.filesToDownload each time a file is downloaded, and we don't want to modify that array while SMServerAPI.session.downloadFiles is using it. We're modifying the self.filesToDownload! each time a file is downloaded to make recovery easier.
        var filesToDownloadCopy = [SMServerFile]()
        filesToDownloadCopy.appendContentsOf(self.filesToDownload!)
        
        SMServerAPI.session.downloadFiles(filesToDownloadCopy) { dfResult in
            if dfResult.error == nil {
                // Done!
                self.callSyncServerDownloadsComplete()
            }
            else {
                Log.error("Failed on downloadFiles: \(dfResult.error)")
                self.recovery()
            }
        }
    }
    
    // MARK: Start: Methods that call delegate methods
    // Don't call the "completion" delegate methods directly; call these methods instead-- so that we ensure serialization/sync is maintained correctly.

    private func callSyncServerDownloadsComplete() {
        Log.msg("Finished downloading files: \(self.fileDiffs!.filesToDownload)")
        
        var downloaded = [(NSURL, SMSyncAttributes)]()
        
        for file in self.fileDiffs!.filesToDownload! {
            // SMServerFile parameter used in call must include mimeType, remoteFileName, version and appFileType if on server.
            Assert.If(nil == file.mimeType, thenPrintThisString: "mimeType not given by server!")
            Assert.If(nil == file.remoteFileName, thenPrintThisString: "remoteFileName not given by server!")
            Assert.If(nil == file.version, thenPrintThisString: "version not given by server!")
        
            let attr = SMSyncAttributes(withUUID: file.uuid)
            attr.appFileType = file.appFileType
            attr.mimeType = file.mimeType
            attr.remoteFileName = file.remoteFileName
            downloaded.append((file.localURL!, attr))
            
            // Hold off on updating the SMLocalFile meta data until we have all of the files downloaded-- to preserve the atomic nature of the transaction.
            
            // Check to see if we already know about this file
            var localFileMetaData:SMLocalFile? = SMLocalFile.fetchObjectWithUUID(file.uuid!.UUIDString)
            
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
        }
        
        self.delegate?.syncServerDownloadsComplete(downloaded)
        
        SMSync.session.startDelayed(currentlyOperating: true)
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
        
        SMDownloadFiles.mode = .NonRecoverableError
        
        SMSync.session.stop()
        self.delegate?.syncServerError(error)
    }
    
    private func callSyncServerRecovery() {
        switch (SMSyncServer.mode) {
        case .InboundTransferRecovery, .DownloadRecovery:
            break
            
        default:
            Assert.badMojo(alwaysPrintThisString: "Not a recovery mode")
        }
        
        self.delegate?.syncServerRecovery(SMSyncServer.mode)
    }
    
    // MARK: End: Methods that call delegate methods
}

// MARK: SMServerAPIDownloadDelegate methods

extension SMDownloadFiles : SMServerAPIDownloadDelegate {
    // [1]. We're modifying the self.filesToDownload array here.
    internal func smServerAPIFileDownloaded(file: SMServerFile) {
        let elementIndexToRemove = self.filesToDownload!.indexOf({
            $0.uuid.UUIDString == file.uuid.UUIDString
        })

        Assert.If(elementIndexToRemove == nil, thenPrintThisString: "Didn't find file in self.filesToDownload")
        self.filesToDownload!.removeAtIndex(elementIndexToRemove!)
    }
}

// MARK: Recovery methods.
extension SMDownloadFiles {
    private func recovery() {
        if SMDownloadFiles.numberTimesTriedRecovery > SMDownloadFiles.maxTimesToTryRecovery {
            Log.error("Failed recovery: Already tried \(SMDownloadFiles.numberTimesTriedRecovery) times, and can't get it to work")
            
            // Yikes! What else can we do? Seems like we've given this our best effort in terms of recovery. Kick the error upwards.
            self.callSyncServerError(Error.Create("Failed to recover from SyncServer error after \(SMDownloadFiles.numberTimesTriedRecovery) recovery attempts"))
            
            return
        }
        
        self.callSyncServerRecovery()
        
        SMSync.session.continueIf({
            return Network.session().connected()
        }, then: {
            // This gets executed if we have network access.
            SMDownloadFiles.numberTimesTriedRecovery++
            
            switch (SMDownloadFiles.mode) {
            case .InboundTransferRecovery:
                self.inboundTransferRecovery()
                
            case .DownloadRecovery:
                self.downloadRecovery()

            default:
                Assert.badMojo(alwaysPrintThisString: "Should not have this recovery mode")
            }
        })
    }
    
    // Only call this from the recovery method.
    private func inboundTransferRecovery() {
        SMServerAPI.session.inboundTransferRecovery { apiResult in
            if (nil == apiResult.error) {
                self.startToPollForOperationFinish()
            }
            else if apiResult.returnCode == SMServerConstants.rcLockNotHeld {
                // The server will *not* have initiated the inbound transfer again. We'll do it ourselves.
                self.checkForDownloadsAux()
            }
            else if apiResult.returnCode == SMServerConstants.rcNoOperationId {
                // No operation id yet, but getting to this point, we will have a lock.
                SMServerAPI.session.unlock() { apiResult in
                    if apiResult.error == nil {
                        self.checkForDownloadsAux()
                    }
                    else {
                        self.recovery()
                    }
                }
            }
            else {
                // Error, but try again later.
                let duration = SMServerNetworking.exponentialFallbackDuration(forAttempt: SMDownloadFiles.numberTimesTriedRecovery)

                TimedCallback.withDuration(duration) {
                    self.recovery()
                }
            }
        }
    }

    // Only call this from the recovery method.
    private func downloadRecovery() {
        // This method will call recovery again if it fails. And .mode is not reset, so we'll accumulate the number of recovery failures.
        self.doDownloadsAux()
    }
}
