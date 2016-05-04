
//
//  SMCloudStorageCredentials.swift
//  NetDb
//
//  Created by Christopher Prince on 11/26/15.
//  Copyright © 2015 Christopher Prince. All rights reserved.
//

// Credentials for a user signing into the specific cloud cloud storage types. Subclasses will have details about the cloud systems (e.g., mechanisms for signing a user into Google) because we have to present some specific UI to allow the user to sign in, and authorize us (the app) for use of their account.

import Foundation
import SMCoreLib

/* TODO: Handle this: Got it when I pressed the Sign In button to connect to Google.
2015-11-26 21:09:38.198 NetDb[609/0x16e12f000] [lvl=3] __65-[GGLClearcutLogger sendNextPendingRequestWithCompletionHandler:]_block_invoke_3() Error posting to Clearcut: Error Domain=NSURLErrorDomain Code=-1005 "The network connection was lost." UserInfo={NSUnderlyingError=0x15558de70 {Error Domain=kCFErrorDomainCFNetwork Code=-1005 "(null)" UserInfo={_kCFStreamErrorCodeKey=57, _kCFStreamErrorDomainKey=1}}, NSErrorFailingURLStringKey=https://play.googleapis.com/log, NSErrorFailingURLKey=https://play.googleapis.com/log, _kCFStreamErrorDomainKey=1, _kCFStreamErrorCodeKey=57, NSLocalizedDescription=The network connection was lost.}
*/
public class SMCloudStorageCredentials : NSObject, SMCloudStorageUserDelegate {
    public static var session : SMCloudStorageCredentials! = nil
    
    /*
    public override init() {
    }
    */
    
    // Use this from openURL in the AppDelegate.
    public func handleURL(url: NSURL, sourceApplication: String?, annotation: AnyObject) -> Bool {
        return false
    }
    
    // Attempts to sign in, not using a UI and not interacting with the user.
    // Use the signInCompletion handler to determine if silentSignIn was successful.
    public func silentSignIn() {
    }
    
    public func makeSignInController() -> UIViewController! {
        return nil
    }
    
    // MARK: SMCloudStorageCredentials delegate method/vars start
    
    public func syncServerAppLaunchSetup() {
    }
    
    public var syncServerUserIsSignedIn: Bool {
        get {
            return false
        }
    }
    
    public var syncServerSignedInUser:SMCloudStorageUser? {
        get {
            return nil
        }
    }
    
    // MARK: End of SMCloudStorageCredentials delegate methods
}

