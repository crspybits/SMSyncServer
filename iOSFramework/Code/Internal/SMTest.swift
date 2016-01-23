//
//  SMTest.swift
//  NetDb
//
//  Created by Christopher Prince on 12/21/15.
//  Copyright © 2015 Spastic Muffin, LLC. All rights reserved.
//

// Enabling failure testing.

// Context for the failure test.
public enum SMTestContext: String {
    case Lock
    case GetFileIndex
    case UploadFiles
    case CommitChanges
}

import Foundation

public class SMTest {
    // Singleton class. Usually named "session", but sometimes it just reads better to have it named "If".
    public static let If = SMTest()
    // In other situations, this is better.
    public static let session = If
    
    private var clientFailureTest = [SMTestContext:Bool]()
    private var _serverDebugTest:Int?
    
    private var _crash:Bool = false
    private var _willCrash:Bool?
    
    private init() {
    }

    public var serverDebugTest:Int? {
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
        
    // These are for injecting client/app side tests.
    public func doClientFailureTest(context:SMTestContext) {
        self.clientFailureTest[context] = true
    }
    
    // Crash the app.
    public func crash() {
        self._crash = self._willCrash!
    }
    
    public func success(error:NSError?, context:SMTestContext) -> Bool {
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
