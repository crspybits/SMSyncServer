//
//  SMTest.swift
//  NetDb
//
//  Created by Christopher Prince on 12/21/15.
//  Copyright © 2015 Spastic Muffin, LLC. All rights reserved.
//

// Enabling failure testing.

// Context for the failure test.
internal enum SMTestContext: String {
    case Lock
    case Unlock
    case GetFileIndex
    case UploadFiles
    case OutboundTransfer
    case SetupInboundTransfer
    case InboundTransfer
    case DownloadFiles
    case CheckOperationStatus
    case RemoveOperationId
}

import Foundation
import SMCoreLib

internal class SMTest {
    // Singleton class. Usually named "session", but sometimes it just reads better to have it named "If".
    internal static let If = SMTest()
    // In other situations, this is better.
    internal static let session = If
    
    internal var clientFailureTest = [SMTestContext:Bool]()
    private var _serverDebugTest:Int?
    
    private var _crash:Bool = false
    private var _willCrash:Bool?
    
    private init() {
    }

    internal var serverDebugTest:Int? {
        get {
#if DEBUG
            if self._serverDebugTest != nil {
                return self._serverDebugTest
            }
#endif
            return nil
        }
        
        set {
            self._serverDebugTest = newValue
        }
    }
        
    // These are for injecting client/app side tests. They fail once, and then reset back to non-failure operation.
    internal func doClientFailureTest(context:SMTestContext) {
        self.clientFailureTest[context] = true
    }
    
    // Crash the app.
    internal func crash() {
        Log.warning("Just about to crash...")
        self._crash = self._willCrash!
    }
    
    internal func success(error:NSError?, context:SMTestContext) -> Bool {
#if DEBUG
        if let doFailureTest = self.clientFailureTest[context] {
            if doFailureTest {
                // Just a one-time test.
                self.clientFailureTest[context] = false
                
                // force failure. I.e., no success == failure.
                return false
            }
        }    
#endif
        return nil == error;
    }
}
