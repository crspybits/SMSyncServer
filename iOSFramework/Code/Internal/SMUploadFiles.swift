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

internal enum SMUploadFilesMode : Int {
    // Non-error, non-recovery operating condition
    case Normal
    
    // We've reported an error that SMUploadFiles couldn't recover from. Keep a persistent record of that error until we're assured of externally provided recovery.
    case NonRecoverableError

    // We're going to categorize errors on the server into a few main types for the purpose of recovery:
    
    // 1) An error occurred *prior* to any files being transferred to cloud storage. i.e., an error occured between lock and commitChanges, prior to a successful commitChanges. (By successful commitChanges, I mean that the commit successfully started asynchronous operation of the file upload on the server).
    case ChangesRecovery
    
    // 2) An edge recovery case that needs more execution-time evaluation to determine whether to categorize it as FileChangesRecovery or CloudStorageTransferRecovery.
    case MayHaveCommittedRecovery
    
    // 3) An error occurred and some files (or parts of files) may have been transferred to cloud storage. This occurs strictly after the FileChangesRecovery mode. i.e., commitChanges *was* successful.
    case CloudStorageTransferRecovery
}

/* 
This class uses RepeatingTimer. It must have NSObject as a base class.
*/
internal class SMUploadFiles : NSObject {
    // This is a singleton because we need centralized control over the file upload operations.
    internal static let session = SMUploadFiles()
    
    internal weak var delegate:SMSyncServerDelegate?
    
    // To ensure that multiple calls to upload cannot be occuring at the same time.
    private var currentlyOperating = false
    
    internal var isOperating: Bool {
        get {
            return self.currentlyOperating
        }
    }
    
    // I could make these a persistent var, but little seems to be gained by that other than reducing the number of times we try to recover. I've made this a "static" so I can access it within the setMode method below.
    private static var numberTimesTriedFileChangesRecovery = 0
    private static var numberTimesTriedMayHaveCommittedRecovery = 0
    private static var numberTimesTriedCloudStorageTransferRecovery = 0

    internal static var maxTimesToTryRecovery = 3
    
    // true iff another upload operation needs to be done immediately after the current one is done.
    private static let _doOperationLater = SMPersistItemBool(name: "SMUploadFiles.DoOperationLater", initialBoolValue: false, persistType: .UserDefaults)
    
    // Persisting this variable because we need to be know what mode we are operating in even if the app is restarted or crashes.
    private static let _mode = SMPersistItemInt(name: "SMUploadFiles.Mode", initialIntValue: SMUploadFilesMode.Normal.rawValue, persistType: .UserDefaults)
    
    // Similarly, for error recovery, it's useful to have the operationId if we have one.
    private static let _operationId = SMPersistItemString(name: "SMUploadFiles.OperationId", initialStringValue: "", persistType: .UserDefaults)
    
    // TODO: If we fail on an attempt at recovery, we may to impose a timed interval between recovery attempts. E.g., if the server went down, we'd like to give it time to come back up.
    
    // [3]. For software engineering integrity purposes, classes outside of this one should not be able to set the mode.
    internal class var mode:SMUploadFilesMode {
        get {
            return SMUploadFilesMode(rawValue: _mode.intValue)!
        }
    }
    
    // As above [3]. Only this class should be able to set the mode.
    private class func setMode(newMode:SMUploadFilesMode) {
        _mode.intValue = newMode.rawValue
        
        switch (newMode) {
        case .ChangesRecovery:
            numberTimesTriedFileChangesRecovery = 0

        case .MayHaveCommittedRecovery:
            numberTimesTriedMayHaveCommittedRecovery = 0
        
        case .CloudStorageTransferRecovery:
            numberTimesTriedCloudStorageTransferRecovery = 0
            
        default:
            break
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
    
    // This describes the files that need to be uploaded/deleted on the server. And the set of changes that need to be synced against the local meta data.
    private var pendingUploadFiles:[SMServerFile]?
    private var pendingDeleteFiles:[SMServerFile]?

    private static let TIME_INTERVAL_TO_CHECK_IF_OPERATION_SUCCEEDED_S:Float = 5
        
    private override init() {
        super.init()
    }
    
    internal func appLaunchSetup() {
        self.start(withCurrentlyOperatingExpected: false)
    }
    
    internal func networkOnline() {
        // currentlyOperating can be false when the network comes back online (the typical case because an operation likely failed), or possibly true if there was a quick bump in the network online/offline state.
        self.start(withCurrentlyOperatingExpected: nil)
    }
    
    // Call this when the app starts or the network comes back online. When called because the network came back online, and recovery is already in process, the .Do cases will have no effect. If we come back online in .Normal mode, and we are currentlyOperating, we'll just do nothing. 'Cause not quite sure what to do there. ALSO: This should prevent us from doing anything if we get multiple consecutive calls indicating the network is online.
    private func start(withCurrentlyOperatingExpected currentlyOperatingExpected:Bool?) {
        switch (SMUploadFiles.mode) {
            case .Normal:
                self.sync(.DoDelayed(currentlyOperatingExpected: currentlyOperatingExpected),
                    nextOperation: {
                        self.prepareForUpload(givenAlreadyUploadedFiles: nil)
                    })

            case .ChangesRecovery:
                self.sync(.Do, currentOperation: {
                    self.fileChangesRecovery()
                })
            
            case .MayHaveCommittedRecovery:
                self.sync(.Do, currentOperation: {
                    self.mayHaveCommittedRecovery()
                })
            
            case .CloudStorageTransferRecovery:
                self.sync(.Do, currentOperation: {
                    self.cloudStorageTransferRecovery()
                })
            
            case .NonRecoverableError:
                Assert.badMojo(alwaysPrintThisString: "Not yet implemented")
        }
    }
    
    // If an upload is currently in progress, an upload will be done as soon as the current one is completed.
    internal func prepareForUpload() {
        self.sync(.DoOrDelay, nextOperation: {
            self.prepareForUpload(givenAlreadyUploadedFiles: nil)
        })
    }
    
    // Doesn't actually recover from the error. Expect the caller to somehow do that. Just resets the mode so this class can later proceed.
    internal func resetFromError() {
        Assert.If(SMUploadFiles.mode != .NonRecoverableError, thenPrintThisString: "We're not in the NonRecoverableError mode")
        SMUploadFiles.setMode(.Normal)
    }
    
    private enum OperationSyncType {
        // Unconditionally do an operation (includes upload and recovery operations). Must not currently be operating.
        case Do
        
        // Do the upload unless there is an upload currently happening.
        case DoOrDelay
        
        // Do a delayed upload if there is one.
        case DoDelayed(currentlyOperatingExpected:Bool?)
        
        // Conditionally stop operations. E.g., possible network loss.
        case ConditionalStop(stopConditional:()->Bool)
        
        // Completely stop operations. E.g., an API error or failed during multiple recovery attempts.
        case Stop
    }
    
    // Centralize access to SMUploadFiles._doOperationLater and self.currentlyOperating so we don't get multiple operations being executed concurrently.
    // In the .ConditionalStop case, the stopConditional will be executed within with the Synchronized.block
    private func sync(syncType:OperationSyncType, currentOperation:(()->())?=nil, nextOperation:(()->())?=nil) {
    
        var doCurrent:Bool = false
        var doNext:Bool = false
        
        Synchronized.block(self) {
        
            func stop() {
                Log.msg("Stopping!")
                self.currentlyOperating = false
                SMUploadFiles._doOperationLater.boolValue = false
                doCurrent = true
            }
            
            switch (syncType) {
            case .Do:
                if self.currentlyOperating {
                    Log.warning(".Do, but self.currentlyOperating is true")
                }
                else {
                    self.currentlyOperating = true
                    SMUploadFiles._doOperationLater.boolValue = false
                    doCurrent = true
                    doNext = true
                }
                
            case .DoOrDelay:
                if self.currentlyOperating {
                    Log.warning(".DoOrDelay: Currently operating");
                    SMUploadFiles._doOperationLater.boolValue = true
                }
                else {
                    self.currentlyOperating = true
                    
                    // This shouldn't be necessary, but just to be safe.
                    SMUploadFiles._doOperationLater.boolValue = false
                    
                    doCurrent = true
                    doNext = true
                }
                
            case .DoDelayed (let currentlyOperatingExpected):
                if currentlyOperatingExpected == nil {
                    // Not quite sure what to do here if we *are* currently operating: This will be for the case of the network coming back online in .Normal mode. Just return and cross our fingers.
                    if self.currentlyOperating {
                        return
                    }
                }
                else {
                    Assert.If(currentlyOperatingExpected! != self.currentlyOperating, thenPrintThisString: "Didn't get expected currentlyOperating value")
                }
                
                let needToUploadAgain = SMUploadFiles._doOperationLater.boolValue
                if !needToUploadAgain {
                    self.currentlyOperating = false
                }
                // Else: self.currentlyOperating remains true because we'll start an upload next.
                
                SMUploadFiles._doOperationLater.boolValue = false
                
                doCurrent = true
                
                if needToUploadAgain {
                    doNext = true
                }
            
            // If the stopConditional returns true, then the nextOperation is *not* executed.
            case .ConditionalStop (let stopConditional):
                if stopConditional() {
                    stop()
                }
                else {
                    // Not stopping: Do the next operation.
                    doNext = true
                }
                
            case .Stop:
                stop()
            }

        } // End Synchronized.block(self)
        
        if doCurrent {
            currentOperation?()
        }
        
        if doNext {
            nextOperation?()
        }
    }
    
    //MARK: Don't call the "completion" delegate methods directly; call these methods instead-- so that we ensure the self.currentlyOperating flag is maintained correctly.
    private func callSyncServerCommitComplete(numberOperations numberOperations:Int?) {
        self.sync(.DoDelayed(currentlyOperatingExpected:true), currentOperation: {
            self.delegate?.syncServerCommitComplete(numberOperations: numberOperations)
        }, nextOperation: {
            self.prepareForUpload(givenAlreadyUploadedFiles: nil)
        })
    }
    
    private func callSyncServerError(error:NSError) {
        // We've had an API error. Don't try to do any pending next operation.
        
        // Set the mode to .NonRecoverableError so that if the app restarts we don't try to recover again. This also has the additional effect of forcing the caller of this class to do something to recover. i.e., at least to call the resetFromError method.
        SMUploadFiles.setMode(.NonRecoverableError)
        
        self.sync(.Stop, currentOperation: {
            self.delegate?.syncServerError(error)
        })
    }
    
    // The alreadyUploadedFiles parameter is for usage of this method in recovery: The parameter gives the collection of files that have already been uploaded to the SyncServer (but not yet transferred to cloud storage).
    private func prepareForUpload(givenAlreadyUploadedFiles alreadyUploadedFiles:[SMServerFile]?) {
        
        let changedFiles = SMChangedFiles()
        Log.msg("\(changedFiles.count) files have changed")
        if changedFiles.count == 0 {
            // We have a lock on SMUploadFiles, so we're safe to .Stop, not .DoDelayed
            self.sync(.Stop, currentOperation: nil)
            return
        }
        
        // The .FileChangesRecovery recovery mode will let us know we need to recover if we fail sometime prior to the commmit operation. When the app restarts and/or we regain network access, we'll check this flag and see what we need to do.
        SMUploadFiles.setMode(.ChangesRecovery)
        
        SMServerAPI.session.lock() { error in
            Log.msg("lock: \(error)")
            
            if SMTest.If.success(error, context: .Lock) {
                SMServerAPI.session.getFileIndex() { fileIndex, error in
                    if SMTest.If.success(error, context: .GetFileIndex) {
                        Log.msg("Success on getFileIndex!")
                        
                        self.doDeletionAndUpload(changedFiles, serverFileIndex:fileIndex, alreadyUploadedFiles:alreadyUploadedFiles)
                    }
                    else {
                        // Error with SMSyncServer.session.getFileIndex; do recovery.
                        self.fileChangesRecovery()
                    }
                }
            }
            else {
                // Error with SMSyncServer.session.startFileChanges
                // Cleaning up may not be needed as we may not hold the lock, or have an operationId, but do it anyways to be safe.
                self.fileChangesRecovery()
            }
        }
    }
    
    private func doDeletionAndUpload(changedFiles:SMChangedFiles, serverFileIndex:[SMServerFile]?, alreadyUploadedFiles:[SMServerFile]?) {
    
        changedFiles.serverFileIndex = serverFileIndex
        
        var error:NSError?
        var filesToUpload:[SMServerFile]?
        
        (self.pendingDeleteFiles, error) = changedFiles.filesToDelete()
        if nil == error {
            // Call filesToUpload with only having set serverFileIndex so we know how to update the meta data should the upload be successful
            (self.pendingUploadFiles, error) = changedFiles.filesToUpload()
        }
     
        if nil == error {
            // This to deal with the recovery case: If we've already uploaded some files, and are restarting the upload.
            changedFiles.alreadyUploaded = alreadyUploadedFiles
            (filesToUpload, error) = changedFiles.filesToUpload()
        }
        
        if error != nil {
            self.callSyncServerError(error!) // Not a recovery case
            return
        }
        
        // Do the deletion first, if there are any files to delete, just because the deletion should be fast.
        SMServerAPI.session.deleteFiles(self.pendingDeleteFiles) { error in
            if (nil == error) {
                if self.pendingDeleteFiles != nil && self.pendingDeleteFiles!.count > 0 {
                    var uuids = [NSUUID]()
                    for fileToDelete in self.pendingDeleteFiles! {
                        uuids.append(fileToDelete.uuid)
                    }
                    self.delegate?.syncServerDeletionsSent(uuids)
                }
                
                self.doUpload(withFilesToUpload: filesToUpload!)
            }
            else {
                self.fileChangesRecovery()
            }
        }
    }
    
    // TODO: What happens to the server side execution when: (1) The app terminates (e.g., crashes, goes into background) while the server is running but the operation hasn't ended, yet, and (2) the app terminates and the operation has ended (as with the end of the commitChanges operation). I've been assuming with (2) at least that the server side execution will *not* be interrupted or otherwise altered.
    
    // GOAL: Work on restarting uploads that have been interrupted prior to completion of a commitChanges operation. How do we tell, algorithmically, that this is needed?

    private func doUpload(withFilesToUpload filesToUpload:[SMServerFile]) {

        SMServerAPI.session.uploadFiles(filesToUpload, perUploadCallback:
                self.delegate?.syncServerSingleUploadComplete
            ) { returnCode, error in
            Log.msg("SMSyncServer.session.uploadFiles: \(error)")
            
            if SMTest.If.success(error, context: .UploadFiles) {
            
                // Just about to do the commit. If we detect failure of the commit on the client, we'll not be fully sure if the commit succeeded. E.g., we could lose a network connection as the commit is operating making it look as if the commit failed, but it actually succeeded.
                SMUploadFiles.setMode(.MayHaveCommittedRecovery)

                SMServerAPI.session.commitChanges() { operationId, error in
                    Log.msg("SMSyncServer.session.commitChanges: \(error); operationId: \(operationId)")
                    if SMTest.If.success(error, context: .CommitChanges) {
                        self.serverOperationId = operationId
                        // We *know* we have a successful commit. Change to our last recovery case.
                        SMUploadFiles.setMode(.CloudStorageTransferRecovery)
                        
                        self.startToPollForOperationFinish()
                    }
                    else {
                        // Failed on commitChanges
                        self.mayHaveCommittedRecovery()
                    }
                }
            }
            else {
                if (returnCode == SMServerConstants.rcServerAPIError) {
                    // Can't recover immediately within the SMSyncServer. This must have been a client error.
                    self.callSyncServerError(error!)
                }
                else {
                    // Failed on uploadFiles-- Attempt recovery.
                    self.fileChangesRecovery()
                }
            }
        }
    }
    
    // Start timer to poll the server to check if our operation has succeeded. That check will update our local file meta data if/when the file sync completes successfully.
    private func startToPollForOperationFinish() {
        SMUploadFiles.setMode(.CloudStorageTransferRecovery)

        self.checkIfUploadOperationFinishedTimer = RepeatingTimer(interval: SMUploadFiles.TIME_INTERVAL_TO_CHECK_IF_OPERATION_SUCCEEDED_S, selector: "pollIfFileOperationFinished", andTarget: self)
        self.checkIfUploadOperationFinishedTimer!.start()
    }
    
    // PRIVATE
    // TODO: How do we know if we've been checking for too long?
    func pollIfFileOperationFinished() {
        Log.msg("checkIfFileOperationFinished")
        self.checkIfUploadOperationFinishedTimer!.cancel()
        
        SMServerAPI.session.checkOperationStatus(serverOperationId: self.serverOperationId!) {operationResult, error in
            if (error != nil) {
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
                    self.wrapUpOperation(operationResult!)
                
                case SMServerConstants.rcOperationStatusFailedBeforeTransfer, SMServerConstants.rcOperationStatusFailedDuringTransfer, SMServerConstants.rcOperationStatusFailedAfterTransfer:
                    // This will do more work than necessary (e.g., checking with the server again for operation status), but it handles these three cases.
                    self.mayHaveCommittedRecovery()
                    
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
        
        SMUploadFiles.setMode(.Normal)
        
        // Now that we know we succeeded, we can remove the Operation Id from the server. In some sense it's not a big deal if this fails. HOWEVER, since we set self.serverOperationId to nil on completion (see [4]), it is a big deal: I just ran into an apparent race condition where in testThatTwoSeriesFileUploadWorks(), I got a crash because self.serverOperationId was nil. Seems like this crash occurred because the removeOperationId completion handler for the first upload was called *after* the second call to startFileChanges completed. To avoid this race condition, I'm going to delay the syncServerCommitComplete callback until removeOperationId completes.
        SMServerAPI.session.removeOperationId(serverOperationId: self.serverOperationId!) { error in
        
            self.serverOperationId = nil // [4]

            if (error != nil) {
                // Not much of an error, but log it.
                Log.file("Failed removing OperationId from server: \(error)")
            }
            
            self.callSyncServerCommitComplete(numberOperations: numberUploads)
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
    
    private func exponentialFallbackDuration(numberTimesTried:Int) -> Float {
        let duration:Float = pow(Float(numberTimesTried), 2.0)
        Log.msg("Failed recovery: But will try again in \(duration) seconds")
        return duration
    }
    
    // TODO: Create test case [3] in Upload tests.
    // We know that we are recovering from an error that occurred sometime between startFileChanges (inclusive) and commitChanges (exclusive).
    private func fileChangesRecovery() {
        self.delegate?.syncServerRecovery(.FileChanges)
        
        // TODO: Create test case [2] in Upload tests.
        
        // Don't attempt the recovery if we don't have network access. This instance of stopping is not an API error. Doing this in self.sync because we'll need to stop operations if the network has failed (e.g., network failure could be the reason that the original operation failed and whey we're in fileChangesRecovery).

        self.sync(.ConditionalStop(stopConditional: {
            
            // The network failure test must be executed within the self.sync Synchronized.block to avoid a race condition between the restart due to the network coming back online. e.g., either this self.sync call will start the next operation (recovery) or the network online callback will, but not both.
            return !Network.session().connected()
            
        }), nextOperation: {
            // This gets executed if we have network access.

            SMUploadFiles.numberTimesTriedFileChangesRecovery++

            SMServerAPI.session.changesRecovery() {serverOperationId, fileIndex, error in
                if (nil == error) {
                    // Either restart from scratch, or restart given the fileIndex of files that have been processed already.
                    self.serverOperationId = serverOperationId
                    self.prepareForUpload(givenAlreadyUploadedFiles: fileIndex)
                }
                else if SMUploadFiles.numberTimesTriedFileChangesRecovery < SMUploadFiles.maxTimesToTryRecovery {
                    
                        // Error, but try again later.
                    
                        let duration = self.exponentialFallbackDuration(SMUploadFiles.numberTimesTriedFileChangesRecovery)

                        TimedCallback.withDuration(duration) {
                            self.fileChangesRecovery()
                        }
                }
                else {
                    Log.error("Failed recovery: Already tried \(SMUploadFiles.numberTimesTriedFileChangesRecovery) times, and can't get it to work")
                    
                    // Yikes! What else can we do? Seems like we've given this our best effort in terms of recovery. Kick the error upwards.
                    self.sync(.Stop, currentOperation: {
                        self.callSyncServerError(Error.Create("Failed to recover from SyncServer error after \(SMUploadFiles.numberTimesTriedFileChangesRecovery) recovery attempts"))
                    })
                }
            }
        })
    }
    
    // It appears that some files were transferred to cloud storage, but we got an error part way through. With our assumptions so far, we'll still hold a lock.
    private func cloudStorageTransferRecovery() {
        self.delegate?.syncServerRecovery(.CloudStorageTransfer)

        self.sync(.ConditionalStop(stopConditional: {
            return !Network.session().connected()
        }), nextOperation: {
            // This gets executed if we have network access.
            SMUploadFiles.numberTimesTriedCloudStorageTransferRecovery++
            self.cloudStorageTransferRecoveryAux()
        })
    }
    
    private func cloudStorageTransferRecoveryAux() {
        // Since we still hold the lock, we can try to recover using the fileChangesRecovery. Again, it will do a little more work than we want, but it will get to the point of retrying the transfers from the SyncServer to cloud storage again. Will it retry the ones that have already been done? No. For successful transfers, the server will have removed those from the outbound files and added entries into the PSFileIndex. For failure, it is possible that we have some inconsistency in the server tables. E.g., a file was transferred, its entry removed from the outbound file changes, but its entry didn't make it into the file index.
        // It would be good to do a server integrity check based on our current expectations of what should be there.

        SMServerAPI.session.transferRecovery { error in

            if (nil == error) {
                // OK. This like a successful return from CommitChanges. We need to wait for the file transfer to complete.
                SMUploadFiles.setMode(.CloudStorageTransferRecovery)
                self.startToPollForOperationFinish()
            }
            else if SMUploadFiles.numberTimesTriedCloudStorageTransferRecovery < SMUploadFiles.maxTimesToTryRecovery {
                
                    // Error, but try again later.
                
                    let duration = self.exponentialFallbackDuration(SMUploadFiles.numberTimesTriedCloudStorageTransferRecovery)

                    TimedCallback.withDuration(duration) {
                        self.cloudStorageTransferRecovery()
                    }
            }
            else {
                Log.error("Failed recovery: Already tried \(SMUploadFiles.numberTimesTriedCloudStorageTransferRecovery) times, and can't get it to work")
                
                // Yikes! What else can we do? Seems like we've given this our best effort in terms of recovery. Kick the error upwards.
                self.sync(.Stop, currentOperation: {
                    self.callSyncServerError(Error.Create("Failed to recover from SyncServer error after \(SMUploadFiles.numberTimesTriedCloudStorageTransferRecovery) recovery attempts"))
                })
            }
        }
    }
}

// MARK: mayHaveCommittedRecovery
// This is an ugly edge case-- falling between the two main recovery cases.

extension SMUploadFiles {
    // Getting to this point, it *seems* like the commitChanges failed. However, it's also possible that something just happened in getting the response back from the server and the commitChanges didn't fail. Need to determine if the commit was successful or not. I.e., if the operation is in progress (or has completed). If the commit was not successful, then we'll do .ChangesRecovery.
    private func mayHaveCommittedRecovery() {
        self.delegate?.syncServerRecovery(.MayHaveCommitted)

        self.sync(.ConditionalStop(stopConditional: {
            return !Network.session().connected()
        }), nextOperation: {
            // This gets executed if we have network access.
            SMUploadFiles.numberTimesTriedMayHaveCommittedRecovery++
            self.mayHaveCommittedRecoveryAux()
        })
    }
    
    private func switchToFileChangesRecovery() {
        SMUploadFiles.setMode(.ChangesRecovery)
        self.fileChangesRecovery()
    }
    
    private func delayAndCheckMayHaveCommitedAgain() {
        if SMUploadFiles.numberTimesTriedMayHaveCommittedRecovery < SMUploadFiles.maxTimesToTryRecovery {
            let duration = self.exponentialFallbackDuration(SMUploadFiles.numberTimesTriedMayHaveCommittedRecovery)

            TimedCallback.withDuration(duration) {
                self.mayHaveCommittedRecovery()
            }
        }
        else {
            self.callSyncServerError(Error.Create("Could not recover from .MayHaveCommittedRecovery state"))
        }
    }
    
    private func mayHaveCommittedRecoveryAux() {
        if (nil == self.serverOperationId) {
            // Need to double check if we actually have an operationId. Server could have generated an operationId, but just failed to get it to us.
            SMServerAPI.session.getOperationId(){ (theServerOperationId, error) in
                if nil == error {
                    if nil == theServerOperationId {
                        self.switchToFileChangesRecovery()
                    }
                    else {
                        self.serverOperationId = theServerOperationId
                        self.continueMayHaveCommittedRecoveryAux()
                    }
                }
                else {
                    Log.error("Error in checkOperationStatus in mayHaveCommittedRecovery: \(error); will retry")
                    self.delayAndCheckMayHaveCommitedAgain()
                }
            }
        }
        else {
            self.continueMayHaveCommittedRecoveryAux()
        }
    }
    
    private func continueMayHaveCommittedRecoveryAux() {
        SMServerAPI.session.checkOperationStatus(serverOperationId: self.serverOperationId!) {operationResult, error in
            if (error != nil) {
                Log.error("Error in checkOperationStatus in mayHaveCommittedRecovery: \(error); will retry")
                self.delayAndCheckMayHaveCommitedAgain()
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
                    if SMUploadFiles.numberTimesTriedMayHaveCommittedRecovery < SMUploadFiles.maxTimesToTryRecovery {
                        let duration = self.exponentialFallbackDuration(SMUploadFiles.numberTimesTriedMayHaveCommittedRecovery)

                        TimedCallback.withDuration(duration) {
                            self.mayHaveCommittedRecovery()
                        }
                    }
                    else {
                        // Assume that we've got the real deal. Commit actually failed.
                        self.switchToFileChangesRecovery()
                    }
                    
                case SMServerConstants.rcOperationStatusCommitFailed:
                    Log.msg("rcOperationStatusCommitFailed")
                    // [1]. We'll do a little more work than necessary with the FileChangesRecovery, but since we've not transferred any files yet this will work to kick off a retry of the commit.
                    self.switchToFileChangesRecovery()
                     
                case SMServerConstants.rcOperationStatusSuccessfulCompletion:
                    Log.msg("rcOperationStatusSuccessfulCompletion")
                    self.wrapUpOperation(operationResult!)
                    
                case SMServerConstants.rcOperationStatusInProgress:
                    // TODO: How do we know if we get here and we have an InProgress status whether (a) InProgress really means in InProgress, or (b) the file transfer has some how failed with didn't record that fact? For now we're just going to assume that InProgress really means InProgress. We could improve this in the future by updating a time/date stamp in the operation status on the server when ever a certain amount of data has been transferred to cloud storage (if somehow that can be done). That way if the time/date stamp is too old, we'd have a good idea that InProgress was wrong and we really had a failure.
                    Log.msg("rcOperationStatusInProgress")
                    self.startToPollForOperationFinish()
                
                case SMServerConstants.rcOperationStatusFailedBeforeTransfer, SMServerConstants.rcOperationStatusFailedDuringTransfer, SMServerConstants.rcOperationStatusFailedAfterTransfer:

                    if 0 == operationResult!.count {
                        // Good. No files could have been transferred.
                        self.switchToFileChangesRecovery()
                    }
                    else {
                        // This is a more difficult case. What do we do?
                        SMUploadFiles.setMode(.CloudStorageTransferRecovery)
                        self.cloudStorageTransferRecovery()
                    }
                    
                default:
                    let msg = "Yikes: Unknown operationStatus: \(operationResult!.status)"
                    Log.error(msg)
                    self.callSyncServerError(Error.Create(msg))
                }
            }
        }
    }
}

