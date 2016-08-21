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

    enum OperationState {
        case Some
        case None
    }
    
    enum OperationNeeds {
        case ServerLock
        case ServerLockOptional // Needs server lock except for recovery.
        case Nothing
    }
    
    enum SyncOperationResult {
        // OperationNeeds given only for Some OperationState
        case Operation(OperationState, OperationNeeds?)
        case Error
    }
    
    // Operations and their priority.
    private var downloadOperations:[((checkIfOperations: Bool)-> Bool?, OperationNeeds)]!
    
    override private init() {
        super.init()
        
        unowned let unownedSelf = self
        
        /* Download execution follows two paths:
        1) If there are file downloads, all of the download steps are followed.
        2) If there are no file downloads, and there are only file deletions (and possibly file conflicts), then steps are skipped until doCallbacks. The .NoFileDownloads SMDownloadStartup.StartupStage is used to control this.
        This is different than the way that uploads operate-- because all uploads (uploads and upload-deletions) have to be processed on the server. Only file downloads have to be processed from the server, however. Download-deletions (once we know about the server file index) only need to be processed locally.
        */
        self.downloadOperations = [
            // I've separated Setup and Start to make recovery easier.
            (unownedSelf.doSetupInboundTransfers, .ServerLock),
            (unownedSelf.doStartInboundTransfers, .ServerLockOptional),
            
            (unownedSelf.startToPollForOperationFinish, .Nothing),
            (unownedSelf.removeOperationId, .Nothing),
            (unownedSelf.doFileDownloads, .Nothing),
            (unownedSelf.doCallbacks, .Nothing)
        ]
    }
    
    internal weak var syncServerDelegate:SMSyncServerDelegate?
    internal weak var syncControlDelegate:SMSyncControlDelegate?
    
    internal func appLaunchSetup() {
        SMServerAPI.session.downloadDelegate = self
    }

    // Check if there are operations that need to be done, and if they need a lock. Doesn't start any operation.
    func checkWhatOperationsNeed() -> SyncOperationResult {
        for (downloadOperation, operationNeeds) in self.downloadOperations {
            if let operationsToDo = downloadOperation(checkIfOperations: true) {
                if operationsToDo {
                    return .Operation(.Some, operationNeeds)
                }
            }
            else {
                return .Error
            }
        }
        
        return .Operation(.None, nil)
    }
    
    func doDownloadOperations() {
        self.resetAttempts()
        self.downloadControl()
    }

    // Control for operations. Each call to this control method does at most one of the asynchronous operations.
    private func downloadControl() {
        for (downloadOperation, _) in self.downloadOperations {
            let successfulOperation = downloadOperation(checkIfOperations: false)
            
            // If there was an error (nil), or if the operation was successful, then we're done with this go-around. Most of the the operations run asynchronously, when successful, and will callback as needed to downloadControl() to do the next operation.
            if successfulOperation == nil || successfulOperation! {
                break
            }
        }
    }
    
    private func doSetupInboundTransfers(checkIfOperations:Bool) -> Bool? {
        let inboundTransfers = SMQueues.current().getBeingDownloadedChanges(
            .DownloadFile, operationStage: .CloudStorage) as? [SMDownloadFile]
        if nil == inboundTransfers {
            return false
        }
        
        if checkIfOperations {
            return true
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
    
    private func doStartInboundTransfers(checkIfOperations:Bool) -> Bool? {
        let startUp = self.getStartup(.StartInboundTransfer)
        if startUp == nil {
            return false
        }
        
        if checkIfOperations {
            return true
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
    private func startToPollForOperationFinish(checkIfOperations:Bool) -> Bool? {
        let startUp = self.getStartup(.InboundTransferWait)
        if startUp == nil {
            return false
        }
        
        if checkIfOperations {
            return true
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
                    NSThread.runSyncOnMainThread() {
                        self.syncServerDelegate?.syncServerEventOccurred(
                            .InboundTransferComplete(
                                numberOperations:operationResult!.count))
                    }
                    
                    Log.msg("Download operation succeeded: \(operationResult!.count) cloud storage operations performed")
        
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
    
    private func removeOperationId(checkIfOperations:Bool) -> Bool? {
        let startUp = self.getStartup(.RemoveOperationId)
        if startUp == nil {
            return false
        }
        
        if checkIfOperations {
            return true
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

    private func doFileDownloads(checkIfOperations:Bool) -> Bool? {
        let filesToDownload = SMQueues.current().getBeingDownloadedChanges(
            .DownloadFile, operationStage: .ServerDownload) as? [SMDownloadFile]
        if nil == filesToDownload {
            return false
        }
        
        if checkIfOperations {
            return true
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
    private func doCallbacks(checkIfOperations:Bool) -> Bool? {
        let startUp = self.getStartup(.NoFileDownloads)
        if startUp != nil {
            startUp!.removeObject()
        }
        
        var result = false
        
        // Do check for modification lock conflict here because we're just about to call the callbacks.
        
        if let fileDownloads = SMQueues.current().getBeingDownloadedChanges(
            .DownloadFile, operationStage: .AppCallback) as? [SMDownloadFile] {
            Log.msg("\(fileDownloads.count) file downloads")
            
            if checkIfOperations {
                return true
            }
            
            self.callSyncServerDownloadsComplete(fileDownloads) {
                self.doCallbacks(checkIfOperations)
            }
            result = true
        }
        else if let fileDeletions = SMQueues.current().getBeingDownloadedChanges(
            .DownloadDeletion) as? [SMDownloadDeletion] {
            Log.msg("\(fileDeletions.count) file deletions")
            
            if checkIfOperations {
                return true
            }
            
            // There is an interesting problem that comes up here. While conceptually, we might want to delay marking the .deletedOnServer property to indicate deleted, for conflicts, this generates a cycle of behavior between the client and the server. If the client resolves the conflict by keeping client operations, then this will generate an upload request, which before that processes will do a download. Then, without the file marked as .deletedOnServer as true, to be consistent with the server, generates another download-deletion-- hence a cycle.
            // Hence, we'll set .deletedOnServer as true here, and with conflicts if the client chooses "Keep", the file will get .deletedOnServer set to false in updateMetaDataForSuccessfulUploads in SMUploadFiles.swift.
            for downloadDeletion in fileDeletions {
                Assert.If(downloadDeletion.localFile == nil, thenPrintThisString: "No localFile for SMDownloadDeletion")
                downloadDeletion.localFile!.deletedOnServer = true
            }
            
            CoreData.sessionNamed(SMCoreData.name).saveContext()
            
            self.callSyncServerSyncServerClientShouldDeleteFiles(fileDeletions) {
                self.doCallbacks(checkIfOperations)
            }
            result = true
        }
        else {
            if checkIfOperations {
                return false
            }
            
            Log.msg("Downloads finished.")
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
                    NSThread.runSyncOnMainThread() {
                        self.syncServerDelegate?.syncServerEventOccurred(.Recovery)
                    }
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
        var downloads = [(downloadedFile: NSURL, downloadedFileAttributes: SMSyncAttributes)]()
        var conflicts = [(downloadedFile: NSURL, downloadedFileAttributes: SMSyncAttributes, uploadConflict: SMSyncServerConflict)]()

        var shouldSaveDownloadsDone = false
        var calledCompletion = false
        
        func checkIfDone() {
            let unresolvedConflicts = conflicts.filter() {(_, _, conflict) in
                !conflict.conflictResolved
            }
            
            if !calledCompletion && shouldSaveDownloadsDone &&
                    unresolvedConflicts.count == 0 {
                SMQueues.current().removeBeingDownloadedChanges(.DownloadFile)
                calledCompletion = true
                completion()
            }
        }
        
        for downloadFile in fileDownloads {
            let localFile = downloadFile.localFile!
            
            let attr = SMSyncAttributes(withUUID: NSUUID(UUIDString: localFile.uuid!)!)
            attr.appMetaData = localFile.appMetaData
            attr.mimeType = localFile.mimeType
            attr.remoteFileName = localFile.remoteFileName
            attr.deleted = false
            
            if downloadFile.conflictType == nil {
                downloads.append((downloadedFile: downloadFile.fileURL!, downloadedFileAttributes: attr))
            }
            else {
                Log.special("FileDownload conflict: \(downloadFile.conflictType!)")
                
                let conflict = SMSyncServerConflict(conflictType: downloadFile.conflictType!) { resolution in

                    // Only in the case of deleting the client operation do we have to do something. If we're keeping the client operation, we do nothing. If we're removing the operations, then we have to either remove the file-upload(s) or upload-deletion.
                    if resolution == .DeleteConflictingClientOperations {
                        switch downloadFile.conflictType! {
                        case .FileUpload:
                            // Need to remove all pending file uploads for this SMLocalFile. See SMLocalFile pendingUpload() method
                            let pendingUploads = downloadFile.localFile!.pendingSMUploadFiles()
                            Assert.If(pendingUploads == nil, thenPrintThisString: "Should have uploads!")
                            for upload in pendingUploads! {
                                let queue = upload.queue
                                upload.removeObject()
                                
                                // Remove the containing queue if no more upload operations after this.
                                queue!.removeIfNoFileOperations()
                            }
                            
                        case .UploadDeletion:
                            // Need to remove pending upload-deletions. There should only ever be one because we don't allow multiple upload-deletions for the same file.
                            let pendingUploadDeletion = downloadFile.localFile!.pendingSMUploadDeletion()
                            Assert.If(pendingUploadDeletion == nil, thenPrintThisString: "Should have a pending upload deletion!")
                            
                            let queue = pendingUploadDeletion!.queue
                            pendingUploadDeletion!.removeObject()
                            
                            // Remove the containing queue if no more upload operations after this.
                            queue!.removeIfNoFileOperations()
                        }
                    }
                    
                    checkIfDone()
                } // End conflict closure

                conflicts.append((downloadedFile: downloadFile.fileURL!, downloadedFileAttributes: attr, uploadConflict: conflict))
            }
        
            if localFile.syncState == .InitialDownload {
                localFile.syncState = .AfterInitialSync
            }
            
            localFile.localVersion = downloadFile.serverVersion
            CoreData.sessionNamed(SMCoreData.name).saveContext()
        }

        if downloads.count > 0 {
            Log.special("syncServerShouldSaveDownloads")
            NSThread.runSyncOnMainThread() {
                self.syncServerDelegate?.syncServerShouldSaveDownloads(downloads) {
                    shouldSaveDownloadsDone = true
                    checkIfDone()
                }
            }
        }
        else {
            shouldSaveDownloadsDone = true
        }
        
        if conflicts.count > 0 {
            NSThread.runSyncOnMainThread() {
                self.syncServerDelegate?.syncServerShouldResolveDownloadConflicts(conflicts)
            }
        }
        else {
            checkIfDone()
        }
    }
    
    private func callSyncServerSyncServerClientShouldDeleteFiles(fileDeletions:[SMDownloadDeletion], completion:()->()) {

        var deletions = [SMSyncAttributes]()
        var conflicts = [(downloadDeletion: SMSyncAttributes, uploadConflict: SMSyncServerConflict)]()

        var shouldResolveDeletionConflictsDone = false
        var calledCompletion = false
        
        func checkIfDone() {
            let unresolvedConflicts = conflicts.filter() {(_, conflict) in
                !conflict.conflictResolved
            }
            
            if !calledCompletion && shouldResolveDeletionConflictsDone && unresolvedConflicts.count == 0 {
            
                SMQueues.current().removeBeingDownloadedChanges(.DownloadDeletion)
                calledCompletion = true
                completion()
            }
        }
        
        for fileToDelete in fileDeletions {
            let attr = SMSyncAttributes(withUUID: NSUUID(UUIDString: fileToDelete.localFile!.uuid!)!)
            attr.appMetaData = fileToDelete.localFile!.appMetaData
            attr.mimeType = fileToDelete.localFile!.mimeType
            attr.remoteFileName = fileToDelete.localFile!.remoteFileName
            attr.deleted = false
            
            if fileToDelete.conflictType == nil {
                deletions.append(attr)
            }
            else {
                Assert.If(fileToDelete.conflictType != .FileUpload, thenPrintThisString: "Didn't have a .FileUpload conflict!")
                
                Log.special("DownloadDeletion conflict: \(fileToDelete.conflictType!)")
                
                let conflict = SMSyncServerConflict(conflictType: fileToDelete.conflictType!) { resolution in

                    let pendingUploads = fileToDelete.localFile!.pendingSMUploadFiles()
                    Assert.If(pendingUploads == nil, thenPrintThisString: "Should have uploads!")
                    
                    switch resolution {
                    case .DeleteConflictingClientOperations:
                        // Need to remove all pending file uploads for this SMLocalFile. See SMLocalFile pendingUpload() method
                        for upload in pendingUploads! {
                            let queue = upload.queue
                            upload.removeObject()
                            
                            // Remove the containing queue if no more upload operations after this.
                            queue!.removeIfNoFileOperations()
                        }
                        
                    case .KeepConflictingClientOperations:
                        // Since the only conflicting operation that we can have are file-uploads, and we are keeping that/those, don't need to change .deletedOnServer property.
                        // Need to mark at least the first upload pending to force an undelete of the server file.
                        // I think the first item in the pending uploads will be the first SMUploadFile to get uploaded (for this local file).
                        pendingUploads![0].undeleteServerFile = true
                    }
                    
                    checkIfDone()
                } // End conflict closure
                
                conflicts.append((downloadDeletion: attr, uploadConflict: conflict))
            }
        }
        
        if deletions.count > 0 {
            NSThread.runSyncOnMainThread() {
                self.syncServerDelegate?.syncServerShouldDoDeletions(downloadDeletions:deletions) {
                    shouldResolveDeletionConflictsDone = true
                    checkIfDone()
                }
            }
        }
        else {
            shouldResolveDeletionConflictsDone = true
        }
        
        if conflicts.count > 0 {
            NSThread.runSyncOnMainThread() {
                self.syncServerDelegate?.syncServerShouldResolveDeletionConflicts(conflicts)
            }
        }
        else {
            checkIfDone()
        }
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
        attr.appMetaData = file.appMetaData
        Log.msg("file.appMetaData: \(file.appMetaData)")
        attr.mimeType = file.mimeType
        attr.remoteFileName = file.remoteFileName
        
        NSThread.runSyncOnMainThread() {
            self.syncServerDelegate?.syncServerEventOccurred(
                .SingleDownloadComplete(url:file.localURL!, attr:attr))
        }
    }
}

