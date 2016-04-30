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
This class uses RepeatingTimer. Seems like it must have NSObject as a base class.
*/
internal class SMDownloadFiles : NSObject {
    // For error recovery, it's useful to have the operationId if we have one.
    private static let _operationId = SMPersistItemString(name: "SMDownloadFiles.OperationId", initialStringValue: "", persistType: .UserDefaults)
    
    private var serverOperationId:String? {
        get {
            if (SMDownloadFiles._operationId.stringValue == "") {
                return nil
            }
            else {
                return SMDownloadFiles._operationId.stringValue
            }
        }
        set {
            if (nil == newValue) {
                SMDownloadFiles._operationId.stringValue = ""
            }
            else {
                SMDownloadFiles._operationId.stringValue = newValue!
            }
        }
    }
    
    private var checkIfInboundTransferOperationFinishedTimer:RepeatingTimer?
    private static let TIME_INTERVAL_TO_CHECK_IF_OPERATION_SUCCEEDED_S:Float = 5
    
    private let MAX_NUMBER_ATTEMPTS = 3
    private var numberErrorsOnSetupInboundTransfer = 0
    private var numberErrorsOnStartInboundTransfer = 0
    private var numberCheckOperationStatusError = 0
    private var numberRevertBackToStartInboundTransfer = 0
    private var numberErrorsRemovingOperationId = 0
    private var numberErrorsDownloadingFiles = 0
    
    private func resetAttempts() {
        self.numberErrorsOnSetupInboundTransfer = 0
        self.numberErrorsOnStartInboundTransfer = 0
        self.numberCheckOperationStatusError = 0
        self.numberRevertBackToStartInboundTransfer = 0
        self.numberErrorsRemovingOperationId = 0
        self.numberErrorsDownloadingFiles = 0
    }
    
    // This is a singleton because we need centralized control over the file download operations.
    internal static let session = SMDownloadFiles()
    
    // Operations and their priority.
    private var downloadOperations:[()-> Bool?]!
    
    override private init() {
        super.init()
        
        unowned let unownedSelf = self
        
        /* Download execution follows two paths:
        1) If there are file downloads, all of the download steps are followed.
        2) If there are no file downloads, but there are file deletions (and possibly file conflicts), then steps are skipped until doCallbacks. The .NoFileDownloads SMDownloadStartup.StartupStage is used to control this.
        */
        self.downloadOperations = [
            // I've separated Setup and Start to make recovery easier.
            unownedSelf.doSetupInboundTransfers,
            unownedSelf.doStartInboundTransfers,
            
            unownedSelf.startToPollForOperationFinish,
            unownedSelf.removeOperationId,
            unownedSelf.doFileDownloads,
            unownedSelf.doCallbacks
        ]
    }
    
    internal weak var syncServerDelegate:SMSyncServerDelegate?
    internal weak var syncControlDelegate:SMSyncControlDelegate?
    
    internal func appLaunchSetup() {
        SMServerAPI.session.downloadDelegate = self
    }

    func doDownloadOperations() {
        self.resetAttempts()
        self.downloadControl()
    }
    
    /*
    private func processPendingDownloads() {
        Assert.badMojo(alwaysPrintThisString: "TO BE IMPLEMENTED!")
        
        if let conflicts = SMQueues.current().downloadConflicts() {
            Assert.If(!SMSyncControl.haveServerLock.boolValue, thenPrintThisString: "Don't have server lock!")
            self.processPendingConflicts(conflicts)
        }
        
        // Process other download too!!
    }
    */
    
    // Control for operations. Each call to this control method does at most one of the asynchronous operations.
    private func downloadControl() {
        for downloadOperation in self.downloadOperations {
            let successfulOperation = downloadOperation()
            
            // If there was an error (nil), or if the operation was successful, then we're done with this go-around. Most of the the operations run asynchronously, when successful, and will callback as needed to downloadControl() to do the next operation.
            if successfulOperation == nil || successfulOperation! {
                break
            }
        }
    }
    
    private func doSetupInboundTransfers() -> Bool? {
        let inboundTransfers = SMQueues.current().getBeingDownloadedChanges(
            .DownloadFile, operationStage: .CloudStorage) as? [SMDownloadFile]
        if nil == inboundTransfers {
            return false
        }
        
        let inboundTransferServerFiles = SMDownloadFile.convertToServerFiles(inboundTransfers!)
        if nil == inboundTransferServerFiles {
            self.callSyncControlModeChange(.InternalError(Error.Create("Could not convert inbound to server files")))
            return nil
        }
        
        SMServerAPI.session.setupInboundTransfer(inboundTransferServerFiles!) { (sitResult) in
            if SMTest.If.success(sitResult.error, context: .SetupInboundTransfer) {
                
                for inboundTransfer in inboundTransfers! {
                    inboundTransfer.operationStage = .ServerDownload
                }
                
                self.downloadControl()
            }
            else {
                Log.error("Failed on setupInboundTransfer: \(sitResult.error)")
                self.retryIfNetworkConnected(
                    &self.numberErrorsOnSetupInboundTransfer, errorSpecifics: "failed on setting up inbound transfer") {
                    self.downloadControl()
                }
            }
        }
        
        return true
    }
    
    private func doStartInboundTransfers() -> Bool? {
        let startUp = self.getStartup(.StartInboundTransfer)
        if startUp == nil {
            return false
        }
        
        SMServerAPI.session.startInboundTransfer() { (theServerOperationId, sitResult) in
            if SMTest.If.success(sitResult.error, context: .InboundTransfer) {
                self.serverOperationId = theServerOperationId
                startUp!.startupStage = .InboundTransferWait
                self.downloadControl()
            }
            else {
                Log.error("Failed on startInboundTransfer: \(sitResult.error)")
                self.retryIfNetworkConnected(
                    &self.numberErrorsOnStartInboundTransfer, errorSpecifics: "failed on starting inbound transfer") {
                    self.downloadControl()
                }
            }
        }
        
        return true
    }
    
    private func getStartup(stage:SMDownloadStartup.StartupStage?) -> SMDownloadStartup? {
        if let startupUpArray = SMQueues.current().getBeingDownloadedChanges(
            .DownloadStartup) as? [SMDownloadStartup] {
            Assert.If(startupUpArray.count != 1, thenPrintThisString: "Not exactly one startup object")
            
            let startUp = startupUpArray[0]
            
            if nil == stage || startUp.startupStage == stage {
                return startUp
            }
        }
        
        return nil
    }
    
    // Start timer to poll the server to check if our operation has succeeded. That check will update our local file meta data if/when the file sync completes successfully.
    private func startToPollForOperationFinish() -> Bool? {
        let startUp = self.getStartup(.InboundTransferWait)
        if startUp == nil {
            return false
        }
        
        self.checkIfInboundTransferOperationFinishedTimer = RepeatingTimer(interval: SMDownloadFiles.TIME_INTERVAL_TO_CHECK_IF_OPERATION_SUCCEEDED_S, selector: #selector(SMDownloadFiles.pollIfFileOperationFinished), andTarget: self)
        self.checkIfInboundTransferOperationFinishedTimer!.start()
        
        return true
    }
    
    @objc private func pollIfFileOperationFinished() {
        Log.msg("pollIfFileOperationFinished")
        self.checkIfInboundTransferOperationFinishedTimer!.cancel()

        let startUp = self.getStartup(.InboundTransferWait)
        if startUp == nil {
            Assert.badMojo(alwaysPrintThisString: "Should not get here")
        }
        
        SMServerAPI.session.checkOperationStatus(serverOperationId: self.serverOperationId!) { operationResult, cosResult in
            if SMTest.If.success(cosResult.error, context: .CheckOperationStatus) {                
                switch (operationResult!.status) {
                case SMServerConstants.rcOperationStatusInProgress:
                    Log.msg("Operation still in progress")
                    self.downloadControl()
                    
                case SMServerConstants.rcOperationStatusSuccessfulCompletion:
                    self.syncServerDelegate?.syncServerEventOccurred(.InboundTransferComplete(numberOperations:operationResult!.count))
                    
                    Log.msg("Operation succeeded: \(operationResult!.count) cloud storage operations performed")
        
                    startUp!.startupStage = .RemoveOperationId
                    self.downloadControl()

                default: // Must have failed on starting inbound transfer.
                    // Revert to the last stage-- recovery.
                    self.retryIfNetworkConnected(
                        &self.numberRevertBackToStartInboundTransfer, errorSpecifics: "failed on inbound transfer") {
                        startUp!.startupStage = .StartInboundTransfer
                        self.downloadControl()
                    }
                }
            }
            else {
                Log.error("Yikes: Error checking operation status: \(cosResult.error)")
                self.retryIfNetworkConnected(&self.numberCheckOperationStatusError, errorSpecifics: "check operation status") {
                    self.downloadControl()
                }
            }
        }
    }
    
    private func removeOperationId() -> Bool? {
        let startUp = self.getStartup(.RemoveOperationId)
        if startUp == nil {
            return false
        }
        
        SMServerAPI.session.removeOperationId(serverOperationId: self.serverOperationId!) { roiResult in
            if SMTest.If.success(roiResult.error, context: .RemoveOperationId) {
                self.serverOperationId = nil
                startUp!.removeObject()
                self.downloadControl()
            }
            else {
                // While this may not seem like much of an error, treat it seriously becuase it could be indicating a network error. If I don't treat it seriously, I can proceed forward which could leave the download in the wrong recovery mode.
                Log.error("Failed removing OperationId from server: \(roiResult.error)")
                self.retryIfNetworkConnected(&self.numberErrorsRemovingOperationId, errorSpecifics: "check operation status") {
                    self.downloadControl()
                }
            }
        }
        
        return true
    }

    private func doFileDownloads() -> Bool? {
        let filesToDownload = SMQueues.current().getBeingDownloadedChanges(
            .DownloadFile, operationStage: .ServerDownload) as? [SMDownloadFile]
        if nil == filesToDownload {
            return false
        }
        
        let serverFilesToDownload = SMDownloadFile.convertToServerFiles(filesToDownload!)
        if nil == serverFilesToDownload {
            self.callSyncControlModeChange(.InternalError(Error.Create("Could not convert downloads to server files")))
            return nil
        }
                
        SMServerAPI.session.downloadFiles(serverFilesToDownload!) { dfResult in
            if SMTest.If.success(dfResult.error, context: .DownloadFiles) {
                // Delegate method should have already marked all of the SMDownloadFile's as being in .AppCallback stage.
                self.downloadControl()
            }
            else {
                Log.error("Failed on downloadFiles: \(dfResult.error)")
                self.retryIfNetworkConnected(&self.numberErrorsDownloadingFiles, errorSpecifics: "downloading files") {
                    self.downloadControl()
                }
            }
        }
        
        return true
    }
    
    // File download, file deletion, and file conflict callbacks.
    private func doCallbacks() -> Bool? {
        let startUp = self.getStartup(.NoFileDownloads)
        if startUp != nil {
            startUp!.removeObject()
        }
        
        var result = false
        
        if let fileDownloads = SMQueues.current().getBeingDownloadedChanges(
            .DownloadFile, operationStage: .AppCallback) as? [SMDownloadFile] {
            Log.msg("\(fileDownloads.count) file downloads")
            self.callSyncServerDownloadsComplete(fileDownloads) {
                self.doCallbacks()
            }
            result = true
        }
        else if let fileDeletions = SMQueues.current().getBeingDownloadedChanges(
            .DownloadDeletion) as? [SMDownloadDeletion] {
            Log.msg("\(fileDeletions.count) file deletions")
            
            for downloadDeletion in fileDeletions {
                Assert.If(downloadDeletion.localFile == nil, thenPrintThisString: "No localFile for SMDownloadDeletion")
                downloadDeletion.localFile!.deletedOnServer = true
            }
            
            CoreData.sessionNamed(SMCoreData.name).saveContext()
            
            self.callSyncServerSyncServerClientShouldDeleteFiles(fileDeletions) {
                self.doCallbacks()
            }
            result = true
        }
        else if let fileConflicts = SMQueues.current().getBeingDownloadedChanges(
            .DownloadConflict) as? [SMDownloadConflict] {
            Log.msg("\(fileConflicts.count) file conflicts")
            Assert.badMojo(alwaysPrintThisString: "Not yet implemented")
            self.callSyncServerSyncServerClientShouldResolveConflicts(fileConflicts) {
                self.doCallbacks()
            }
            result = true
        }
        else {
            self.callSyncServerDownloadsFinished()
        }
        
        return result
    }
    
    private func retryIfNetworkConnected(inout attempts:Int, errorSpecifics:String, retryMethod:()->()) {
        if Network.session().connected() {
            Log.special("retry: for \(errorSpecifics)")

            // Retry up to a max number of times, then fail.
            if attempts < self.MAX_NUMBER_ATTEMPTS {
                attempts += 1
                
                SMServerNetworking.exponentialFallback(forAttempt: attempts) {
                    self.syncServerDelegate?.syncServerEventOccurred(.Recovery)
                    retryMethod()
                }
            }
            else {
                self.callSyncControlModeChange(
                    .NonRecoverableError(Error.Create("Failed after \(self.MAX_NUMBER_ATTEMPTS) retries on \(errorSpecifics)")))
            }
        }
        else {
            self.callSyncControlModeChange(.NetworkNotConnected)
        }
    }
    
    // MARK: Start: Methods that call delegate methods
    
    private func callSyncControlModeChange(mode:SMSyncServerMode) {
        self.syncControlDelegate?.syncControlModeChange(mode)
    }

    private func callSyncServerDownloadsComplete(fileDownloads:[SMDownloadFile], completion:()->()) {
        var downloaded = [(NSURL, SMSyncAttributes)]()
        
        for downloadFile in fileDownloads {
            let localFile = downloadFile.localFile!
            
            let attr = SMSyncAttributes(withUUID: NSUUID(UUIDString: localFile.uuid!)!)
            attr.appFileType = localFile.appFileType
            attr.mimeType = localFile.mimeType
            attr.remoteFileName = localFile.remoteFileName
            downloaded.append((downloadFile.fileURL!, attr))
        
            if localFile.syncState == .InitialDownload {
                localFile.syncState = .AfterInitialSync
            }
            
            localFile.localVersion = downloadFile.serverVersion
            CoreData.sessionNamed(SMCoreData.name).saveContext()
        }
        
        self.syncServerDelegate?.syncServerDownloadsComplete(downloaded) {
            SMQueues.current().removeBeingDownloadedChanges(.DownloadFile)
            completion()
        }
    }
    
    private func callSyncServerSyncServerClientShouldDeleteFiles(fileDeletions:[SMDownloadDeletion], completion:()->()) {
            
        var uuids = [NSUUID]()
        
        for fileToDelete in fileDeletions {
            uuids.append(NSUUID(UUIDString: fileToDelete.localFile!.uuid!)!)
        }
        
        self.syncServerDelegate?.syncServerClientShouldDeleteFiles(uuids) {
            SMQueues.current().removeBeingDownloadedChanges(.DownloadDeletion)
            completion()
        }
    }
    
    private func callSyncServerSyncServerClientShouldResolveConflicts(fileConflicts:[SMDownloadConflict], completion:()->()) {
    }
    
    private func callSyncServerDownloadsFinished() {
        // The server lock gets released automatically when the transfer from cloud storage completes, before the actual downloads of the files.
        // TODO: This may change once we have a websockets server-client communication method in place. If using websockets the server can communicate with assuredness to the client app that the inbound transfer is done, then the server may not have to release the lock.
        self.syncControlDelegate?.syncControlDownloadsFinished()
    }
    
    // MARK: End: Methods that call delegate methods
}

// MARK: SMServerAPIDownloadDelegate methods

extension SMDownloadFiles : SMServerAPIDownloadDelegate {
    internal func smServerAPIFileDownloaded(file: SMServerFile) {
        let downloadedFile = SMQueues.current().getBeingDownloadedChange(forUUID: file.uuid.UUIDString, andChangeType: .DownloadFile) as? SMDownloadFile
        Assert.If(downloadedFile == nil, thenPrintThisString: "Yikes: Could not get SMDownloadFile: \(file.uuid)")
        downloadedFile!.operationStage = .AppCallback
        
        let attr = SMSyncAttributes(withUUID: file.uuid)
        attr.appFileType = file.appFileType
        attr.mimeType = file.mimeType
        attr.remoteFileName = file.remoteFileName
        
        self.syncServerDelegate?.syncServerEventOccurred(.SingleDownloadComplete(url:file.localURL!, attr:attr))
    }
}

