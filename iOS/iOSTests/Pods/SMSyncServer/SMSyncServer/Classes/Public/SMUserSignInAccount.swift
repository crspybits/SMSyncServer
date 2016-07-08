//
//  SMUserSignInAccount.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 11/26/15.
//  Copyright © 2015 Christopher Prince. All rights reserved.
//

// Abstract class for sign-in accounts. Only needed because of the way generics work-- and my use of SMLazyWeakRef.

import Foundation
import SMCoreLib

public protocol SMUserSignInAccountDelegate {
    func smUserSignIn(userJustSignedIn userSignIn:SMUserSignInAccount)
    func smUserSignIn(userJustSignedOut userSignIn:SMUserSignInAccount)
    
    // Was this SMUserSignInAccount the one that called userJustSignedIn (without calling userJustSignedOut) last? Value must be stored persistently. Implementors must ensure that there is at most one actively signed in account (i.e., SMUserSignInAccount object). This is a persistent version of the method syncServerUserIsSignedIn on the SMUserSignInDelegate.
    func smUserSignIn(activelySignedIn userSignIn:SMUserSignInAccount) -> Bool
    
    func smUserSignIn(getSharingInvitationCodeForUserSignIn userSignIn:SMUserSignInAccount) -> String?
    func smUserSignIn(resetSharingInvitationCodeForUserSignIn userSignIn:SMUserSignInAccount)
    
    // You must call selectLinkedAccount to make your selection after you receive this call.
    func smUserSignIn(userSignIn userSignIn:SMUserSignInAccount, linkedAccountsForSharingUser:[SMLinkedAccount], selectLinkedAccount:(internalUserId:SMInternalUserId)->())
}

public class SMUserSignInAccount : NSObject {
    public var delegate:SMUserSignInAccountDelegate!

    public class var displayNameS: String? {
        get {
            return nil
        }
    }
    
    public var displayNameI: String? {
        get {
            return nil
        }
    }

    public func syncServerAppLaunchSetup(silentSignIn silentSignIn:Bool, launchOptions:[NSObject: AnyObject]?) {
    }
    
    public func application(application: UIApplication!, openURL url: NSURL!, sourceApplication: String!, annotation: AnyObject!) -> Bool {
        return false
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
}

