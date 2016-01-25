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
    private var checkIfUploadOperationFinishedTimer:RepeatingTimer?
    private static let TIME_INTERVAL_TO_CHECK_IF_OPERATION_SUCCEEDED_S:Float = 5
    private var numberInboundTransfersExpected = 0
    
    // This is a singleton because we need centralized control over the file download operations.
    internal static let session = SMDownloadFiles()
    
    override private init() {
        super.init()
    }
    
    private var serverOperationId:String?
    
    internal weak var delegate:SMSyncServerDelegate?

    internal func checkForDownloads() {
        SMSync.session.startIf({
            return Network.session().connected()
        }, then: {
            self.checkForDownloadsAux()
        })
    }
    
    private func checkForDownloadsAux() {
        SMServerAPI.session.lock() { (error) in
            if error == nil {
                SMServerAPI.session.getFileIndex() { (fileIndex, error) in
                    if error == nil {
                        // Need to compare server files against our local meta data and see which if any files need to be downloaded.
                        // TODO: There is also the possiblity of conflicts: I.e., the same file needing to be downloaded also need to be uploaded.
                        let fileDiffs = SMFileDiffs(type: .RemoteChanges(serverFileIndex: fileIndex!))
                        if let downloadFiles = fileDiffs.filesToDownload() {
                            self.doDownloads(downloadFiles)
                        }
                        else {
                            // No files to download. Release the lock.
                            SMServerAPI.session.unlock() { error in
                                if error == nil {
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
            else {
                // No need to do recovery since we just started. It is also possible that the lock is held at this point.
                Log.error("Failed on obtaining lock")
                // TODO: Need to .Stop operations.
            }
        }
    }
    
    private func doDownloads(filesToDownload:[SMServerFile]) {
        self.numberInboundTransfersExpected = filesToDownload.count
        
        SMServerAPI.session.startInboundTransfer(filesToDownload) { (theServerOperationId, returnCode, error) in
            if error == nil {
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

        self.checkIfUploadOperationFinishedTimer = RepeatingTimer(interval: SMDownloadFiles.TIME_INTERVAL_TO_CHECK_IF_OPERATION_SUCCEEDED_S, selector: "pollIfFileOperationFinished", andTarget: self)
        self.checkIfUploadOperationFinishedTimer!.start()
    }
    
    // PRIVATE
    // TODO: How do we know if we've been checking for too long?
    internal func pollIfFileOperationFinished() {
        Log.msg("checkIfFileOperationFinished")
        self.checkIfUploadOperationFinishedTimer!.cancel()
        
        SMServerAPI.session.checkOperationStatus(serverOperationId: self.serverOperationId!) {operationResult, error in
            if (error != nil) {
                // TODO: How many times to check/recheck and still get an error?
                Log.error("Yikes: Error checking operation status: \(error)")
                self.checkIfUploadOperationFinishedTimer!.start()
            }
            else {
                // TODO: Deal with other collection of operation status here.
                
                switch (operationResult!.status) {
                case SMServerConstants.rcOperationStatusInProgress:
                    Log.msg("Operation still in progress")
                    self.checkIfUploadOperationFinishedTimer!.start()
                    
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
        }
        
        //SMUploadFiles.setMode(.Normal)
        
        SMServerAPI.session.removeOperationId(serverOperationId: self.serverOperationId!) { error in
        
            self.serverOperationId = nil

            if (error != nil) {
                // Not much of an error, but log it.
                Log.file("Failed removing OperationId from server: \(error)")
            }
            
            // Really: Have to download the files, one by one now.
            // TEMPORARY
            let url = NSURL()
            let attr = SMSyncAttributes(withUUID: NSUUID())
            self.callSyncServerSingleFileDownloadComplete(url, withFileAttributes: attr)
            // TEMPORARY
        }
    }
    
    // MARK: Start: Methods that call delegate methods
    // Don't call the "completion" delegate methods directly; call these methods instead-- so that we ensure serialization/sync is maintained correctly.

    private func callSyncServerSingleFileDownloadComplete(localFile:NSURL, withFileAttributes attr: SMSyncAttributes) {
        SMSync.session.startDelayed(currentlyOperating: true)
        self.delegate?.syncServerSingleFileDownloadComplete(localFile, withFileAttributes: attr)
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
