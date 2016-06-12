//
//  SMUserSignIn.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 11/26/15.
//  Copyright © 2015 Christopher Prince. All rights reserved.
//

// Abstract class that enables a user to sign into specific (sharing or owning) user accounts. Subclasses will have details about the particular account systems (e.g., mechanisms for signing a user into Google) because we have to present some specific UI to allow the user to sign in, and authorize us (the app) for use of their account.

import Foundation
import SMCoreLib

public class SMUserSignIn : NSObject, SMUserSignInDelegate {
    // The keys are the displayName's for the specific credentials.
    private static var _possibleAccounts = [String: SMUserSignIn]()
    
    // I'd like to have this type be: SMLazyWeakRef<SMUserSignInDelegate>, but Swift doesn't like that!
    private static var _session = SMLazyWeakRef<SMUserSignIn>() {
        var current:SMUserSignIn?
        for signInAccount in _possibleAccounts.values {
            if signInAccount.syncServerUserIsSignedIn {
                Assert.If(current != nil, thenPrintThisString: "Yikes: Signed into more than one account!")
                current = signInAccount
            }
        }
        
        return current
    }

    // Account that the user is currently signed into, if any, as a lazy weak reference.
    public static var lazySession:SMLazyWeakRef<SMUserSignIn> {
        return _session
    }
    
    // You *must* override this to provide a name for the account type. Must be unique across account types.
    public var displayName: String? {
        return nil
    }
    
    // Since this has no setter, user won't be able to modify.
    public static var possibleAccounts:[String:SMUserSignIn] {
        return _possibleAccounts
    }

    // The user *must* be signed into at most one of these accounts.
    public static func addSignInAccount(signIn: SMUserSignIn) {
        self._possibleAccounts[signIn.displayName!] = signIn
    }
    
    // Call this from the corresponding method in the AppDelegate.
    public func application(application: UIApplication!, openURL url: NSURL!, sourceApplication: String!, annotation: AnyObject!) -> Bool {
        return false
    }
    
    // MARK: SMCloudStorageCredentials delegate method/vars start
    
    public func syncServerAppLaunchSetup() {
    }
    
    public var syncServerUserIsSignedIn: Bool {
        get {
            return false
        }
    }
    
    public var syncServerSignedInUser:SMUserCredentials? {
        get {
            return nil
        }
    }
    
    public func syncServerSignOutUser() {
    }
    
    public func syncServerRefreshUserCredentials() {
    }
    
    // MARK: End of SMCloudStorageCredentials delegate methods
}

