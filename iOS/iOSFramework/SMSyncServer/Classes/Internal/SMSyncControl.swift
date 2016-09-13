//
//  SMSyncControl.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 4/7/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

// Deals with controlling when uploads are carried out and when downloads are carried out. Responsible for local thread safety and server locking. (Sometimes server locks are automatically released, so not always responsible for server unlocking).

import Foundation
import SMCoreLib

internal protocol SMSyncControlDelegate : class {
    // Indicate the end of a upload or download operations.
    func syncControlUploadsFinished()
    func syncControlDownloadsFinished()
    
    // On error conditions, operation needs to stop.
    func syncControlModeChange(newMode:SMSyncServerMode)
}

internal class SMSyncControl {
    // Persisting this variable because we need to be know what mode we are operating in even if the app is restarted or crashes.
    private static let _mode = SMPersistItemData(name: "SMSyncControl.Mode", initialDataValue: NSKeyedArchiver.archivedDataWithRootObject(SMSyncServerModeWrapper(withMode: .Idle)), persistType: .UserDefaults)
    
    internal var mode:SMSyncServerMode {
        get {
            let syncServerMode = NSKeyedUnarchiver.unarchiveObjectWithData(SMSyncControl._mode.dataValue) as! SMSyncServerModeWrapper
            let result = syncServerMode.mode
            Log.msg("mode.get: \(result)")
            return result
        }
        
        set {
            Log.msg("mode.set: \(newValue)")
            SMSyncControl._mode.dataValue = NSKeyedArchiver.archivedDataWithRootObject(SMSyncServerModeWrapper(withMode: newValue))
        }
    }
    
    // Are we currently uploading, downloading, or doing a related operation? Note that this is somewhat redundant with the .Idle vs. .Synchronizing mode, but it makes sense to make this a non-persistent member variable to reflect the locked vs. unlocked state of the the following lock.
    private var _operating:Bool = false
    
    // Ensuring thread safe operation of the api client interface for uploading and downloading.
    private var lock = NSLock()
    
    // Dealing with a race condition between starting a next operation and ending the current operation.
    private let nextOperationLock = NSLock()
    
    private var serverFileIndex:[SMServerFile]?
    
    // Have we fetched the server file index since this launch of the app and having the server lock?
    private var checkedForServerFileIndex = false
    
    private let MAX_NUMBER_ATTEMPTS = 3
    private var numberGetFileIndexAttempts = 0
    private var numberGetFileIndexForUploadAttempts = 0
    private var numberResetAttempts = 0
    
    private func resetAttempts() {
        self.numberGetFileIndexAttempts = 0
        self.numberGetFileIndexForUploadAttempts = 0
        self.numberResetAttempts = 0
    }

    internal static let session = SMSyncControl()
    internal weak var delegate:SMSyncServerDelegate?

    private init() {
        SMUploadFiles.session.syncControlDelegate = self
        SMDownloadFiles.session.syncControlDelegate = self
    }
    
    // a.k.a, startOperating()
    private func tryLock() -> Bool {
        var result:Bool!
        
        // Having an issue with locking/unlocking self.lock from different threads.
        NSThread.runSyncOnMainThread() {
            result = self.lock.tryLock()
            if result! {
                Assert.If(self._operating, thenPrintThisString: "Yikes: Already operating!")
                self._operating = true
            }
        }
        
        return result
    }
    
    // a.k.a, unlock
    private func stopOperating() {
        Assert.If(!self._operating, thenPrintThisString: "Not already operating!")
        self._operating = false
        NSThread.runSyncOnMainThread() {
            self.lock.unlock()
        }
        
        Log.special("Stopped operating!")

        // Callback for .Idle mode change is after the unlock (and now, after this method call) to let the idle callback acquire the lock if needed.
    }
    
    /* Call this to try to perform the next sync operation. If the thread lock can be obtained, this will perform a next sync operation if there is one. Otherwise, will just return.
    
        This needs to be called when:
        A) the app starts
        B) the network comes back online
        C) we get a WebSocket request from the server to do so.

    The priority of the sync operations are:
        TODO: Recovery must take first priority.
     
        1) If pending downloads (assumes we have a server lock), do those.
            Pending downloads include download-conflicts (which are given first priority within downloads), download-deletions, and plain downloads of files.
        2) If pending uploads (also assumes we have a server lock), do those.
            Pending uploads include upload-deletions and plain uploads of files.
            While the ordering of this pending uploads check appears to be higher priority than than the check for downloads in 4), the only way we actually achieve pending uploads is in 5).
        3) Check for downloads (assumes we don't have a lock). This check can result in downloads, download-deletions, and download-conflicts, so we need to go back to 1).
        4) If there are committed uploads, assign a queue of those as pending uploads, go back to 3) (requires a lock created during checking for downloads).
        
        The completion, if given, is called: a) just before returning on error or not getting lock, or b) just after getting the lock.
    */
    internal func nextSyncOperation(completion:(()->())?=nil) {
        Log.msg("nextSyncOperation: \(self.mode)")
      
        switch self.mode {
        case .InternalError, .NonRecoverableError, .ResettingFromError:
            // Don't call self.syncControlModeChange because that will cause a call to stopOperating(), which will fail. Just report this above as an error.
            NSThread.runSyncOnMainThread() {
                self.delegate?.syncServerModeChange(self.mode)
            }
            completion?()
            return
        
        // If we're in a .NetworkNotConnected mode, calling nextSyncOperation() should be considered a .Recovery step. i.e., because presumably the network is now connected.
        case .NetworkNotConnected:
            NSThread.runSyncOnMainThread() {
                self.delegate?.syncServerEventOccurred(.Recovery)
            }
            
        // If we're in a .Synchronizing mode, this is also a .Recovery step. This is because they only way we should get to this point and be in a .Synchronizing mode is if the app terminated and we were in a .Synchronizing mode.
        case .Synchronizing:
            if !self._operating {
                NSThread.runSyncOnMainThread() {
                    self.delegate?.syncServerEventOccurred(.Recovery)
                }
            }
            
        case .Idle:
            break
        }
        
        if self.tryLock() {
            completion?()
            self.syncControlModeChange(.Synchronizing)
            Log.special("Starting operating!")
            self.resetAttempts()
            self.next()
        }
        else {
            completion?()
            // Else: Couldn't get the lock. Another thread must already being doing nextSyncOperation(). This is not an error.
            NSThread.runSyncOnMainThread() {
                self.delegate?.syncServerEventOccurred(.LockAlreadyHeld)
            }
            Log.special("nextSyncOperation: Couldn't get the lock!")
        }
    }
    
    internal func lockAndNextSyncOperation(upload:()->()) {
        self.nextOperationLock.lock()
        upload()
        // Shouldn't hold the nextOperationLock for very long-- the nextSyncOperation callback will release it quickly.
        self.nextSyncOperation() {
            self.nextOperationLock.unlock()
        }
    }
    
    private func doNextUploadOrStop() {
        self.nextOperationLock.lock()
        if nil == SMQueues.current().committedUploads {
            Log.msg("No uploads, stop operating")
            self.stopOperating()
            // Unlock before calling .Idle callback so we don't get into deadlock issues. E.g., .Idle callback could cause lockAndNextSyncOperation to be called.
            self.nextOperationLock.unlock()
            self.syncControlModeChange(.Idle)
        }
        else {
            self.nextOperationLock.unlock()

            // Will necessarily do another check for downloads, but once we get the lock, we'll also process the commited uploads that are waiting.
            self.next()
        }
    }

    private func localCleanup() {
        // Using nextOperationLock so that no one races in, does a client commit, and the commit remains enqueued but doesn't actually do any sync operations. Either the commit will get thrown away in the cleanup, or it will operate after this cleanup/stop sequence occurs.
        self.nextOperationLock.lock()

        SMQueues.current().flush()

        // Since we just did the localCleanup(), which flushed the SMQueues, there is no point in calling doNextUploadOrStop() because there will not be any uploads or other queued operations.
        
        self.stopOperating()
        self.nextOperationLock.unlock()
        
        self.syncControlModeChange(.Idle)
    }

    // allowDebugReset is for DEBUG builds and for testing .InternalError and .NonRecoverableError reset.
    internal func resetFromError(allowDebugReset allowDebugReset:Bool=false, resetType: SMSyncServer.ErrorResetMask=[.All], completion:((error:NSError?)->())?=nil) {
    
        Assert.If(resetType.isEmpty, thenPrintThisString: "Yikes: Empty reset!")
    
        let orignalErrorMode = self.mode
        
        #if !DEBUG
            Assert.If(allowDebugReset == true, thenPrintThisString: "Yikes: Attempted to do debug reset in non-debug build!")
        #endif
    
        switch (self.mode) {
        case .Idle, .Synchronizing, .NetworkNotConnected, .ResettingFromError:
            if allowDebugReset {
                break
            }
            let error = Error.Create("Not in an error mode: \(self.mode)")
            Log.msg("\(error)")
            completion?(error: error)
            return
            
        case .InternalError, .NonRecoverableError:
            break
        }
        
        // Should not be operating or have the lock -- because we're in an error mode.
        
        if !self.tryLock() {
            Assert.badMojo(alwaysPrintThisString: "Could not get the lock!!")
        }
        
        // Now: We are operating, and we have the lock.

        self.syncControlModeChange(.ResettingFromError)
        
        if resetType.contains(.Local) && !resetType.contains(.Server) {
            self.localCleanup()
            completion?(error: nil)
            return
        }
        
        self.resetFromErrorAux(resetType:resetType, originalErrorMode:orignalErrorMode, completion: completion)
    }

    
    private func resetFromErrorAux(resetType resetType: SMSyncServer.ErrorResetMask, originalErrorMode:SMSyncServerMode, completion:((error:NSError?)->())?=nil) {
        
        SMServerAPI.session.cleanup() { apiResult in
            if nil == apiResult.error {
                Log.msg("Succeeded on cleanup!")
                
                if resetType.contains(.Local) {
                    self.localCleanup()
                }
                else {
                    self.syncControlModeChange(.Synchronizing)
                    self.doNextUploadOrStop()
                }
                
                Log.msg("About to call completion: \(completion)")

                completion?(error: nil)
            }
            else {
                // Not checking Network.session().connected() because SMServerNetworking will check that and we can retry here.
                self.retry(&self.numberResetAttempts, errorSpecifics: "Failed on server cleanup", success: {
                    self.resetFromErrorAux(resetType:resetType, originalErrorMode: originalErrorMode, completion: completion)
                }, failure: {
                    // Failed on resetting.
                    self.syncControlModeChange(originalErrorMode)
                    completion?(error: apiResult.error)
                })
            }
        }
    }
    
    // Must have thread lock before calling. Must do thread unlock upon returning-- that return and thread unlock may be delayed due to an asynchronous operation.
    private func next() {
        Assert.If(!self._operating, thenPrintThisString: "Yikes: Not operating!")

        if Network.session().connected() {
            // Check for downloads that we have already enqueued.
            if SMQueues.current().beingDownloaded != nil  {
                if case .SomeOperationsToDo = SMDownloadFiles.session.checkWhatOperationsNeed() {
                    Log.special("SMSyncControl: Process pending downloads")
                    SMDownloadFiles.session.doDownloadOperations()
                }
            }
            else if SMQueues.current().beingUploaded != nil && SMQueues.current().beingUploaded!.operations!.count > 0 {
                // Uploads are second priority. See [1] also.
                Log.special("SMSyncControl: Process pending uploads")

                let syncOperationResult = SMUploadFiles.session.checkWhatOperationsNeed()
                
                var getServerFileIndex = false
                var error = false
                
                switch syncOperationResult {
                case .Operation(.Some, let operationNeeds):
                    switch operationNeeds {
                    case .None:
                        Assert.badMojo(alwaysPrintThisString: "Should not get here")
                        
                    case .Some(.ServerFileIndex):
                        getServerFileIndex = true
                        
                    case .Some(.Nothing):
                        break
                    }
                
                case .Operation(.None, _):
                    Assert.badMojo(alwaysPrintThisString: "Should not get here")
                
                case .Error:
                    error = true
                }
                
                if !error {
                    self.processPendingUploads(getFileIndex: getServerFileIndex)
                }
            }
            else if !self.checkedForServerFileIndex {
                Log.special("SMSyncControl: checkServerForDownloads")
                // No pending uploads or pending downloads. See if the server has any new files that need downloading.
                self.checkServerForDownloads()
            }
            else if SMQueues.current().committedUploads != nil {
                Log.special("SMSyncControl: moveOneCommittedQueueToBeingUploaded")
                // If there are committed uploads, make a queue of them pending uploads.
                SMQueues.current().moveOneCommittedQueueToBeingUploaded()
                // Use recursion to jump back and processPendingUploads.
                self.next()
            }
            else {
                // No work to do!
                Log.special("SMSyncControl: No work to do!")
                
                self.checkedForServerFileIndex = false
            
                // Not calling stopOperating() directly to deal with race condition between committing uploads and stopping.
                self.doNextUploadOrStop()
            }
        }
        else {
            self.syncControlModeChange(.NetworkNotConnected)
        }
    }
    
    private func processPendingUploads(getFileIndex getFileIndex:Bool=false) {
        // With some upload operations, we need a fresh server file index. This is because the upload process itself changes the server file index on the server. (I could simulate this server file index change process locally, but since upload is expensive and getting the file index is cheap, it doesn't seem worthwhile).
        
        func doUploads() {
            SMUploadFiles.session.doUploadOperations(self.serverFileIndex)
            self.serverFileIndex = nil
        }
        
        if !getFileIndex {
            doUploads()
            return
        }
        
        if nil == self.serverFileIndex {
            Log.msg("getFileIndex within processPendingUploads")
            
            SMServerAPI.session.getFileIndex() { (fileIndex, fileIndexVersion, gfiResult) in
                if SMTest.If.success(gfiResult.error, context: .GetFileIndex) {
                    self.serverFileIndex = fileIndex
                    self.numberGetFileIndexForUploadAttempts = 0
                    doUploads()
                }
                else {
                    self.retry(&self.numberGetFileIndexForUploadAttempts, errorSpecifics: "attempting to get the file index for uploads", success: {
                        self.next()
                    })
                }
            }
        }
        else {
            doUploads()
        }
    }
    
    // Check the server to see if downloads are needed. We always check for downloads as a first priority (e.g., before doing any uploads) because the server files act as the `truth`. Any device managing to get an upload or upload-deletion to the server will be taken to have established the working current value (`truth`) of the files. If a device has modified a file (including deletion) and hasn't yet uploaded it, it has clearly come later to the game and its changes should receive lower priority. HOWEVER, conflict management will make it possible that after the download, the devices modified file can subsequently replace the server update.
    // Assumes the threading lock is held. Assumes that there are no pending downloads and no pending uploads. The server lock typically won't be held, but could already be held in the case of retrying to get the server file index (on an error with that). (It is not an error to try to get the server lock if we alread hold it.)
    // The result of calling this method, if it succeeds, is to hold the server lock, and to change download and conflict queues in SMQueues.
    private func checkServerForDownloads() {

        Log.msg("getFileIndex within checkServerForDownloads")
        SMServerAPI.session.getFileIndex() { (fileIndex, fileIndexVersion, gfiResult) in
            if SMTest.If.success(gfiResult.error, context: .GetFileIndex) {
            
                self.serverFileIndex = fileIndex
                self.checkedForServerFileIndex = true
                self.numberGetFileIndexAttempts = 0
                
                SMSyncControl.checkForDownloads(fromServerFileIndex: fileIndex!)
                if nil == SMQueues.current().beingDownloaded {
                    NSThread.runSyncOnMainThread() {
                        self.delegate?.syncServerEventOccurred(.DownloadsFinished)
                    }
                }
                
                self.next()
            }
            else {
                // We couldn't get the file index from the server. We have the lock.
                self.retry(&self.numberGetFileIndexAttempts, errorSpecifics: "attempting to get the file index", success: {
                    self.next()
                })
            }
        }
    }

    // If you give a failure handler, it should call syncControlModeChange.
    private func retry(inout attempts:Int, errorSpecifics:String, success:()->(), failure:(()->())?=nil) {
        Log.special("retry: for \(errorSpecifics)")
        
        // Retry up to a max number of times, then fail.
        if attempts < self.MAX_NUMBER_ATTEMPTS {
            attempts += 1
            
            SMServerNetworking.exponentialFallback(forAttempt: attempts) {
                NSThread.runSyncOnMainThread() {
                    self.delegate?.syncServerEventOccurred(.Recovery)
                }
                success()
            }
        }
        else {
            if failure == nil {
                self.syncControlModeChange(.InternalError(Error.Create("Failed after \(self.MAX_NUMBER_ATTEMPTS) retries on \(errorSpecifics)")))
            }
            else {
                failure!()
            }
        }
    }

    /* Compare our local file meta data against the server files to see which indicate download, download-deletion, and download-conflicts.
    The result of this call is stored in .beingDownloaded in the current SMQueues object.
    beingDownloaded must be nil before this call.
    */
    private class func checkForDownloads(fromServerFileIndex serverFileIndex:[SMServerFile]) {
    
        Assert.If(SMQueues.current().beingDownloaded != nil, thenPrintThisString: "There are already files being downloaded")
        
        var fileDownloads = 0
        
        // This is for downloads, download-deletions
        let downloadOperations = NSMutableOrderedSet()
                
        for serverFile in serverFileIndex {
            let localFile = SMLocalFile.fetchObjectWithUUID(serverFile.uuid!.UUIDString)
            
            if serverFile.deleted! {
                // File was deleted on the server.
                if localFile != nil  {
                    // Record this as a file to be deleted locally, only if we haven't already done so.
                    
                    let localFileNotDeleted = !localFile!.deletedOnServer

                    if localFileNotDeleted {
                        // A pending upload-deletion is not a conflict.
                        if localFile!.pendingUploadDeletion() {
                            // We were trying to upload a deletion to the server, but someone else got there first.
                            // We can remove the pending upload deletion.
                            let deletion = localFile!.pendingSMUploadDeletion()
                            
                            let queue = deletion!.queue
                            deletion!.removeObject()
                            
                            // Remove the containing queue if no more upload operations after this.
                            queue!.removeIfNoFileOperations()
                            
                            // And we can mark the file as deleted on server.
                            localFile!.deletedOnServer = true
                            CoreData.sessionNamed(SMCoreData.name).saveContext()
                            // And we don't have to process this as a SMDownloadDeletion object because the client app already knows about the deletion.
                        }
                        else {
                            let downloadDeletion = SMDownloadDeletion.newObject( withLocalFileMetaData: localFile!)
                            downloadOperations.addObject(downloadDeletion)
                            
                            // The caller will be responsible for updating local meta data for this file, to mark it as deleted. The caller should do it at a time that will preserve the atomic nature of the operation.
                            // Has the download-deletion file been modified (not deleted) locally?
                            if localFile!.pendingUpload() {
                                downloadDeletion.conflictType = .FileUpload
                            }
                        }
                    }
                    // Else: The local meta data indicates we've already know about the server deletion. No need to locally delete again.
                }
                /* Else:
                    Don't have meta data for this file locally. File must have been uploaded, and deleted by other device(s) all without syncing with this device. I don't see any point in creating local meta data for the file given that I'd just need to mark it as deleted.
                */
            }
            else {
                // File not deleted on the server, i.e., this is a download not a download-deletion case.
                
                Assert.If(nil == serverFile.version, thenPrintThisString: "No version for server file.")
                
                if localFile == nil {
                    // Server file doesn't yet exist on the app/client. I'm going to create the new SMLocalFile meta data object now so that we have access to this meta data when we need to give the callback to the client.
                    
                    // SMServerFile must include mimeType, remoteFileName, version and appFileType if on server.
                    Assert.If(nil == serverFile.mimeType, thenPrintThisString: "mimeType not given by server!")
                    Assert.If(nil == serverFile.remoteFileName, thenPrintThisString: "remoteFileName not given by server!")
            
                    let localFile = SMLocalFile.newObject() as! SMLocalFile
                    localFile.syncState = .InitialDownload
                    localFile.uuid = serverFile.uuid.UUIDString
                    localFile.mimeType = serverFile.mimeType
                    localFile.appMetaData = serverFile.appMetaData
                    localFile.remoteFileName = serverFile.remoteFileName
                    
                    // .localVersion must remain nil until just before callback that download is finished (syncServerDownloadsComplete)
                    localFile.localVersion = nil
                
                    let downloadFile = SMDownloadFile.newObject(fromServerFile: serverFile, andLocalFileMetaData: localFile)
                    downloadFile.serverVersion = serverFile.version
                    downloadOperations.addObject(downloadFile)
                    fileDownloads += 1
                }
                else {
                    let serverVersion = serverFile.version
                    let localVersion = localFile!.localVersion!.integerValue
                    
                    if serverVersion == localVersion {
                        // No update. No need to download. [1].
                        continue
                    }
                    else if serverVersion > localVersion {
                        // Server file is updated version of that on app/client.
                        // Server version is greater. Need to download.
                        let downloadFile = SMDownloadFile.newObject(fromServerFile: serverFile, andLocalFileMetaData: localFile!)
                        downloadFile.serverVersion = serverVersion
                        downloadOperations.addObject(downloadFile)
                        fileDownloads += 1
                        
                        // Handle conflict cases: These are only relevant when downloading an updated version from the server. If the server version hasn't changed (as in [1] above), and we have a pending upload or pending upload-deletion, then this does not indicate a conflict.
                        var downloadConflict:SMSyncServerConflict.ClientOperation?
                        
                        // I'm prioritizing deletion as a conflict. Because deletion is final, and a choice has to be made if we only issue a single conflict per file per round of downloads.
                        if localFile!.pendingUploadDeletion() {
                            downloadConflict = .UploadDeletion
                        }
                        else if localFile!.pendingUpload() {
                            downloadConflict = .FileUpload
                        }
                        
                        if downloadConflict != nil {
                            downloadFile.conflictType = downloadConflict
                        }
                    } else { // serverVersion < localVersion
                        Assert.badMojo(alwaysPrintThisString: "This should never happen.")
                    }
                }
            }
        } // End-for
        
        if downloadOperations.count > 0 {
            let downloadStartup = SMDownloadStartup.newObject() as! SMDownloadStartup
            
            if fileDownloads == 0 {
                // We don't have any files to downloads: Only download-deletions and possibly download-conflicts.
                downloadStartup.startupStage = .NoFileDownloads
            }
            
            downloadOperations.addObject(downloadStartup)
            
            SMQueues.current().beingDownloaded = downloadOperations
        }
        else {
            SMQueues.current().beingDownloaded = nil
        }
        
        CoreData.sessionNamed(SMCoreData.name).saveContext()
    }
}

extension SMSyncControl : SMSyncControlDelegate {
    // After uploads are complete, there will be no server lock held (because the server lock automatically gets released by the server after outbound transfers finish), *and* we'll be at the bottom priority of our list in [1].
    func syncControlUploadsFinished() {
        
        // Because we don't have the lock and we're at the bottom priority, and we just released the lock, don't call self.next(). That would just cause another server check for downloads, and since we just released the lock, and had checked for downloads initially, there can't be downloads straight away.
        // HOWEVER, there may be additional uploads to process. I.e., there may be other committed uploads.
        
        self.doNextUploadOrStop()
    }
    
    // Again, after downloads are complete, there will be no server lock held. But, we'll not be at the bottom of the priority list.
    func syncControlDownloadsFinished() {
        Log.msg("syncControlDownloadsFinished")

        self.delegate?.syncServerEventOccurred(.DownloadsFinished)
        
        // Since we're not at the bottom of the priority list, call next(). This will (unfortunately) result in another check for downloads. We're trying to get to the point where we can check for uploads, however.
        self.next()
    }
    
    func syncControlModeChange(newMode:SMSyncServerMode) {
        self.mode = newMode
        Log.special("newMode: \(self.mode)")
        
        switch newMode {
        case .Idle:
            // Don't call stopOperating(). It will have already been called.
            break
            
        case .Synchronizing, .ResettingFromError:
            // Don't call stopOperating()-- we're most certainly operating!
            break
            
        case .NetworkNotConnected:
            self.stopOperating()
        
        case .NonRecoverableError, .InternalError:
            // Ditto.
            self.stopOperating()
        }
        
        NSThread.runSyncOnMainThread() {
            self.delegate?.syncServerModeChange(newMode)
        }
    }
}
