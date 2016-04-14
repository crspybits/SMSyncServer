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
    // Indicate the end of a server operation.
    func syncControlFinished(serverLockHeld serverLockHeld:Bool?)
    
    // Indicate an error condition and operation needs to stop.
    func syncControlError()
}

internal class SMSyncControl {
    // Are we currently uploading, downloading, or doing a related operation?
    private var _operating:Bool = false
    
    // Ensuring thread safe operation of the api client interface for uploading and downloading.
    private var lock = NSLock()
    
    // For now, we're assuming that there is no server lock breaking. I.e., once we get the server lock, we have it until we release it. We only obtain the server lock in the process of checking for downloads, and we don't release it until the next() method has no work to do. We're storing this persistently because having or not having the server lock persists across launches of the app.
    private static let haveServerLock = SMPersistItemBool(name: "SMSyncControl.haveServerLock", initialBoolValue: false, persistType: .UserDefaults)
    
    private var serverFileIndex:[SMServerFile]?
    
    private var justUploadedFiles:Bool = false
    
    internal static let session = SMSyncControl()
    internal weak var delegate:SMSyncServerDelegate?
    
    internal var operating : Bool {
        return self._operating
    }

    private init() {
        SMUploadFiles.session.syncControlDelegate = self
    }
    
    /* Call this to perform the next sync operation. This needs to be called when:
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
        if self.lock.tryLock() {
            Assert.If(self._operating, thenPrintThisString: "Yikes: Already operating!")
            self._operating = true
            Log.special("Starting operating!")
            self.delegate?.syncServerModeChange(.Operating)
            self.next()
        }
        // Else: Couldn't get the lock. Another thread must already being doing nextSyncOperation().
    }
    
    private func stopOperating() {
        Assert.If(!self._operating, thenPrintThisString: "Yikes: Not operating!")
        self._operating = false
        
        Log.special("Stopped operating!")
        Log.msg("SMSyncControl.haveServerLock.boolValue: \(SMSyncControl.haveServerLock.boolValue)")

        self.lock.unlock()
        
        // TODO: Fix this: Replace with usage of a mode class.
        self.delegate?.syncServerModeChange(.Idle)
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
                Log.special("SMSyncControl: Process pending uploads")
                Assert.If(!SMSyncControl.haveServerLock.boolValue, thenPrintThisString: "Don't have server lock (uploads)!")
                self.processPendingUploads()
            }
            else if !SMSyncControl.haveServerLock.boolValue {
                Log.special("SMSyncControl: checkServerForDownloads")
                // Only check for server downloads when we don't have the server lock. If we have the server lock this indicates we have already checked for server downloads and don't need to do it again in the span of holding the server lock.
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
            // Network not connected.
            self.stopOperating()
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
        // Every time we process uploads, we need a fresh server file index. This is because the upload process itself changes the server file index.
        
        func doUploads() {
            SMUploadFiles.session.doUploads(self.serverFileIndex!)
            self.serverFileIndex = nil
        }
        
        if nil == self.serverFileIndex {
            Log.msg("getFileIndex within processPendingUploads")
            SMServerAPI.session.getFileIndex() { (fileIndex, gfiResult) in
                if SMTest.If.success(gfiResult.error, context: .GetFileIndex) {
                    self.serverFileIndex = fileIndex
                    doUploads()
                }
                else {
                    // We couldn't get the file index from the server. We have the lock. Recovery will attempt unlocking and try again.
                    self.recovery()
                }
            }
        }
        else {
            doUploads()
        }
    }
    
    // Check the server to see if downloads are needed. We always check for downloads as a first priority (e.g., before doing any uploads) because the server files act as the `truth`. Any device managing to get an upload or upload-deletion to the server will be taken to have established the working current value (`truth`) of the files. If a device has modified a file (including deletion) and hasn't yet uploaded it, it has clearly come later to the game and its changes should receive lower priority. HOWEVER, conflict management will make it possible that after the download, the devices modified file can subsequently replace the server update.
    // Assumes the threading lock is held. Assumes that there are no pending downloads and no pending uploads. Assumes we have no lock on the server.
    // The result of calling this method, if it succeeds, is to hold the server lock, and to change download and conflict queues in SMQueues.
    private func checkServerForDownloads() {
        SMServerAPI.session.lock() { lockResult in
            if SMTest.If.success(lockResult.error, context: .Lock) {
            
                SMSyncControl.haveServerLock.boolValue = true
                
                Log.msg("getFileIndex within checkServerForDownloads")
                SMServerAPI.session.getFileIndex() { (fileIndex, gfiResult) in
                    if SMTest.If.success(gfiResult.error, context: .GetFileIndex) {
                        self.serverFileIndex = fileIndex
                        SMQueues.current().checkForDownloads(fromServerFileIndex: fileIndex!)
                        self.next()
                    }
                    else {
                        // We couldn't get the file index from the server. We have the lock. Recovery will attempt unlocking and try again.
                        self.recovery()
                    }
                }
            }
            else if lockResult.returnCode == SMServerConstants.rcLockAlreadyHeld {
                Log.error("Lock already held")
                // We're calling the "NoFilesToDownload" delegate callback. In some sense this is expected, or normal operation, and we haven't been able to check for downloads (due to a lock), so the check for downloads will be done again later when, hopefully, a lock will not be held. However, for debugging purposes, we effectively have no files to download, so report that back.
                self.stopOperating()
                self.delegate?.syncServerEventOccurred(.NoFilesToDownload)
            }
            else {
                // No need to do recovery since we just started. HOWEVER, it is also possible that the lock is held at this point, but we just failed on getting the return code from the server. Our recovery is going to consist of making certain we don't have the lock, and trying this all over again.
                Log.error("Failed on obtaining lock: \(lockResult.error)")
                self.recovery()
            }
        }
    }
    
    // Make sure we don't have the lock and retry our server check. We'll limit the number of times we do this so we don't get in an infinite loop.
    private func recovery() {
        Assert.badMojo(alwaysPrintThisString: "TO BE IMPLEMENTED!")
        
        SMServerAPI.session.unlock() { unlockResult in
            if SMTest.If.success(unlockResult.error, context: .Unlock) {
                SMSyncControl.haveServerLock.boolValue = false
            }
            else {
                Log.error("Failed on unlock: \(unlockResult.error)")
                self.recovery()
            }
        }
    }
    
    // Try a fixed number of times to release the server lock. 
    // TODO: We'll limit the number of times we do this so we don't get in an infinite loop.
    private func releaseServerLock() {
        SMServerAPI.session.unlock() { unlockResult in
            if SMTest.If.success(unlockResult.error, context: .Unlock) {
                Log.msg("Have released lock!")
                SMSyncControl.haveServerLock.boolValue = false
                self.stopOperating()
            }
            else {
                Log.error("Failed on unlock: \(unlockResult.error)")
                self.recovery()
            }
        }
    }
}

extension SMSyncControl : SMSyncControlDelegate {
    // Indicate the end of a server operation.
    func syncControlFinished(serverLockHeld serverLockHeld:Bool?) {
        // If the server lock has been released, we'll set SMSyncControl.haveServerLock.boolValue to false, and when we call .next(), this will again get the lock and check for downloads. 
        // This will result in overchecking for downloads-- e.g., when an upload has completed, the server lock will not be held, and we'll check again for downloads. I could tweak this to optimize this behavior, but it doesn't seem bad for SMSyncControl to always end on a check for downloads. And this mechanism is relatively simple.
        if serverLockHeld != nil {
            SMSyncControl.haveServerLock.boolValue = serverLockHeld!
        }
        self.next()
    }
    
    // Indicate an error condition and operation needs to stop.
    func syncControlError() {
        Assert.badMojo(alwaysPrintThisString: "Not yet handling error!")
        self.stopOperating()
    }
}
