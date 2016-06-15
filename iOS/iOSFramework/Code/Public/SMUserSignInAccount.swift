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

// "class" so its delegate var can be weak.
public protocol SMUserSignInAccountDelegate : class {
    var activeSignInDelegate:SMActivelySignedInUserDelegate! {get set}

    static var displayNameS: String? {get}
    var displayNameI: String? {get}

    // This will be called just once, when the app is launching. It is assumed that appLaunchSetup will do any initial network interaction needed. If silentSignIn is true, the callee should try to silently sign the user in (without UI interaction).
    func syncServerAppLaunchSetup(silentSignIn silentSignIn:Bool)
    
    func application(application: UIApplication!, openURL url: NSURL!, sourceApplication: String!, annotation: AnyObject!) -> Bool
    
    // Is a user currently signed in?
    var syncServerUserIsSignedIn: Bool {get}
    
    // Credentials specific to the user signed in.
    // Returns non-nil value iff syncServerUserSignedIn is true.
    var syncServerSignedInUser:SMUserCredentials? {get}
    
    // If user is currently signed in, sign them out. No effect if not signed in.
    func syncServerSignOutUser()
    
    // At least OAuth2 requires that the IdToken be refreshed occaisonally.
    func syncServerRefreshUserCredentials()
}

// The intent of this protocol is to enable you to manage your UI-- e.g., to determine which UI button's should be active, and also to allow you to persistently store the SMUserSignIn.
public protocol SMActivelySignedInUserDelegate {
    func smUserSignIn(userJustSignedIn userSignIn:SMUserSignInAccountDelegate)
    func smUserSignIn(userJustSignedOut userSignIn:SMUserSignInAccountDelegate)
    
    // Was this SMUserSignInAccount the one that called userJustSignedIn (without calling userJustSignedOut) last? Value must be stored persistently. Implementors must ensure that there is at most one actively signed in account (i.e., SMUserSignInAccount object). This is a persistent version of the method syncServerUserIsSignedIn on the SMUserSignInDelegate.
    func smUserSignIn(activelySignedIn userSignIn:SMUserSignInAccountDelegate) -> Bool
}

public class SMUserSignInAccount : NSObject, SMUserSignInAccountDelegate {
    public var activeSignInDelegate:SMActivelySignedInUserDelegate!

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

    public func syncServerAppLaunchSetup(silentSignIn silentSignIn:Bool) {
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

