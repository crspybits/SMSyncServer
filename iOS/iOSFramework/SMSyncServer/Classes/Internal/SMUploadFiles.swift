//
//  SMUploadFiles.swift
//  NetDb
//
//  Created by Christopher Prince on 12/12/15.
//  Copyright © 2015 Spastic Muffin, LLC. All rights reserved.
//

// Algorithms for upload and upload-deletion of files to the SyncServer.
// This class' resources are either private or internal. It is not intended for use by classes outside of the SMSyncServer framework.

import Foundation
import SMCoreLib

/* 
This class uses RepeatingTimer. It must have NSObject as a base class.
*/
internal class SMUploadFiles : NSObject {
    // This is a singleton because we need centralized control over the file upload operations.
    internal static let session = SMUploadFiles()
    
    internal weak var syncServerDelegate:SMSyncServerDelegate?
    internal weak var syncControlDelegate:SMSyncControlDelegate?
    
    // I could make this a persistent var, but little seems to be gained by that other than reducing the number of times we try to recover. I've made this a "static" so I can access it within the mode var below.
    private static var numberTimesTriedRecovery = 0
    
    internal static var maxTimesToTryRecovery = 3
    
    // For error recovery, it's useful to have the operationId if we have one.
    private static let _operationId = SMPersistItemString(name: "SMUploadFiles.OperationId", initialStringValue: "", persistType: .UserDefaults)
    
    private static let operationCount = SMPersistItemInt(name: "SMUploadFiles.operationCount", initialIntValue: 0, persistType: .UserDefaults)
    
    // Our strategy is to delay updating local meta data for files until we are completely assured the changes have propagated through to cloud storage.
    private var serverOperationId:String? {
        get {
            if (SMUploadFiles._operationId.stringValue == "") {
                return nil
            }
            else {
                return SMUploadFiles._operationId.stringValue
            }
        }
        set {
            if (nil == newValue) {
                SMUploadFiles._operationId.stringValue = ""
            }
            else {
                SMUploadFiles._operationId.stringValue = newValue!
            }
        }
    }
    
    private var checkIfUploadOperationFinishedTimer:RepeatingTimer?
    private static let TIME_INTERVAL_TO_CHECK_IF_OPERATION_SUCCEEDED_S:Float = 5

    // The current file index from the server.
    private var serverFileIndex:[SMServerFile]?
    
    private let MAX_NUMBER_ATTEMPTS = 3
    private var numberDeletionAttempts = 0
    private var numberUploadAttempts = 0
    private var numberOutboundTransferAttempts = 0
    private var numberCheckOperationStatusErrors = 0
    private var numberRemoveOperationIdAttempts = 0
    private var numberRevertBackToOutboundTransfer = 0

    private func resetAttempts() {
        self.numberDeletionAttempts = 0
        self.numberUploadAttempts = 0
        self.numberOutboundTransferAttempts = 0
        self.numberCheckOperationStatusErrors = 0
        self.numberRemoveOperationIdAttempts = 0
        self.numberRevertBackToOutboundTransfer = 0
    }
    
    enum OperationState {
        case Some
        case None
    }
    
    enum OperationNeeds {
        case ServerFileIndex
        case Nothing
    }
    
    enum SyncOperationResult {
        // OperationNeeds given only for Some OperationState
        case Operation(OperationState, OperationNeeds?)
        case Error
    }

    // Operations and their priority.
    private var uploadOperations:[((checkIfOperations:Bool)-> Bool?, OperationNeeds)]!
    
    private override init() {
        super.init()
        
        unowned let unownedSelf = self

        // Putting deletions as first priority just because deletions should be fast.
        self.uploadOperations = [
            (unownedSelf.doUploadDeletions, .ServerFileIndex),
            (unownedSelf.doUploadFiles, .ServerFileIndex),
            (unownedSelf.doOutboundTransfer, .Nothing),
            (unownedSelf.startToPollForOperationFinish, .Nothing),
            (unownedSelf.removeOperationId, .Nothing)
        ]
    }
    
    internal func appLaunchSetup() {
        SMServerAPI.session.uploadDelegate = self
    }
    
    // MARK: Start: Methods that call delegate methods
    // Don't call the delegate methods directly; call these methods instead-- so that we ensure serialization/sync is maintained correctly.
    
    private func callSyncServerCommitComplete(numberOperations numberOperations:Int?) {
    
        // The server lock gets released automatically when the transfer to cloud storage completes. I'm doing this automatic releasing of the lock because the cloud storage transfer is a potentially long running operation, and we could lose network connectivity. What's the point of holding the lock if we don't have network connectivity?
        // TODO: This may change once we have a websockets server-client communication method in place. If using websockets the server can communicate with assuredness to the client app that the outbound transfer is done, then the server may not have to release the lock.
        self.syncControlDelegate?.syncControlUploadsFinished()
        NSThread.runSyncOnMainThread() {
            self.syncServerDelegate?.syncServerEventOccurred(.AllUploadsComplete(numberOperations: numberOperations))
        }
    }
    
    private func callSyncControlModeChange(mode:SMSyncServerMode) {
        self.syncControlDelegate?.syncControlModeChange(mode)
    }
    
    // MARK: End: Methods that call delegate methods

    // The serverFileIndex is optional to accomodate the possiblity that not all possible upload oeprations are necessarily being executed. i.e., checkIfOperationsNeedLock was called prior to this.
    func doUploadOperations(serverFileIndex:[SMServerFile]?) {
        self.resetAttempts()
        self.serverFileIndex = serverFileIndex
        self.uploadControl()
    }

    // Check if there are operations that need to be done, and if they need a lock. Doesn't start any operation.
    func checkWhatOperationsNeed() -> SyncOperationResult {
        for (uploadOperation, operationNeeds) in self.uploadOperations {
            if let operationsToDo = uploadOperation(checkIfOperations: true) {
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
    
    // Control for operations. Each call to this control method does at most one of the asynchronous operations.
    private func uploadControl(checkIfOperations:Bool=false) {
        for (uploadOperation, _) in self.uploadOperations {
            let successfulOperation = uploadOperation(checkIfOperations: false)
            
            // If there was an error (nil), or if the operation was successful, then we're done with this go-around. The operations run asynchronously, when successful, and will callback as needed to uploadControl() to do the next operation.
            if successfulOperation == nil || successfulOperation! {
                break
            }
        }
    }
    
    // Returns true if there were deletions to do (which will be in process asynchronously), and false if there were no deletions to do. Nil is returned in the case of an error.
    private func doUploadDeletions(checkIfOperations:Bool=false) -> Bool? {
        Log.msg("\(SMQueues.current().beingUploaded)")
        var deletionChanges = SMQueues.current().beingUploaded?.getChanges(.UploadDeletion, operationStage:.ServerUpload) as! [SMUploadDeletion]?
        if deletionChanges == nil {
            return false
        }
        
        if checkIfOperations {
            return true
        }
        
        var serverFileDeletions:[SMServerFile]?
        
        if let error = self.errorCheckingForDeletion(self.serverFileIndex!, deletionChanges: &deletionChanges) {
            self.callSyncControlModeChange(error)
            return nil
        }
        
        serverFileDeletions = SMUploadFileOperation.convertToServerFiles(deletionChanges!)
        Assert.If(nil == serverFileDeletions, thenPrintThisString: "Yikes: Nil serverFileDeletions")
        
        SMServerAPI.session.deleteFiles(serverFileDeletions) { dfResult in
            if (nil == dfResult.error) {
                var uuids = [NSUUID]()
                for fileToDelete in serverFileDeletions! {
                    uuids.append(fileToDelete.uuid)
                }
                
                NSThread.runSyncOnMainThread() {
                    self.syncServerDelegate?.syncServerEventOccurred(.DeletionsSent(uuids: uuids))
                }
                
                for deletionChange in deletionChanges! {
                    deletionChange.operationStage = .CloudStorage
                }
                
                self.uploadControl()
            }
            else {
                self.retryIfNetworkConnected(&self.numberDeletionAttempts, errorSpecifics: "upload-deletion") {
                    self.uploadControl()
                }
            }
        }
        
        return true
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
                self.callSyncControlModeChange(.NonRecoverableError(Error.Create("Failed after \(self.MAX_NUMBER_ATTEMPTS) retries on \(errorSpecifics)")))
            }
        }
        else {
            self.callSyncControlModeChange(.NetworkNotConnected)
        }
    }

    private func doUploadFiles(checkIfOperations:Bool=false) -> Bool? {
        let uploadChanges = SMQueues.current().beingUploaded?.getChanges(
                .UploadFile, operationStage: .ServerUpload) as? [SMUploadFile]

        if checkIfOperations {
            return uploadChanges != nil
        }
        
        if uploadChanges == nil {
            return false
        }
        
        let (filesToUpload, error) = self.filesToUpload(self.serverFileIndex, uploadChanges: uploadChanges!)
        
        if error != nil {
            self.callSyncControlModeChange(error!)
            return nil
        }
        
        SMServerAPI.session.uploadFiles(filesToUpload) { uploadResult in
            Log.msg("Result error: \(uploadResult.error)")
            
            if SMTest.If.success(uploadResult.error, context: .UploadFiles) {
                self.uploadControl()
            }
            else {
                if (uploadResult.returnCode == SMServerConstants.rcServerAPIError) {
                    // Not sure if this was a programming error within the SMSyncServer framework or from usage of the client api by the app.
                    self.callSyncControlModeChange(.InternalError(uploadResult.error!))
                }
                else {
                    self.retryIfNetworkConnected(&self.numberUploadAttempts, errorSpecifics: "upload") {
                        self.uploadControl()
                    }
                }
            }
        }
        
        return true
    }
    
    private func getWrapup(stage:SMUploadWrapup.WrapupStage?) -> SMUploadWrapup? {
        
        if let wrapUpArray = SMQueues.current().beingUploaded?.getChanges(.UploadWrapup) as? [SMUploadWrapup] {
            Assert.If(wrapUpArray.count != 1, thenPrintThisString: "Not exactly one wrapup object")
            
            let wrapUp = wrapUpArray[0]
            
            if nil == stage || wrapUp.wrapupStage == stage {
                return wrapUp
            }
        }
        
        return nil
    }
    
    private func doOutboundTransfer(checkIfOperations:Bool=false) -> Bool? {
        let wrapUp = self.getWrapup(.OutboundTransfer)
        if wrapUp == nil {
            return false
        }
        
        if checkIfOperations {
            return true
        }
        
        SMServerAPI.session.startOutboundTransfer() { operationId, sotResult in
            Log.msg("Result error: \(sotResult.error); operationId: \(operationId)")
            
            if SMTest.If.success(sotResult.error, context: .OutboundTransfer) {
                self.serverOperationId = operationId
                wrapUp!.wrapupStage = .OutboundTransferWait
                self.uploadControl()
            }
            else {
                self.retryIfNetworkConnected(&self.numberOutboundTransferAttempts, errorSpecifics: "outbound transfer") {
                    self.uploadControl()
                }
            }
        }
        
        return true
    }
    
    // Start timer to poll the server to check if our operation has succeeded. That check will update our local file meta data if/when the file sync completes successfully.
    private func startToPollForOperationFinish(checkIfOperations:Bool=false) -> Bool? {
        let wrapUp = self.getWrapup(.OutboundTransferWait)
        if wrapUp == nil {
            return false
        }
        
        if checkIfOperations {
            return true
        }
        
        self.checkIfUploadOperationFinishedTimer = RepeatingTimer(interval: SMUploadFiles.TIME_INTERVAL_TO_CHECK_IF_OPERATION_SUCCEEDED_S, selector: #selector(SMUploadFiles.pollIfFileOperationFinished), andTarget: self)
        self.checkIfUploadOperationFinishedTimer!.start()
        
        return true
    }
    
    // PRIVATE
    // TODO: How do we know if we've been checking for too long?
    func pollIfFileOperationFinished() {
        let wrapUp = self.getWrapup(.OutboundTransferWait)
        if wrapUp == nil {
            Assert.badMojo(alwaysPrintThisString: "Should not get here")
        }
        
        Log.msg("checkIfFileOperationFinished")
        self.checkIfUploadOperationFinishedTimer!.cancel()
        
        // TODO: Should fallback exponentially in our checks-- sometimes cloud storage can take a while. Either because it's just slow, or because the file is large.
        
        SMServerAPI.session.checkOperationStatus(serverOperationId: self.serverOperationId!) {operationResult, apiResult in
            if SMTest.If.success(apiResult.error, context: .CheckOperationStatus) {
                switch (operationResult!.status) {
                case SMServerConstants.rcOperationStatusInProgress:
                    Log.msg("Operation still in progress")
                    self.uploadControl()
                    
                case SMServerConstants.rcOperationStatusSuccessfulCompletion:
                    Log.msg("Upload operation succeeded: \(operationResult!.count) cloud storage operations performed")
                    self.numberRevertBackToOutboundTransfer = 0
                    let numberUploads = self.updateMetaDataForSuccessfulUploads()
                    Log.msg("number server operations: \(operationResult!.count); numberUploads: \(numberUploads)")
                    
                    // 3/15/16; Because of a server error, operation count could be greater than the number uploads. Just ran into this.
                    // 4/29/16; And just ran into a situation where because the deletion was eliminated locally (becuase of a prior deletion-download), there were no server operations.
                    /*
                    Assert.If(numberUploads > operationResult!.count, thenPrintThisString: "Something bad is going on: numberUploads \(numberUploads) > operation count \(operationResult!.count)")
                    */
                    
                    SMUploadFiles.operationCount.intValue = operationResult!.count

                    wrapUp!.wrapupStage = .RemoveOperationId
                    self.uploadControl()

                default: // Must have failed on outbound transfer.
                    // Revert to the last stage-- recovery.
                    self.retryIfNetworkConnected(
                        &self.numberRevertBackToOutboundTransfer, errorSpecifics: "failed on outbound transfer") {
                        wrapUp!.wrapupStage = .OutboundTransfer
                        self.uploadControl()
                    }
                }
            }
            else {
                Log.msg("Yikes: Error checking operation status")
                self.retryIfNetworkConnected(&self.numberCheckOperationStatusErrors, errorSpecifics: "check operation status") {
                    self.uploadControl()
                }
            }
        }
    }
    
    private func removeOperationId(checkIfOperations:Bool=false) -> Bool {
        let wrapUp = self.getWrapup(.RemoveOperationId)
        if wrapUp == nil {
            return false
        }
        
        if checkIfOperations {
            return true
        }
        
        // Now that we know we succeeded, we can remove the Operation Id from the server. In some sense it's not a big deal if this fails. HOWEVER, since we set self.serverOperationId to nil on completion (see [4]), it is a big deal: I just ran into an apparent race condition where in testThatTwoSeriesFileUploadWorks(), I got a crash because self.serverOperationId was nil. Seems like this crash occurred because the removeOperationId completion handler for the first upload was called *after* the second call to startFileChanges completed. To avoid this race condition, I'm going to delay the syncServerCommitComplete callback until removeOperationId completes.
        SMServerAPI.session.removeOperationId(serverOperationId: self.serverOperationId!) { apiResult in
        
            if SMTest.If.success(apiResult.error, context: .RemoveOperationId) {
                self.serverOperationId = nil // [4]

                SMQueues.current().beingUploaded!.removeChanges(.UploadWrapup)
                
                // Fully done the upload-- can return to SMSyncControl now.
                self.callSyncServerCommitComplete(numberOperations: SMUploadFiles.operationCount.intValue)
            }
            else {
                Log.file("Failed removing OperationId from server: \(apiResult.error)")
                self.retryIfNetworkConnected(&self.numberRemoveOperationIdAttempts, errorSpecifics: "remove operation id") {
                    self.uploadControl()
                }
            }
        }
        
        return true
    }
    
    // Do error checking for the files to be deleted using. If non-nil, the return value will be one of the errors in SMSyncServerMode. The deletionChanges parameter will get updated if there are deletions that don't have to be done because they have already been done on the server. The received value of deletionChanges will not be nil, but the result might be nil.
    private func errorCheckingForDeletion(serverFileIndex:[SMServerFile], inout deletionChanges:[SMUploadDeletion]?) -> SMSyncServerMode? {

        var updatedDeletionChanges = [SMUploadDeletion]()
        
        for deletionChange:SMUploadDeletion in deletionChanges! {
            let localFile = deletionChange.localFile!
            
            let localVersion:Int = localFile.localVersion!.integerValue
            
            let serverFile:SMServerFile? = SMServerFile.getFile(fromFiles: serverFileIndex, withUUID: NSUUID(UUIDString: localFile.uuid!)!)
            
            if nil == serverFile {
                return .InternalError(Error.Create("File you are deleting is not on the server!"))
            }
            
            if serverFile!.deleted!.boolValue {
                // This isn't necessarily an error. If we queued an upload-deletion, and then processed a (naturally higher priority) download-deletion, then the file will already be deleted-- and will be marked as such in the local meta data.
                if localFile.deletedOnServer {
                    // skip this deletionChange
                    continue
                }
                else {
                    return .InternalError(Error.Create("The server file you are attempting to delete was already deleted!"))
                }
            }
            
            // Also seems odd to delete a file version that you don't know about.
            if localVersion != serverFile!.version {
                return .InternalError(Error.Create("Server file version \(serverFile!.version) not the same as local file version \(localVersion)"))
            }
            
            updatedDeletionChanges.append(deletionChange)
        }
        
        if updatedDeletionChanges.count == 0 {
            deletionChanges = nil
        }
        else {
            deletionChanges = updatedDeletionChanges
        }
        
        return nil
    }
    
    // If non-nil, the return value will be one of the errors in SMSyncServerMode.
    internal func filesToUpload(serverFileIndex:[SMServerFile]?, uploadChanges:[SMUploadFile]) -> (filesToUpload:[SMServerFile]?, error:SMSyncServerMode?) {
        
        var filesToUpload = [SMServerFile]()
        
        Assert.If(serverFileIndex == nil, thenPrintThisString: "serverFileIndex should not be nil!")
        
        for fileChange:SMUploadFile in uploadChanges {
            Log.msg("\(fileChange)")
            
            let localFile = fileChange.localFile!
            
            // We need to make sure that the current version on the server (if any) is the same as the version locally. This is so that we can be assured that the new version we are updating from locally is logically the next version for the server.
            
            let localVersion:Int = localFile.localVersion!.integerValue
            Log.msg("Local file version: \(localVersion)")
            
            let currentServerFile = SMServerFile.getFile(fromFiles: serverFileIndex, withUUID:  NSUUID(UUIDString: localFile.uuid!)!)
            var uploadServerFile:SMServerFile?
            
            if nil == currentServerFile {
                Assert.If(0 != localFile.localVersion, thenPrintThisString: "Yikes: The first version of the file was not 0")
                
                // No file with this UUID on the server. This must be a new file.
                uploadServerFile = fileChange.convertToServerFile()
            }
            else {
                if localVersion != currentServerFile!.version {
                    return (filesToUpload:nil, error: .InternalError(Error.Create("Server file version \(currentServerFile!.version) not the same as local file version \(localVersion)")))
                }
                
                if currentServerFile!.deleted!.boolValue && fileChange.undeleteServerFile == nil {
                    return (filesToUpload:nil, error: .InternalError(Error.Create("The server file you are attempting to upload was already deleted, and you hadn't forced undeletion!")))
                }
                
                uploadServerFile = fileChange.convertToServerFile()
                uploadServerFile!.version = localVersion + 1
            }
            
            uploadServerFile!.localURL = fileChange.fileURL
            filesToUpload += [uploadServerFile!]
        }
        
        return (filesToUpload:filesToUpload, error:nil)
    }
    
    // Given that the uploads and/or upload-deletions of files was successful (i.e., both server upload and cloud storage operations have been done), update the local meta data to reflect the success.
    // Returns the combined number of uploads and upload-deletions that happened.
    private func updateMetaDataForSuccessfulUploads() -> Int {
        var numberVersionIncrements = 0
        var numberNewFiles = 0
        var numberDeletions = 0
        
        if let uploadDeletions = SMQueues.current().beingUploaded?.getChanges(.UploadDeletion) as? [SMUploadDeletion] {
            for uploadDeletion in uploadDeletions {
                let deletedLocalFile:SMLocalFile = uploadDeletion.localFile!
                
                deletedLocalFile.deletedOnServer = true
                deletedLocalFile.pendingUploads = nil
                
                numberDeletions += 1
            }
            
            SMQueues.current().beingUploaded!.removeChanges(.UploadDeletion)
        }
        
        if let uploadFiles = SMQueues.current().beingUploaded?.getChanges(.UploadFile) as? [SMUploadFile] {
            for uploadFile in uploadFiles {
                let localFile:SMLocalFile = uploadFile.localFile!
                
                if uploadFile.deleteLocalFileAfterUpload!.boolValue {
                    let fileWasDeleted = FileStorage.deleteFileWithPath(uploadFile.fileURL)
                    Assert.If(!fileWasDeleted, thenPrintThisString: "File could not be deleted")
                }
                
                // Special case for undeletion: Need to mark files that were undeleted on server as not deleted here locally.
                if uploadFile.undeleteServerFile ?? false {
                    localFile.deletedOnServer = false
                }
                
                if localFile.syncState == .InitialUpload {
                    localFile.syncState = .AfterInitialSync
                    numberNewFiles += 1
                }
                else {
                    localFile.localVersion = localFile.localVersion!.integerValue + 1
                    Log.msg("New local file version: \(localFile.localVersion)")
                    numberVersionIncrements += 1
                }
            }
            
            SMQueues.current().beingUploaded!.removeChanges(.UploadFile)
        }
        
        CoreData.sessionNamed(SMCoreData.name).saveContext()
        
        NSThread.runSyncOnMainThread() {
            self.syncServerDelegate?.syncServerEventOccurred(.FrameworkUploadMetaDataUpdated)
        }
        
        Log.msg("Number version increments: \(numberVersionIncrements)")
        Log.msg("Number new files: \(numberNewFiles)")
        Log.msg("Number deletions: \(numberDeletions)")
        
        return numberVersionIncrements + numberNewFiles + numberDeletions
    }
}

// MARK: SMServerAPIUploadDelegate methods

extension SMUploadFiles : SMServerAPIUploadDelegate {
    internal func smServerAPIFileUploaded(serverFile : SMServerFile) {
        // Switch over the operation stage for the change to .CloudStorage (and don't delete the upload) so that we still have the info to later, once the outbound transfer has completed, to send delegate callbacks to the app using the api.
        let change:SMUploadFileOperation? = SMQueues.current().beingUploaded?.getChange(forUUID:serverFile.uuid.UUIDString)
        Assert.If(change == nil, thenPrintThisString: "Yikes: Couldn't get upload for uuid \(serverFile.uuid.UUIDString)")
        change!.operationStage = .CloudStorage
        
        NSThread.runSyncOnMainThread() {
            self.syncServerDelegate?.syncServerEventOccurred(
                .SingleUploadComplete(uuid: serverFile.uuid))
        }
    }
}
