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
    
    // TODO: If we fail on an attempt at recovery, we may to impose a timed interval between recovery attempts. E.g., if the server went down, we'd like to give it time to come back up.
    
    private class var mode:SMClientMode {
        set {
            SMSyncServer.session.mode = newValue
            self.numberTimesTriedRecovery = 0
        
            switch (newValue) {
            case .Running(.Upload, _),
                .Running(.BetweenUploadAndOutBoundTransfer, _),
                .Running(.OutboundTransfer, _),
                .Running(.AfterOutboundTransfer, _):
                break
        
            case .Idle, .NonRecoverableError:
                break
        
            case .Running(.InboundTransfer, _),
                .Running(.Download, _):
                Assert.badMojo(alwaysPrintThisString: "Yikes: Bad mode value for SMUploadFiles!")
            
            case .Operating:
                break
            }
        }
    
        get {
            return SMSyncServer.session.mode
        }
    }
    
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

    private override init() {
        super.init()
    }
    
    // TODO: Right now this is being called after sign in is completed. That seems good. But what about the app going into the background and coming into the foreground? This can cause a server API operation to fail, and we should initiate recovery at that point too.
    internal func appLaunchSetup() {
        // SMSync.session.delayDelegate = self
        SMServerAPI.session.uploadDelegate = self
    }
    
    /*
    // If an upload is currently in progress, an upload will be done as soon as the current one is completed.
    internal func prepareForUpload() {
        SMSync.session.startOrDelay()
    }
    */
    
    // MARK: Start SMSyncDelayedOperationDelegate method
    
    /*
    // I don't think this can actually be private to be called as a delegate method. But conceptually, it's private.
    internal func smSyncDelayedOperation() {
        self.prepareForUpload(givenAlreadyUploadedFiles: nil)
    }
    */
    
    // MARK: End SMSyncDelayedOperationDelegate method

    // Doesn't actually recover from the error. Expect the caller to somehow do that. Just resets the mode so this class can later proceed.
    internal func resetFromError() {
        // SMSyncControl should be the one that does this resetting. And the one that changes to an .Idle mode.
        Assert.badMojo(alwaysPrintThisString: "Fix Me")
        
        switch SMUploadFiles.mode {
        case .NonRecoverableError:
            break
        default:
            Assert.badMojo(alwaysPrintThisString: "We're not in .NonRecoverableError mode")
        }
        
        SMUploadFiles.mode = .Idle
    }
    
    // MARK: Start: Methods that call delegate methods
    // Don't call the "completion" delegate methods directly; call these methods instead-- so that we ensure serialization/sync is maintained correctly.
    
    private func callSyncServerCommitComplete(numberOperations numberOperations:Int?) {
    
        // The server lock gets released automatically when the transfer to cloud storage completes. I'm doing this automatic releasing of the lock because the cloud storage transfer is a potentially long running operation, and we could lose network connectivity. What's the point of holding the lock if we don't have network connectivity?
        self.syncControlDelegate?.syncControlFinished(serverLockHeld:false)
        
        self.syncServerDelegate?.syncServerEventOccurred(.OutboundTransferComplete(numberOperations: numberOperations))
    }
    
    private func callSyncServerError(error:NSError) {
        // We've had an API error or an error we couldn't deal with. Don't try to do any pending next operation.
        
        // Set the mode to .NonRecoverableError so that if the app restarts we don't try to recover again. This also has the additional effect of forcing the caller of this class to do something to recover. i.e., at least to call the resetFromError method.
        
        self.syncControlDelegate?.syncControlError()
        SMUploadFiles.mode = .NonRecoverableError(error)
    }
    
    // MARK: End: Methods that call delegate methods
    
    func doUploadOperations(serverFileIndex:[SMServerFile]) {
        self.serverFileIndex = serverFileIndex
        self.uploadControl()
    }

    // Control for 1) upload-deletions, 2) uploads, and 3) outbound transfers. The priority is in that order.
    // Putting deletions as first priority just because deletions should be fast.
    // Each call to this control method will do at most one of the three asynchronous operations.
    private func uploadControl() {
        let wereUploadDeletions = self.doUploadDeletions()
        if wereUploadDeletions == nil {
            return
        }
        else if !wereUploadDeletions! {
            let wereDownloadFiles = self.doUploadFiles()
            if wereDownloadFiles == nil {
                return
            }
            else if !wereDownloadFiles! {
                self.doOutboundTransfer()
            }
        }
    }
    
    // Returns true if there were deletions to do (which will be in process asynchronously), and false if there were no deletions to do. Nil is returned in the case of an error.
    private func doUploadDeletions() -> Bool? {
        let deletionChanges = SMQueues.current().beingUploaded!.getChanges(.UploadDeletion, operationStage:.ServerUpload) as! [SMUploadDeletion]?
        if deletionChanges == nil {
            return false
        }
        
        var serverFileDeletions:[SMServerFile]?
        
        if let error = self.errorCheckingForDeletion(self.serverFileIndex!, deletionChanges: deletionChanges!) {
            self.callSyncServerError(error)
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
                
                self.syncServerDelegate?.syncServerEventOccurred(.DeletionsSent(uuids: uuids))
                
                for deletionChange in deletionChanges! {
                    deletionChange.operationStage = .CloudStorage
                }
                
                self.uploadControl()
            }
            else {
                Assert.badMojo(alwaysPrintThisString: "Can't yet do recovery!")
                //self.recovery()
            }
        }
        
        return true
    }

    private func doUploadFiles() -> Bool? {
        let (filesToUpload, error) = self.filesToUpload(self.serverFileIndex!)
        
        if error != nil {
            self.callSyncServerError(error!)
            return nil
        }
        
        if filesToUpload == nil {
            return false
        }
        
        SMServerAPI.session.uploadFiles(filesToUpload) { uploadResult in
            Log.msg("SMSyncServer.session.doUpload: \(uploadResult.error)")
            
            if SMTest.If.success(uploadResult.error, context: .UploadFiles) {
                // Just about to do the commit. If we detect failure of the commit on the client, we'll not be fully sure if the commit succeeded. E.g., we could lose a network connection as the commit is operating making it look as if the commit failed, but it actually succeeded.
                SMUploadFiles.mode = .Running(.BetweenUploadAndOutBoundTransfer, .Operating)

                self.uploadControl()
            }
            else {
                if (uploadResult.returnCode == SMServerConstants.rcServerAPIError) {
                    // Can't recover immediately within the SMSyncServer. This must have been a client error.
                    self.callSyncServerError(uploadResult.error!)
                }
                else {
                    // Failed on uploadFiles-- Attempt recovery.
                    Assert.badMojo(alwaysPrintThisString: "Can't yet do recovery!")

                    // self.recovery()
                }
            }
        }
        
        return true
    }
    
    private func doOutboundTransfer() {
        let outboundTransfer = SMQueues.current().beingUploaded!.getChanges(.OutboundTransfer) as?[SMUploadOutboundTransfer]
        if outboundTransfer == nil {
            return
        }
        
        Assert.If(outboundTransfer!.count != 1, thenPrintThisString: "Not exactly one outbound transfer")
        
        SMServerAPI.session.startOutboundTransfer() { operationId, sotResult in
            Log.msg("SMSyncServer.session.startOutboundTransfer: \(sotResult.error); operationId: \(operationId)")
            if SMTest.If.success(sotResult.error, context: .OutboundTransfer) {
                self.serverOperationId = operationId
                // We *know* we have a successful commit. Change to our last recovery case.
                SMUploadFiles.mode = .Running(.OutboundTransfer, .Operating)
                
                SMQueues.current().beingUploaded!.removeChanges(.OutboundTransfer)
                
                self.startToPollForOperationFinish()
            }
            else {
                Assert.badMojo(alwaysPrintThisString: "Can't yet do recovery!")
                //self.recovery()
            }
        }
    }
    
    // Start timer to poll the server to check if our operation has succeeded. That check will update our local file meta data if/when the file sync completes successfully.
    private func startToPollForOperationFinish() {
        SMUploadFiles.mode = .Running(.OutboundTransfer, .Operating)

        self.checkIfUploadOperationFinishedTimer = RepeatingTimer(interval: SMUploadFiles.TIME_INTERVAL_TO_CHECK_IF_OPERATION_SUCCEEDED_S, selector: #selector(SMUploadFiles.pollIfFileOperationFinished), andTarget: self)
        self.checkIfUploadOperationFinishedTimer!.start()
    }
    
    // PRIVATE
    // TODO: How do we know if we've been checking for too long?
    func pollIfFileOperationFinished() {
        Log.msg("checkIfFileOperationFinished")
        self.checkIfUploadOperationFinishedTimer!.cancel()
        
        // TODO: Should fallback exponentially in our checks-- sometimes cloud storage can take a while. Either because it's just slow, or because the file is large.
        SMServerAPI.session.checkOperationStatus(serverOperationId: self.serverOperationId!) {operationResult, apiResult in
            if (apiResult.error != nil) {
                // TODO: How many times to check/recheck and still get an error?
                Log.msg("Yikes: Error checking operation status")
                self.checkIfUploadOperationFinishedTimer!.start()
            }
            else {
                // TODO: Deal with other collection of operation status here.
                
                switch (operationResult!.status) {
                case SMServerConstants.rcOperationStatusInProgress:
                    Log.msg("Operation still in progress")
                    self.checkIfUploadOperationFinishedTimer!.start()
                    
                case SMServerConstants.rcOperationStatusSuccessfulCompletion:
                    Log.msg("wrapUpOperation called from pollIfFileOperationFinished")
                    self.wrapUpOperation(operationResult!)
                
                case SMServerConstants.rcOperationStatusFailedBeforeTransfer, SMServerConstants.rcOperationStatusFailedDuringTransfer, SMServerConstants.rcOperationStatusFailedAfterTransfer:
                
                    if SMServerConstants.rcOperationStatusFailedAfterTransfer == operationResult!.status {
                        SMUploadFiles.mode = .Running(.AfterOutboundTransfer, .Recovery)
                    }
                    
                    // This will do more work than necessary (e.g., checking with the server again for operation status), but it handles these three cases.
                    Assert.badMojo(alwaysPrintThisString: "Can't yet do recovery!")

                    //self.recovery()
                    
                default:
                    let msg = "Yikes: Unknown operationStatus: \(operationResult!.status)"
                    Log.msg(msg)
                    self.callSyncServerError(Error.Create(msg))
                }
            }
        }
    }
    
    private func wrapUpOperation(operationResult: SMOperationResult?) {

        let numberUploads = self.updateMetaDataForSuccessfulUploads()
        
        if operationResult != nil {
            Log.msg("Operation succeeded: \(operationResult!.count) cloud storage operations performed")
            
            // 3/15/16; Because of a server error, operation count could be greater than the number uploads. Just ran into this.
            Assert.If(numberUploads > operationResult!.count, thenPrintThisString: "Something bad is going on: numberUploads \(numberUploads) > operation count \(operationResult!.count)")
        }
        
        // Letting SMSyncControl deal with this.
        // SMUploadFiles.mode = .Idle
        
        // Now that we know we succeeded, we can remove the Operation Id from the server. In some sense it's not a big deal if this fails. HOWEVER, since we set self.serverOperationId to nil on completion (see [4]), it is a big deal: I just ran into an apparent race condition where in testThatTwoSeriesFileUploadWorks(), I got a crash because self.serverOperationId was nil. Seems like this crash occurred because the removeOperationId completion handler for the first upload was called *after* the second call to startFileChanges completed. To avoid this race condition, I'm going to delay the syncServerCommitComplete callback until removeOperationId completes.
        SMServerAPI.session.removeOperationId(serverOperationId: self.serverOperationId!) { apiResult in
        
            if SMTest.If.success(apiResult.error, context: .RemoveOperationId) {
                self.serverOperationId = nil // [4]
                self.callSyncServerCommitComplete(numberOperations: numberUploads)
            }
            else {
                // While this may not seem like much of an error, treat it seriously because it could be indicating a network error. If I don't treat it seriously, I can proceed forward which could leave the upload in the wrong recovery mode.
                Log.file("Failed removing OperationId from server: \(apiResult.error)")
                Assert.badMojo(alwaysPrintThisString: "Can't yet do recovery!")
                //self.recovery()
            }
        }
    }
    
    // Do error checking for the files  to be deleted using.
    private func errorCheckingForDeletion(serverFileIndex:[SMServerFile], deletionChanges:[SMUploadDeletion]) -> NSError? {

        for deletionChange:SMUploadDeletion in deletionChanges {
            let localFile = deletionChange.localFile!
            
            let localVersion:Int = localFile.localVersion!.integerValue
            
            let serverFile:SMServerFile? = SMServerFile.getFile(fromFiles: serverFileIndex, withUUID: NSUUID(UUIDString: localFile.uuid!)!)
            
            if nil == serverFile {
                return Error.Create("File you are deleting is not on the server!")
            }
            
            if serverFile!.deleted!.boolValue {
                return Error.Create("The server file you are attempting to delete was already deleted!")
            }
            
            // Also seems odd to delete a file version that you don't know about.
            if localVersion != serverFile!.version {
                return Error.Create("Server file version \(serverFile!.version) not the same as local file version \(localVersion)")
            }
        }
        
        return nil
    }
    
    internal func filesToUpload(serverFileIndex:[SMServerFile]) -> (filesToUpload:[SMServerFile]?, error:NSError?) {
        
        var filesToUpload = [SMServerFile]()

        let uploadChanges = SMQueues.current().beingUploaded!.getChanges(
                .UploadFile, operationStage:.ServerUpload) as? [SMUploadFile]
        
        if uploadChanges == nil {
            return (filesToUpload:nil, error:nil)
        }
        
        for fileChange:SMUploadFile in uploadChanges! {
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
                    return (filesToUpload:nil, error: Error.Create("Server file version \(currentServerFile!.version) not the same as local file version \(localVersion)"))
                }
                
                if currentServerFile!.deleted!.boolValue {
                    return (filesToUpload:nil, error: Error.Create("The server file you are attempting to upload was already deleted!"))
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
    // Returns the number of uploads and upload-deletions that happened.
    private func updateMetaDataForSuccessfulUploads() -> Int {
        var numberUpdates = 0
        var numberNewFiles = 0
        var numberDeletions = 0
        
        if let uploadDeletions = SMQueues.current().beingUploaded!.getChanges(.UploadDeletion) as? [SMUploadDeletion] {
            for uploadDeletion in uploadDeletions {
                let deletedLocalFile:SMLocalFile = uploadDeletion.localFile!
                
                deletedLocalFile.deletedOnServer = true
                deletedLocalFile.pendingUploads = nil
                
                numberDeletions += 1
            }
            
            SMQueues.current().beingUploaded!.removeChanges(.UploadDeletion)
        }
        
        if let uploadFiles = SMQueues.current().beingUploaded!.getChanges(.UploadFile) as? [SMUploadFile] {
            for uploadFile in uploadFiles {
                let localFile:SMLocalFile = uploadFile.localFile!
                
                if uploadFile.deleteLocalFileAfterUpload!.boolValue {
                    let fileWasDeleted = FileStorage.deleteFileWithPath(uploadFile.fileURL)
                    Assert.If(!fileWasDeleted, thenPrintThisString: "File could not be deleted")
                }
                
                if localFile.newUpload!.boolValue {
                    localFile.newUpload = false
                    numberNewFiles += 1
                }
                else {
                    localFile.localVersion = localFile.localVersion!.integerValue + 1
                    Log.msg("New local file version: \(localFile.localVersion)")
                    numberUpdates += 1
                }
            }
            
            SMQueues.current().beingUploaded!.removeChanges(.UploadFile)
        }
        
        CoreData.sessionNamed(SMCoreData.name).saveContext()
        
        Log.msg("Number updates: \(numberUpdates)")
        Log.msg("Number new files: \(numberNewFiles)")
        Log.msg("Number deletions: \(numberDeletions)")
        
        return numberUpdates + numberNewFiles + numberDeletions
    }
}

#if false

// MARK: Recovery methods.
extension SMUploadFiles {
    // `internal` and not `private` so that we can use this from SMSyncServer.swift.
    internal func recovery(forceModeChangeReport forceModeChangeReport:Bool=true) {
        if SMUploadFiles.numberTimesTriedRecovery > SMUploadFiles.maxTimesToTryRecovery {
            Log.error("Failed recovery: Already tried \(SMUploadFiles.numberTimesTriedRecovery) times, and can't get it to work")
            
            // Yikes! What else can we do? Seems like we've given this our best effort in terms of recovery. Kick the error upwards.
            self.callSyncServerError(Error.Create("Failed to recover from SyncServer error after \(SMUploadFiles.numberTimesTriedRecovery) recovery attempts"))
            
            return
        }
        
        if forceModeChangeReport {
            SMUploadFiles.mode = SMClientModeWrapper.convertToRecovery(SMUploadFiles.mode)
        }
        
        SMSync.session.continueIf({
            return Network.session().connected()
        }, then: {
            // This gets executed if we have network access.
            SMUploadFiles.numberTimesTriedRecovery += 1
            
            switch (SMUploadFiles.mode) {
            case .Running(.Upload, _):
                self.uploadRecovery()
                
            case .Running(.BetweenUploadAndOutBoundTransfer, _):
                self.betweenUploadAndOutBoundTransferRecovery()
                
            case .Running(.OutboundTransfer, _),
                .Running(.AfterOutboundTransfer, _):
                self.outboundTransferRecovery()

            default:
                Assert.badMojo(alwaysPrintThisString: "Should not have this recovery mode")
            }
        })
    }
    
    private func delayedRecovery() {
        let duration = SMServerNetworking.exponentialFallbackDuration(forAttempt: SMUploadFiles.numberTimesTriedRecovery)

        TimedCallback.withDuration(duration) {
            self.recovery()
        }
    }
    
    // TODO: Create test case [3] in Upload tests.
    // We know that we are recovering from an error that occurred sometime between lock (inclusive) and commit (exclusive).
    private func uploadRecovery() {
        // TODO: Create test case [2] in Upload tests.

        SMServerAPI.session.uploadRecovery() {serverOperationId, fileIndex, apiResult in
            if (nil == apiResult.error) {
                // Either restart from scratch, or restart given the fileIndex of files that have been processed already.
                self.serverOperationId = serverOperationId
                self.prepareForUpload(givenAlreadyUploadedFiles: fileIndex)
            }
            else if apiResult.returnCode == SMServerConstants.rcLockNotHeld {
                // We tried to recover the upload, but didn't hold a lock. Must have had a failure when attempting to obtain the lock. We can't already have uploaded files given that we don't have the lock.
                self.prepareForUpload(givenAlreadyUploadedFiles: nil)
            }
            else {
                // Error, but try again later.
                self.delayedRecovery()
            }
        }
    }
    
    // It appears that some files were transferred to cloud storage, but we got an error part way through.
    private func outboundTransferRecovery() {

        SMServerAPI.session.outboundTransferRecovery { operationId, apiResult in
            var afterOutboundTransfer = false
            
            switch SMUploadFiles.mode {
            case .Running(.AfterOutboundTransfer, .Recovery):
                afterOutboundTransfer = true
                
            default:
                break
            }
            
            if (nil == apiResult.error) {
                self.serverOperationId = operationId
                // OK. Looks like a successful commit. We need to wait for the file transfer to complete.
                self.startToPollForOperationFinish()
            }
            else if SMServerConstants.rcLockNotHeld == apiResult.returnCode && afterOutboundTransfer {
                // Don't really need further recovery. The lock isn't held. And it's after the transfer.
                self.wrapUpOperation(nil)
            }
            else {
                // Error, but try again later.
                self.delayedRecovery()
            }
        }
    }
    
    // This is an ugly edge case-- falling between the two main recovery cases.
    // Getting to this point, it *seems* like the commitChanges failed. However, it's also possible that something just happened in getting the response back from the server and the commitChanges didn't fail. Need to determine if the commit was successful or not. I.e., if the operation is in progress (or has completed). If the commit was not successful, then we'll do .ChangesRecovery.

    private func betweenUploadAndOutBoundTransferRecovery() {
        if (nil == self.serverOperationId) {
            // Need to double check if we actually have an operationId. Server could have generated an operationId, but just failed to get it to us.
            SMServerAPI.session.getOperationId(){ (theServerOperationId, apiResult) in
                if nil == apiResult.error {
                    if nil == theServerOperationId {
                        SMUploadFiles.mode = .Running(.Upload, .Recovery)
                        self.recovery(forceModeChangeReport: false)
                    }
                    else {
                        self.serverOperationId = theServerOperationId
                        self.betweenUploadAndOutBoundTransferRecoveryAux()
                    }
                }
                else {
                    self.delayedRecovery()
                }
            }
        }
        else {
            self.betweenUploadAndOutBoundTransferRecoveryAux()
        }
    }
    
    private func betweenUploadAndOutBoundTransferRecoveryAux() {
        SMServerAPI.session.checkOperationStatus(serverOperationId: self.serverOperationId!) {operationResult, apiResult in
            if (apiResult.error != nil) {
                self.delayedRecovery()
            }
            else {
                // TODO: How do we ensure that the set of cases in mayHaveCommittedRecovery() matches those that can actually be returned?
                switch operationResult!.status {
                case SMServerConstants.rcOperationStatusNotStarted:
                    Log.msg("rcOperationStatusNotStarted")
                    /* 
                    Is it possible that the operation will start soon and progress into an InProgress state? It seems like it. The following would have to occur: (1) We get a failure in the return from SMSyncServer.session.commitChanges(), but that failure was a networking or other failure that wasn't actually because the SMSyncServer.session.commitChanges() failed on the server side, and (2) the server side was relatively slow in execution and the server side operation state hadn't yet changed to rcOperationStatusInProgress. So this is a combination of race condition and failure.
                    What can we do to resolve this? What if we poll for this to change for a certain period of time?
                    */
                    self.delayedRecovery()

                case SMServerConstants.rcOperationStatusCommitFailed:
                    Log.msg("rcOperationStatusCommitFailed")
                    // [1]. We'll do a little more work than necessary with the FileChangesRecovery, but since we've not transferred any files yet this will work to kick off a retry of the commit.
                    SMUploadFiles.mode = .Running(.Upload, .Recovery)
                    self.recovery(forceModeChangeReport: false)

                case SMServerConstants.rcOperationStatusSuccessfulCompletion:
                    Log.msg("wrapUpOperation called from rcOperationStatusSuccessfulCompletion")
                    self.wrapUpOperation(operationResult!)
                    
                case SMServerConstants.rcOperationStatusInProgress:
                    // TODO: How do we know if we get here and we have an InProgress status whether (a) InProgress really means in InProgress, or (b) the file transfer has some how failed with didn't record that fact? For now we're just going to assume that InProgress really means InProgress. We could improve this in the future by updating a time/date stamp in the operation status on the server when ever a certain amount of data has been transferred to cloud storage (if somehow that can be done). That way if the time/date stamp is too old, we'd have a good idea that InProgress was wrong and we really had a failure.
                    Log.msg("rcOperationStatusInProgress")
                    self.startToPollForOperationFinish()
                
                case SMServerConstants.rcOperationStatusFailedBeforeTransfer, SMServerConstants.rcOperationStatusFailedDuringTransfer, SMServerConstants.rcOperationStatusFailedAfterTransfer:

                    if 0 == operationResult!.count {
                        // Good. No files could have been transferred.
                        SMUploadFiles.mode = .Running(.Upload, .Recovery)
                    }
                    else {
                        var recoveryMode:SMRunningMode = .OutboundTransfer
                        
                        if SMServerConstants.rcOperationStatusFailedAfterTransfer == operationResult!.status {
                            recoveryMode = .AfterOutboundTransfer
                        }
                        
                        // This is a more difficult case. What do we do?
                        SMUploadFiles.mode = .Running(recoveryMode, .Recovery)
                    }
                    
                    self.recovery(forceModeChangeReport: false)
                    
                default:
                    let msg = "Yikes: Unknown operationStatus: \(operationResult!.status)"
                    Log.error(msg)
                    self.callSyncServerError(Error.Create(msg))
                }
            }
        }
    }
}

#endif

// MARK: SMServerAPIUploadDelegate methods

extension SMUploadFiles : SMServerAPIUploadDelegate {
    internal func smServerAPIFileUploaded(serverFile : SMServerFile) {
        // Switch over the operation stage for the change to .CloudStorage (and don't delete the upload) so that we still have the info to later, once the outbound transfer has completed, to send delegate callbacks to the app using the api.
        let change:SMUploadFileOperation? = SMQueues.current().beingUploaded!.getChange(forUUID:serverFile.uuid.UUIDString)
        Assert.If(change == nil, thenPrintThisString: "Yikes: Couldn't get upload for uuid \(serverFile.uuid.UUIDString)")
        change!.operationStage = .CloudStorage
        
        self.syncServerDelegate?.syncServerEventOccurred(.SingleUploadComplete(uuid: serverFile.uuid))
    }
}


