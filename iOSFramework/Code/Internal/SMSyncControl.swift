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

    // For now, we're assuming that there is no server lock breaking. I.e., once we get the server lock, we have it until we release it. We only obtain the server lock in the process of checking for downloads, and we don't release it until the next() method has no work to do. We're storing this persistently because having or not having the server lock persists across launches of the app.
    private static let haveServerLock = SMPersistItemBool(name: "SMSyncControl.haveServerLock", initialBoolValue: false, persistType: .UserDefaults)
    
    private var serverFileIndex:[SMServerFile]?
    
    // Have we fetched the server file index since this launch of the app and having the server lock?
    private var checkedForServerFileIndex = false
    
    private let MAX_NUMBER_ATTEMPTS = 3
    private var numberLockAttempts = 0
    private var numberGetFileIndexAttempts = 0
    private var numberGetFileIndexForUploadAttempts = 0
    private var numberUnlockAttempts = 0
    private var numberCleanupAttempts = 0
    
    private func resetAttempts() {
        self.numberLockAttempts = 0
        self.numberGetFileIndexAttempts = 0
        self.numberGetFileIndexForUploadAttempts = 0
        self.numberUnlockAttempts = 0
        self.numberCleanupAttempts = 0
    }

    internal static let session = SMSyncControl()
    internal weak var delegate:SMSyncServerDelegate?

    private init() {
        SMUploadFiles.session.syncControlDelegate = self
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
    */
    internal func nextSyncOperation() {
        switch self.mode {
        case .ClientAPIError, .InternalError, .NonRecoverableError:
            // Don't call self.syncControlModeChange because that will cause a call to stopOperating(), which will fail. Just report this above as an error.
            self.delegate?.syncServerModeChange(self.mode)
            return
        
        // If we're in a .NetworkNotConnected mode, calling nextSyncOperation() should be considered a .Recovery step. i.e., because presumably the network is now connected.
        case .NetworkNotConnected:
            self.delegate?.syncServerEventOccurred(.Recovery)
            
        // If we're in a .Synchronizing mode, this is also a .Recovery step. This is because they only way we should get to this point and be in a .Synchronizing mode is if the app terminated and we were in a .Synchronizing mode.
        case .Synchronizing:
            if !self._operating {
                self.delegate?.syncServerEventOccurred(.Recovery)
            }
            
        case .Idle:
            break
        }
        
        if self.lock.tryLock() {
            Assert.If(self._operating, thenPrintThisString: "Yikes: Already operating!")
            self._operating = true
            self.syncControlModeChange(.Synchronizing)
            Log.special("Starting operating!")
            self.resetAttempts()
            self.next()
        }
        else {
            // Else: Couldn't get the lock. Another thread must already being doing nextSyncOperation(). This is not an error.
            Log.special("nextSyncOperation: Couldn't get the lock!")
        }
    }
    
    internal func lockAndNextSyncOperation(upload:()->()) {
        self.nextOperationLock.lock()
        upload()
        self.nextSyncOperation()
        self.nextOperationLock.unlock()
    }
    
    private func doNextUploadOrStop() {
        self.nextOperationLock.lock()
        
        if nil == SMQueues.current().committedUploads {
            // No uploads, stop operating; will set mode to .Idle
            self.stopOperating()
            self.nextOperationLock.unlock()
        }
        else {
            self.nextOperationLock.unlock()

            // Will necessarily do another check for downloads, but once we get the lock, we'll also process the commited uploads that are waiting.
            self.next()
        }
    }
    
    private func stopOperating(andSetModeToIdle setModeToIdle:Bool=true) {
        Assert.If(!self._operating, thenPrintThisString: "Yikes: Not operating!")
        
        self._operating = false
        if setModeToIdle {
            self.syncControlModeChange(.Idle)
        }
        
        Log.special("Stopped operating!")
        Log.msg("SMSyncControl.haveServerLock.boolValue: \(SMSyncControl.haveServerLock.boolValue)")

        self.lock.unlock()
    }
    
    internal func resetFromError(completion:((error:NSError?)->())?=nil) {
        func localCleanup() {
            SMQueues.current().flush()
            self.numberCleanupAttempts = 0
            self.syncControlModeChange(.Idle)
        }
        
        switch (self.mode) {
        case .Idle, .Synchronizing, .NetworkNotConnected:
            completion?(error: Error.Create("Not in an error mode: \(self.mode)"))
            return
        
        case .ClientAPIError:
            localCleanup()
            completion?(error: nil)
            return
            
        case .InternalError, .NonRecoverableError:
            break
        }
        
        // Should not be operating-- because we're in an error mode. The only time self._operating should be true is when we're in .Synchronizing mode.
        Assert.If(self._operating, thenPrintThisString: "Should not be operating!")
        
        SMServerAPI.session.cleanup() { apiResult in
            if nil == apiResult.error {
                // One result of successfully calling cleanup is that we won't have the server lock any more.
                SMSyncControl.haveServerLock.boolValue = false
                
                localCleanup()
                completion?(error: nil)
            }
            else {
                // Retry up to a max number of times, then fail. Not using self.retry because we don't want to call next() here. Not checking Network.session().connected() because SMServerNetworking will check that and we can retry here.
                
                if self.numberCleanupAttempts < self.MAX_NUMBER_ATTEMPTS {
                    self.numberCleanupAttempts += 1
                    
                    SMServerNetworking.exponentialFallback(forAttempt: self.numberCleanupAttempts) {
                        self.delegate?.syncServerEventOccurred(.Recovery)
                        self.resetFromError(completion)
                    }
                }
                else {
                    completion?(error: apiResult.error)
                }
            }
        }
    }
    
    // Must have thread lock before calling. Must do thread unlock upon returning-- that return and thread unlock may be delayed due to an asynchronous operation.
    private func next() {
        Assert.If(!self._operating, thenPrintThisString: "Yikes: Not operating!")

        if Network.session().connected() {
            Log.msg("SMSyncControl.haveServerLock.boolValue: \(SMSyncControl.haveServerLock.boolValue)")
            
            if SMQueues.current().beingDownloaded != nil  {
                Log.special("SMSyncControl: Process pending downloads")
                Assert.If(!SMSyncControl.haveServerLock.boolValue, thenPrintThisString: "Don't have server lock (downloads)!")
                self.processPendingDownloads()
            }
            else if SMQueues.current().beingUploaded != nil && SMQueues.current().beingUploaded!.operations!.count > 0 {
                // Uploads are really the bottom priority. See [1] also.
                Log.special("SMSyncControl: Process pending uploads")
                Assert.If(!SMSyncControl.haveServerLock.boolValue, thenPrintThisString: "Don't have server lock (uploads)!")
                self.processPendingUploads()
            }
            else if !SMSyncControl.haveServerLock.boolValue
                    || !self.checkedForServerFileIndex {
                Log.special("SMSyncControl: checkServerForDownloads")
                // No pending uploads or pending downloads. See if the server has any new files that need downloading.
                self.checkServerForDownloads()
            }
            else if SMQueues.current().committedUploads != nil {
                Log.special("SMSyncControl: moveOneCommittedQueueToBeingUploaded")
                // If there are committed uploads, make a queue of them pending uploads.
                SMQueues.current().moveOneCommittedQueueToBeingUploaded()
                // Use recursion to process the pending uploads.
                self.next()
            }
            else {
                // No work to do! Need to release the server lock if needed.
                Log.special("SMSyncControl: No work to do!")

                if SMSyncControl.haveServerLock.boolValue {
                    self.releaseServerLock()
                }
            }
        }
        else {
            self.syncControlModeChange(.NetworkNotConnected)
        }
    }
    
    private func processPendingDownloads() {
        Assert.badMojo(alwaysPrintThisString: "TO BE IMPLEMENTED!")
        
        if let conflicts = SMQueues.current().downloadConflicts() {
            Assert.If(!SMSyncControl.haveServerLock.boolValue, thenPrintThisString: "Don't have server lock!")
            self.processPendingConflicts(conflicts)
        }
        
        // Process other download too!!
    }
    
    private func processPendingConflicts(conflicts:[SMDownloadConflict]) {
        Assert.badMojo(alwaysPrintThisString: "TO BE IMPLEMENTED!")
        // Need to call delegate methods, and require user app to resolve each conflict. We will delete each conflict out of core data when we get the response. When that's all done, we need to call next().
    }
    
    private func processPendingUploads() {
        // Every time we process uploads, we need a fresh server file index. This is because the upload process itself changes the server file index on the server. (I could simulate this server file index change process locally, but since upload is expensive and getting the file index is cheap, it doesn't seem worthwhile).
        
        func doUploads() {
            SMUploadFiles.session.doUploadOperations(self.serverFileIndex!)
            self.serverFileIndex = nil
        }
        
        if nil == self.serverFileIndex {
            Log.msg("getFileIndex within processPendingUploads")
            
            SMServerAPI.session.getFileIndex() { (fileIndex, gfiResult) in
                if SMTest.If.success(gfiResult.error, context: .GetFileIndex) {
                    self.serverFileIndex = fileIndex
                    self.numberGetFileIndexForUploadAttempts = 0
                    doUploads()
                }
                else {
                    self.retry(&self.numberGetFileIndexForUploadAttempts, errorSpecifics: "attempting to get the file index for uploads")
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
        SMServerAPI.session.lock() { lockResult in
            if SMTest.If.success(lockResult.error, context: .Lock) {
            
                SMSyncControl.haveServerLock.boolValue = true
                self.numberLockAttempts = 0
                
                Log.msg("getFileIndex within checkServerForDownloads")
                SMServerAPI.session.getFileIndex() { (fileIndex, gfiResult) in
                    if SMTest.If.success(gfiResult.error, context: .GetFileIndex) {
                    
                        self.serverFileIndex = fileIndex
                        self.checkedForServerFileIndex = true
                        self.numberGetFileIndexAttempts = 0
                        
                        SMQueues.current().checkForDownloads(fromServerFileIndex: fileIndex!)
                        self.next()
                    }
                    else {
                        // We couldn't get the file index from the server. We have the lock.
                        self.retry(&self.numberGetFileIndexAttempts, errorSpecifics: "attempting to get the file index")
                    }
                }
            }
            else if lockResult.returnCode == SMServerConstants.rcLockAlreadyHeld {
                // Not really an error.
                Log.special("Lock already held by another userId")
                // We're calling the "NoFilesToDownload" delegate callback. In some sense this is expected, or normal operation, and we haven't been able to check for downloads (due to a lock), so the check for downloads will be done again later when, hopefully, a lock will not be held. However, for debugging purposes, we effectively have no files to download, so report that back.
                self.stopOperating()
                self.delegate?.syncServerEventOccurred(.NoFilesToDownload)
            }
            else {
                // No need to do recovery since we just started. HOWEVER, it is also possible that the lock is actually held at this point, but we just failed on getting the return code from the server.
                // Not going to check for nextwork connection here because next() checks that.
                self.retry(&self.numberLockAttempts, errorSpecifics: "attempting to get lock")
            }
        }
    }
    
    private func retry(inout attempts:Int, errorSpecifics:String) {
        // Retry up to a max number of times, then fail.
        if attempts < self.MAX_NUMBER_ATTEMPTS {
            attempts += 1
            
            SMServerNetworking.exponentialFallback(forAttempt: attempts) {
                self.delegate?.syncServerEventOccurred(.Recovery)
                self.next()
            }
        }
        else {
            self.syncControlModeChange(.InternalError(Error.Create("Failed after \(self.MAX_NUMBER_ATTEMPTS) retries on \(errorSpecifics)")))
        }
    }
    
    private func releaseServerLock() {
        func success() {
            Log.msg("Have released lock!")
            SMSyncControl.haveServerLock.boolValue = false
            self.checkedForServerFileIndex = false
            self.numberUnlockAttempts = 0
            
            // Not calling stopOperating() directly to deal with race condition between committing uploads and stopping.
            self.doNextUploadOrStop()
        }
        
        SMServerAPI.session.unlock() { unlockResult in
            if SMTest.If.success(unlockResult.error, context: .Unlock) {
                success()
            }
            else if unlockResult.returnCode == SMServerConstants.rcLockNotHeld {
                // This situation could arise if the first attempt at unlocking somehow resulted in the return result being not being communicated correctly back to the app. The second time we try to unlock, we don't hold the lock, which is what we want.
                success()
            }
            else {
                self.retry(&self.numberUnlockAttempts, errorSpecifics: "attempting to unlock")
            }
        }
    }
}

extension SMSyncControl : SMSyncControlDelegate {
    // After uploads are complete, there will be no server lock held (because the server lock automatically gets released by the server after outbound transfers finish), *and* we'll be at the bottom priority of our list in [1].
    func syncControlUploadsFinished() {
        SMSyncControl.haveServerLock.boolValue = false
        
        // Because we don't have the lock and we're at the bottom priority, and we just released the lock, don't call self.next(). That would just cause another server check for downloads, and since we just released the lock, and had checked for downloads initially, there can't be downloads straight away.
        // HOWEVER, there may be additional uploads to process. I.e., there may be other committed uploads.
        
        self.doNextUploadOrStop()
    }
    
    // Again, after downloads are complete, there will be no server lock held. But, we'll not be at the bottom of the priority list.
    func syncControlDownloadsFinished() {
        SMSyncControl.haveServerLock.boolValue = false

        // Since we're not at the bottom of the priority list, call next(). This will (unfortunately) result in another check for downloads. We're trying to get to the point where we can check for uploads, however.
        self.next()
    }
    
    func syncControlModeChange(newMode:SMSyncServerMode) {
        self.mode = newMode
        Log.special("newMode: \(self.mode)")
        
        switch newMode {
        case .Idle:
            // Don't call stopOperating(); The .Idle mode is only set from within stopOperating() itself.
            break
            
        case .Synchronizing:
            // Don't call stopOperating()-- we're most certainly operating!
            break
            
        case .NetworkNotConnected:
            // We've set the mode above, and don't want to change it to .Idle. But, we do want to stop operating.
            self.stopOperating(andSetModeToIdle: false)
        
        case .ClientAPIError, .NonRecoverableError, .InternalError:
            // Ditto.
            self.stopOperating(andSetModeToIdle: false)
        }
        
        self.delegate?.syncServerModeChange(newMode)
    }
}
