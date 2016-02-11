//
//  SMSync.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 1/23/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import SMCoreLib

// A "Hoare Monitor" to serialize access to SMUploadFiles and SMDownloadFiles so we don't get multiple operations being executed concurrently. This is especially relevant to concurrent operations within uploading or within downloading. However, I am disallowing concurrent operations across downloads and uploads because, on the server, the same directory is used for both uploads and downloads.

// This monitor provides a delegate-callback form of delayed operations. No representation is provided for queue of operations (a stronger form of delay, which would entail being able to persistently store closures).

// Generally executes operations outside of conditional blocks to abide by the philosophy that the least done inside of a synchronized block, the better.

protocol SMSyncDelayedOperationDelegate : class {
    func smSyncDelayedOperation()
}

/*
// http://stackoverflow.com/questions/24127587/how-do-i-declare-an-array-of-weak-references-in-swift

private class WeakDelegate {
  weak var delegate:SMSyncDelayedOperationDelegate?
  init (_ value: SMSyncDelayedOperationDelegate?) {
    self.delegate = value
  }
}
*/

internal class SMSync {
    // An array of weak references to delegates.
    // private var _weakDelegates = [WeakDelegate]()
    
    private static let _session = SMSync()
    
    // true iff another operation needs to be done immediately after the current one is done.
    private static let _doOperationLater = SMPersistItemBool(name: "SMSync.DoOperationLater", initialBoolValue: false, persistType: .UserDefaults)
        
    // To ensure that multiple operations cannot be occuring at the same time.
    private var currentlyOperating = false
    
    internal var isOperating: Bool {
        get {
            return self.currentlyOperating
        }
    }
    
    private init() {
    }
    
    internal static var session:SMSync {
        get {
            return self._session
        }
    }
    
    // We're assuming that there will be only one possible delayed operation.
    internal weak var delayDelegate:SMSyncDelayedOperationDelegate?

    /*
    // Add delegates to be called when a delayed operation is to be executed.
    internal func addDelayedOperation(delegate:SMSyncDelayedOperationDelegate) {
        let weakDelegate = WeakDelegate(delegate)
        self._weakDelegates.append(weakDelegate)
    }
    */
    
    // Assumes it is called from within a Synchronized.block
    private func stopAux() {
        Log.msg("Stopping!")
        self.currentlyOperating = false
        SMSync._doOperationLater.boolValue = false
    }
    
    // Unconditionally start an operation. Must not currently be operating.
    // Formerly: .Do
    internal func start(operation:()->()) {
        Synchronized.block(self) {
            Assert.If(self.currentlyOperating, thenPrintThisString: "Yikes: Currently operating!")
            
            self.currentlyOperating = true
            SMSync._doOperationLater.boolValue = false
        }
        
        operation()
    }
    
    // Conditionally start an operation if: (a) the condition returns true (executed in the conditional block), and (b) if not currently operating.
    internal func startIf(condition:()->Bool, then:(()->())?) {
        var doOperation = false
        
        Synchronized.block(self) {
            if condition() && !self.currentlyOperating {
                doOperation = true
                self.currentlyOperating = true
                SMSync._doOperationLater.boolValue = false
            }
        }
        
        if doOperation {
            then?()
        }
    }
    
    // Start delay delegate operation unless there is an operation currently happening.
    // Formerly: .DoOrDelay
    internal func startOrDelay() {
        var doOperation = false
        
        Synchronized.block(self) {
            if self.currentlyOperating {
                Log.msg("startOrDelay: Currently operating");
                SMSync._doOperationLater.boolValue = true
            }
            else {
                self.currentlyOperating = true
                
                // This shouldn't be necessary, but just to be safe.
                SMSync._doOperationLater.boolValue = false
                
                doOperation = true
            }
        }
        
        if doOperation {
            self.delayDelegate?.smSyncDelayedOperation()
        }
    }
    
    // Start a delayed operation if there is one.
    // Formerly: .DoDelayed
    internal func startDelayed(currentlyOperating currentlyOperatingExpected:Bool?) {
    
        var doDelayed = false
        
        Synchronized.block(self) {
            if currentlyOperatingExpected == nil {
                // Not quite sure what to do here if we *are* currently operating: This will be for the case of the network coming back online in .Normal mode. Just return and cross our fingers.
                if self.currentlyOperating {
                    return
                }
            }
            else {
                Assert.If(currentlyOperatingExpected! != self.currentlyOperating, thenPrintThisString: "Didn't get expected currentlyOperating value")
            }
            
            doDelayed = SMSync._doOperationLater.boolValue
            if doDelayed {
                Assert.If(!self.currentlyOperating, thenPrintThisString: "Yikes: Should have been currently operating")
            } else {
                self.currentlyOperating = false
            }
            
            SMSync._doOperationLater.boolValue = false
        }
        
        if doDelayed {
            self.delayDelegate?.smSyncDelayedOperation()
        }
    }
    
    // Continue operations based on the results of executing the condition. E.g., to stop based on possible network loss. The condition is executed in the synchronized block.
    // Formerly: .ConditionalStop (but negated now).
    internal func continueIf(condition:()->Bool, then:()->()) {
        var doNext = false
        
        Synchronized.block(self) {
            if condition() {
                doNext = true
            }
            else {
                self.stopAux()
            }
        }
        
        if doNext {
            then();
        }
    }
    
    // Unconditionally stop operations. E.g., an API error or failed during multiple recovery attempts.
    // Formerly: .Stop
    internal func stop() {
        Synchronized.block(self) {
            self.stopAux()
        }
    }
}
