//
//  SMUploadFiles.swift
//  NetDb
//
//  Created by Christopher Prince on 12/12/15.
//  Copyright © 2015 Spastic Muffin, LLC. All rights reserved.
//

// Algorithms for uploading and deletion of files to the SyncServer.
// This class' resources are either private or internal. It is not intended for use by classes outside of the SMSyncServer framework.

import Foundation
import SMCoreLib

/* 
This class uses RepeatingTimer. It must have NSObject as a base class.
*/
internal class SMUploadFiles : NSObject, SMSyncDelayedOperationDelegate {
    // This is a singleton because we need centralized control over the file upload operations.
    internal static let session = SMUploadFiles()
    
    internal weak var delegate:SMSyncServerDelegate?
    
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
                .Running(.OutboundTransfer, _):
                break
            case .Idle, .NonRecoverableError:
                break
                
            default:
                Assert.badMojo(alwaysPrintThisString: "Yikes: Bad mode value for SMUploadFiles!")
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

    // This describes the files that need to be uploaded/deleted on the server. And the set of changes that need to be synced against the local meta data.
    private var pendingUploadFiles:[SMServerFile]?
    private var pendingDeleteFiles:[SMServerFile]?

    private override init() {
        super.init()
    }
    
    // TODO: Right now this is being called after sign in is completed. That seems good. But what about the app going into the background and coming into the foreground? This can cause a server API operation to fail, and we should initiate recovery at that point too.
    internal func appLaunchSetup() {
        SMSync.session.delayDelegate = self
        SMServerAPI.session.uploadDelegate = self
    }
    
    // If an upload is currently in progress, an upload will be done as soon as the current one is completed.
    internal func prepareForUpload() {
        SMSync.session.startOrDelay()
    }
    
    // MARK: Start SMSyncDelayedOperationDelegate method
    
    // I don't think this can actually be private to be called as a delegate method. But conceptually, it's private.
    internal func smSyncDelayedOperation() {
        self.prepareForUpload(givenAlreadyUploadedFiles: nil)
    }
    
    // MARK: End SMSyncDelayedOperationDelegate method

    // Doesn't actually recover from the error. Expect the caller to somehow do that. Just resets the mode so this class can later proceed.
    internal func resetFromError() {
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
        SMSync.session.startDelayed(currentlyOperating: true)
        self.delegate?.syncServerEventOccurred(.OutboundTransferComplete(numberOperations: numberOperations))
    }
    
    private func callSyncServerError(error:NSError) {
        // We've had an API error or an error we couldn't deal with. Don't try to do any pending next operation.
        
        // Set the mode to .NonRecoverableError so that if the app restarts we don't try to recover again. This also has the additional effect of forcing the caller of this class to do something to recover. i.e., at least to call the resetFromError method.
        
        SMSync.session.stop()
        SMUploadFiles.mode = .NonRecoverableError(error)
    }
    
    // MARK: End: Methods that call delegate methods

    // The alreadyUploadedFiles parameter is for usage of this method in recovery: The parameter gives the collection of files that have already been uploaded to the SyncServer (but not yet transferred to cloud storage).
    private func prepareForUpload(givenAlreadyUploadedFiles alreadyUploadedFiles:[SMServerFile]?) {
        
        let localChanges = SMFileDiffs(type: .LocalChanges)
        Log.msg("\(localChanges.count) local files have changed")
        if localChanges.count == 0 {
            // We are the operation executing, so we're safe to stop.
            SMSync.session.stop()
            return
        }
        
        // The .UploadRecovery recovery mode will let us know we need to recover if we fail sometime prior to the commmit operation. When the app restarts and/or we regain network access, we'll check this flag and see what we need to do.
        SMUploadFiles.mode = .Running(.Upload, .Operating)
        
        SMServerAPI.session.lock() { lockResult in
            Log.msg("lock: \(lockResult.error)")
            
            if SMTest.If.success(lockResult.error, context: .Lock) {
                SMServerAPI.session.getFileIndex() { fileIndex, gfiResult in
                    if SMTest.If.success(gfiResult.error, context: .GetFileIndex) {
                        Log.msg("Success on getFileIndex!")
                        
                        self.doDeletionAndUpload(localChanges, serverFileIndex:fileIndex, alreadyUploadedFiles:alreadyUploadedFiles)
                    }
                    else {
                        // Error with SMSyncServer.session.getFileIndex; do recovery.
                        self.recovery()
                    }
                }
            }
            else {
                // Error with SMSyncServer.session.lock
                // Cleaning up may not be needed as we may not hold the lock, but do it anyways to be safe.
                // TODO: Possible that we don't have a network connection at this point, and we actually hold the lock. I.e., the problem was that the server just didn't return the right return code to us. Seems this will have to be solved later by a lock breaking strategy.
                self.recovery()
            }
        }
    }
    
    private func doDeletionAndUpload(localChanges:SMFileDiffs, serverFileIndex:[SMServerFile]?, alreadyUploadedFiles:[SMServerFile]?) {
    
        localChanges.serverFileIndex = serverFileIndex
        
        var error:NSError?
        var filesToUpload:[SMServerFile]?
        
        (self.pendingDeleteFiles, error) = localChanges.filesToDelete()
        if nil == error {
            // Call filesToUpload with only having set serverFileIndex so we know how to update the meta data should the upload be successful
            (self.pendingUploadFiles, error) = localChanges.filesToUpload()
        }
     
        if nil == error {
            // This to deal with the recovery case: If we've already uploaded some files, and are restarting the upload.
            localChanges.alreadyUploaded = alreadyUploadedFiles
            (filesToUpload, error) = localChanges.filesToUpload()
        }
        
        if error != nil {
            self.callSyncServerError(error!) // Not a recovery case
            return
        }
        
        // Do the deletion first, if there are any files to delete, just because the deletion should be fast.
        SMServerAPI.session.deleteFiles(self.pendingDeleteFiles) { dfResult in
            if (nil == dfResult.error) {
                if self.pendingDeleteFiles != nil && self.pendingDeleteFiles!.count > 0 {
                    var uuids = [NSUUID]()
                    for fileToDelete in self.pendingDeleteFiles! {
                        uuids.append(fileToDelete.uuid)
                    }
                    
                    self.delegate?.syncServerEventOccurred(.DeletionsSent(uuids: uuids))
                }
                
                self.doUpload(withFilesToUpload: filesToUpload!)
            }
            else {
                self.recovery()
            }
        }
    }
    
    // TODO: What happens to the server side execution when: (1) The app terminates (e.g., crashes, goes into background) while the server is running but the operation hasn't ended, yet, and (2) the app terminates and the operation has ended (as with the end of the commitChanges operation). I've been assuming with (2) at least that the server side execution will *not* be interrupted or otherwise altered.
    
    // GOAL: Work on restarting uploads that have been interrupted prior to completion of a commitChanges operation. How do we tell, algorithmically, that this is needed?

    private func doUpload(withFilesToUpload filesToUpload:[SMServerFile]) {

        SMServerAPI.session.uploadFiles(filesToUpload) { uploadResult in
            Log.msg("SMSyncServer.session.uploadFiles: \(uploadResult.error)")
            
            if SMTest.If.success(uploadResult.error, context: .UploadFiles) {
            
                // Just about to do the commit. If we detect failure of the commit on the client, we'll not be fully sure if the commit succeeded. E.g., we could lose a network connection as the commit is operating making it look as if the commit failed, but it actually succeeded.
                SMUploadFiles.mode = .Running(.BetweenUploadAndOutBoundTransfer, .Operating)

                SMServerAPI.session.startOutboundTransfer() { operationId, sotResult in
                    Log.msg("SMSyncServer.session.startOutboundTransfer: \(sotResult.error); operationId: \(operationId)")
                    if SMTest.If.success(sotResult.error, context: .OutboundTransfer) {
                        self.serverOperationId = operationId
                        // We *know* we have a successful commit. Change to our last recovery case.
                        SMUploadFiles.mode = .Running(.OutboundTransfer, .Operating)
                        
                        self.startToPollForOperationFinish()
                    }
                    else {
                        self.recovery()
                    }
                }
            }
            else {
                if (uploadResult.returnCode == SMServerConstants.rcServerAPIError) {
                    // Can't recover immediately within the SMSyncServer. This must have been a client error.
                    self.callSyncServerError(uploadResult.error!)
                }
                else {
                    // Failed on uploadFiles-- Attempt recovery.
                    self.recovery()
                }
            }
        }
    }
    
    // Start timer to poll the server to check if our operation has succeeded. That check will update our local file meta data if/when the file sync completes successfully.
    private func startToPollForOperationFinish() {
        SMUploadFiles.mode = .Running(.OutboundTransfer, .Operating)

        self.checkIfUploadOperationFinishedTimer = RepeatingTimer(interval: SMUploadFiles.TIME_INTERVAL_TO_CHECK_IF_OPERATION_SUCCEEDED_S, selector: "pollIfFileOperationFinished", andTarget: self)
        self.checkIfUploadOperationFinishedTimer!.start()
    }
    
    // PRIVATE
    // TODO: How do we know if we've been checking for too long?
    func pollIfFileOperationFinished() {
        Log.msg("checkIfFileOperationFinished")
        self.checkIfUploadOperationFinishedTimer!.cancel()
        
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
                    // This will do more work than necessary (e.g., checking with the server again for operation status), but it handles these three cases.
                    self.recovery()
                    
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
        
        // TODO: We need to persist the data needed for this meta data sync because we may not have it in all cases otherwise. E.g., in the MayHaveCommittedRecovery case.
        let numberUploads = self.syncLocalMetaData()
        Assert.If(numberUploads != operationResult.count, thenPrintThisString: "Something bad is going on: numberUploads \(numberUploads) was not the same as the operation count")
        
        SMUploadFiles.mode = .Idle
        
        // Now that we know we succeeded, we can remove the Operation Id from the server. In some sense it's not a big deal if this fails. HOWEVER, since we set self.serverOperationId to nil on completion (see [4]), it is a big deal: I just ran into an apparent race condition where in testThatTwoSeriesFileUploadWorks(), I got a crash because self.serverOperationId was nil. Seems like this crash occurred because the removeOperationId completion handler for the first upload was called *after* the second call to startFileChanges completed. To avoid this race condition, I'm going to delay the syncServerCommitComplete callback until removeOperationId completes.
        SMServerAPI.session.removeOperationId(serverOperationId: self.serverOperationId!) { apiResult in
        
            self.serverOperationId = nil // [4]

            if (apiResult.error == nil) {
                self.callSyncServerCommitComplete(numberOperations: numberUploads)
            }
            else {
                // While this may not seem like much of an error, treat it seriously because it could be indicating a network error. If I don't treat it seriously, I can proceed forward which could leave the upload in the wrong recovery mode.
                Log.file("Failed removing OperationId from server: \(apiResult.error)")
                self.recovery()
            }
        }
    }

    // Given that the upload of files was successful, update the local meta data to reflect that successful upload.
    // Returns the number of uploads/deletes that happened.
    private func syncLocalMetaData() -> Int {
        var numberUpdates = 0
        var numberNewFiles = 0
        var numberDeletions = 0
        
        if self.pendingDeleteFiles != nil {
            for deletedServerFile in self.pendingDeleteFiles! {
                let deletedLocalFile = deletedServerFile.localFile!
                
                deletedLocalFile.deletedOnServer = true
                deletedLocalFile.pendingLocalChanges = nil
                
                numberDeletions++
            }
        }
        
        if self.pendingUploadFiles != nil {
            for serverFile in self.pendingUploadFiles! {
                let localFile = serverFile.localFile!
                
                // The intent here is that the oldest change will be the one we have been processing because we used getMostRecentChangeAndFlush when obtaining the change. In most cases, calling removeOldestChange will leave us with no changes because the user will not have made another change that quickly.
                let fileChange = localFile.removeOldestChange()
                Assert.If(nil == fileChange, thenPrintThisString: "Yikes: No SMFileChange!")
                
                if fileChange!.deleteLocalFileAfterUpload!.boolValue {
                    let url = NSURL(fileURLWithPath: fileChange!.localFileNameWithPath!)
                    let fileWasDeleted = FileStorage.deleteFileWithPath(url)
                    Assert.If(!fileWasDeleted, thenPrintThisString: "File could not be deleted")
                }
                
                if 0 == serverFile.version {
                    numberNewFiles++
                }
                else {
                    localFile.localVersion = localFile.localVersion!.integerValue + 1
                    Log.msg("New local file version: \(localFile.localVersion)")
                    numberUpdates++
                }
            }
        }
        
        CoreData.sessionNamed(SMCoreData.name).saveContext()
        
        Log.msg("Number updates: \(numberUpdates)")
        Log.msg("Number new files: \(numberNewFiles)")
        Log.msg("Number deletions: \(numberDeletions)")
        
        self.pendingUploadFiles = nil
        self.pendingDeleteFiles = nil
        
        return numberUpdates + numberNewFiles + numberDeletions
    }
}

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
            SMUploadFiles.numberTimesTriedRecovery++
            
            switch (SMUploadFiles.mode) {
            case .Running(.Upload, _):
                self.uploadRecovery()
                
            case .Running(.BetweenUploadAndOutBoundTransfer, _):
                self.betweenUploadAndOutBoundTransferRecover()
                
            case .Running(.OutboundTransfer, _):
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
    
    // It appears that some files were transferred to cloud storage, but we got an error part way through. With our assumptions so far, we'll still hold a lock.
    private func outboundTransferRecovery() {

        // Since we still hold the lock, we can try to recover using the fileChangesRecovery. Again, it will do a little more work than we want, but it will get to the point of retrying the transfers from the SyncServer to cloud storage again. Will it retry the ones that have already been done? No. For successful transfers, the server will have removed those from the outbound files and added entries into the PSFileIndex. For failure, it is possible that we have some inconsistency in the server tables. E.g., a file was transferred, its entry removed from the outbound file changes, but its entry didn't make it into the file index.
        // It would be good to do a server integrity check based on our current expectations of what should be there.

        SMServerAPI.session.outboundTransferRecovery { apiResult in
            if (nil == apiResult.error) {
                // OK. Looks like a successful commit. We need to wait for the file transfer to complete.
                self.startToPollForOperationFinish()
            }
            else {
                // Error, but try again later.
                self.delayedRecovery()
            }
        }
    }
    
    // This is an ugly edge case-- falling between the two main recovery cases.
    // Getting to this point, it *seems* like the commitChanges failed. However, it's also possible that something just happened in getting the response back from the server and the commitChanges didn't fail. Need to determine if the commit was successful or not. I.e., if the operation is in progress (or has completed). If the commit was not successful, then we'll do .ChangesRecovery.

    private func betweenUploadAndOutBoundTransferRecover() {
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
                        self.betweenUploadAndOutBoundTransferRecoverAux()
                    }
                }
                else {
                    self.delayedRecovery()
                }
            }
        }
        else {
            self.betweenUploadAndOutBoundTransferRecoverAux()
        }
    }
    
    private func betweenUploadAndOutBoundTransferRecoverAux() {
        SMServerAPI.session.checkOperationStatus(serverOperationId: self.serverOperationId!) {operationResult, apiResult in
            if (apiResult.error != nil) {
                self.delayedRecovery()
            }
            else {
                // TODO: How do we ensure that the set of cases in mayHaveCommittedRecovery() matches those that can actually be returned?
                switch (operationResult!.status) {
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
                        // This is a more difficult case. What do we do?
                        SMUploadFiles.mode = .Running(.OutboundTransfer, .Recovery)
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

// MARK: SMServerAPIUploadDelegate methods

extension SMUploadFiles : SMServerAPIUploadDelegate {
    internal func smServerAPIFileUploaded(file: NSUUID) {
        self.delegate?.syncServerEventOccurred(.SingleUploadComplete(uuid: file))
    }
}

