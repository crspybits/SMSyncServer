//
//  SMFacebookUserSignIn.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 6/11/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

// Enables you to sign in as a Facebook user to (a) create a new sharing user (must have an invitation from another SMSyncServer user), or (b) sign in as an existing sharing user.

import Foundation
import SMSyncServer
import SMCoreLib
import FBSDKLoginKit

// I tried this initially as a way to find friends, but that didn't work
// Does *not* return friends in the way that would be useful to us here.
/*
// See https://developers.facebook.com/docs/graph-api/reference/user/friends/
FBSDKGraphRequest(graphPath: "me/friends", parameters: ["fields" : "data"]).startWithCompletionHandler { (connection:FBSDKGraphRequestConnection!, result: AnyObject!, error: NSError!) in
    Log.msg("result: \(result); error: \(error)")
}*/

public class SMFacebookUserSignIn : SMUserSignInAccount {
    private static let _fbUserName = SMPersistItemString(name: "SMFacebookUserSignIn.fbUserName", initialStringValue: "", persistType: .UserDefaults)
    
    private var fbUserName:String? {
        get {
            return SMFacebookUserSignIn._fbUserName.stringValue == "" ? nil : SMFacebookUserSignIn._fbUserName.stringValue
        }
        set {
            SMFacebookUserSignIn._fbUserName.stringValue =
                newValue == nil ? "" : newValue!
        }
    }

    override public static var displayNameS: String? {
        get {
            return SMServerConstants.accountTypeFacebook
        }
    }
    
    override public var displayNameI: String? {
        get {
            return SMFacebookUserSignIn.displayNameS
        }
    }
    
    override public init() {
    }
    
    override public func syncServerAppLaunchSetup(silentSignIn silentSignIn: Bool, launchOptions:[NSObject: AnyObject]?) {
    
        // TODO: What can be done for a silent sign-in? Perhaps pass a silent parameter to finishSignIn.
        
        // FBSDKLoginManager public class func renewSystemCredentials(handler: ((ACAccountCredentialRenewResult, NSError!) -> Void)!)
        
        // http://stackoverflow.com/questions/32950937/fbsdkaccesstoken-currentaccesstoken-nil-after-quitting-app
        FBSDKApplicationDelegate.sharedInstance().application(UIApplication.sharedApplication(), didFinishLaunchingWithOptions: launchOptions)
        
        Log.msg("FBSDKAccessToken.currentAccessToken(): \(FBSDKAccessToken.currentAccessToken())")
        
        if self.syncServerUserIsSignedIn {
            self.finishSignIn()
        }
    }
    
    override public func application(application: UIApplication!, openURL url: NSURL!, sourceApplication: String!, annotation: AnyObject!) -> Bool {
        return FBSDKApplicationDelegate.sharedInstance().application(application, openURL: url, sourceApplication: sourceApplication, annotation: annotation)
    }
    
    override public var syncServerUserIsSignedIn: Bool {
        get {
            return FBSDKAccessToken.currentAccessToken() != nil
        }
    }
    
    override public var syncServerSignedInUser:SMUserCredentials? {
        get {
            if self.syncServerUserIsSignedIn {
                return .Facebook(userType: SMServerConstants.userTypeSharing, accessToken: FBSDKAccessToken.currentAccessToken().tokenString, userId: FBSDKAccessToken.currentAccessToken().userID, userName: self.fbUserName)
            }
            else {
                return nil
            }
        }
    }
    
    override public func syncServerSignOutUser() {
        self.reallyLogOut()
    }
    
    override public func syncServerRefreshUserCredentials() {
    }
    
    public func signInButton() -> UIButton {
        let fbLoginButton = FBSDKLoginButton()
        // fbLoginButton.readPermissions =  ["public_profile", "email", "user_friends"]
        fbLoginButton.readPermissions =  ["email"]
        fbLoginButton.delegate = self
            
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(longPressAction))
        fbLoginButton.addGestureRecognizer(longPress)
        
        return fbLoginButton
    }
    
    @objc private func longPressAction() {
        if FBSDKAccessToken.currentAccessToken() != nil {
            self.reallyLogOut()
        }
    }
}

extension SMFacebookUserSignIn : FBSDKLoginButtonDelegate {
    public func loginButton(loginButton: FBSDKLoginButton!, didCompleteWithResult result: FBSDKLoginManagerLoginResult!, error: NSError!) {
    
        Log.msg("result: \(result); error: \(error)")
        
        if !result.isCancelled && error == nil {
            self.finishSignIn()
        }
    }

    public func loginButtonDidLogOut(loginButton: FBSDKLoginButton!) {
        self.activeSignInDelegate.smUserSignIn(userJustSignedOut: self)
    }
    
    private func finishSignIn() {
        Log.msg("FBSDKAccessToken.currentAccessToken().userID: \(FBSDKAccessToken.currentAccessToken().userID)")
        
        // Adapted from http://stackoverflow.com/questions/29323244/facebook-ios-sdk-4-0how-to-get-user-email-address-from-fbsdkprofile
        let parameters = ["fields" : "email, id, name"]
        FBSDKGraphRequest(graphPath: "me", parameters: parameters).startWithCompletionHandler { (connection:FBSDKGraphRequestConnection!, result: AnyObject!, error: NSError!) in
            Log.msg("result: \(result); error: \(error)")
            
            if nil == error {
                if let resultDict = result as? [String:AnyObject] {
                    // I'm going to prefer the email address, if we get it, just because it's more distinctive than the name.
                    if resultDict["email"] != nil {
                        self.fbUserName = resultDict["email"] as? String
                    }
                    else {
                        self.fbUserName = resultDict["name"] as? String
                    }
                }
            }
            
            let syncServerFacebookUser = SMUserCredentials.Facebook(userType: SMServerConstants.userTypeSharing, accessToken: FBSDKAccessToken.currentAccessToken().tokenString, userId: FBSDKAccessToken.currentAccessToken().userID, userName: self.fbUserName)
            
            // We are not going to allow the user to create a new sharing user without an invitation code. There just doesn't seem any point: They wouldn't have any access capabilities. So, if we don't have an invitation code, check to see if this user is already on the system.
            if AppDelegate.sharingInvitationCode == nil {
                SMSyncServerUser.session.checkForExistingUser(
                    syncServerFacebookUser, completion: { error in
                    
                    if error == nil {
                        self.activeSignInDelegate.smUserSignIn(userJustSignedIn: self)
                    }
                    else {
                        // TODO: Give them an error message. Tell them they need an invitation from user on the system first.
                        Log.error("User not on the system: Need an invitation!")
                        self.reallyLogOut()
                    }
                })
            }
            else {
                // Going to redeem the invitation even if we get an error checking for email/name (username). The username is optional.
                // Not doing signing callbacks after success on createNewUser because we want to wait until a successful redeeming of the invitation to sign the user in.
                SMSyncServerUser.session.createNewUser(callbacksAfterSigninSuccess:false, userCreds: syncServerFacebookUser, completion: { error in
                    if error == nil {
                        // Need this right after createNewUser because redeemSharingInvitation needs a signed in user.
                        self.activeSignInDelegate.smUserSignIn(userJustSignedIn: self)
                    
                        // Success on redeeming will do the sign callback in process.
                        SMSyncServerUser.session.redeemSharingInvitation(invitationCode: AppDelegate.sharingInvitationCode!, completion: { couldNotRedeemSharingInvitation, error in
                        
                            if couldNotRedeemSharingInvitation {
                                AppDelegate.sharingInvitationCode = nil
                            }
                            
                            if error != nil {
                                // TODO: Give them an error message.
                                // Hmmm. We have an odd state here. If it was a new user, we created the user, but we couldn't redeem the invitation. What to do??
                                Log.error("Failed redeeming new user.")
                                self.reallyLogOut()
                            }
                        })
                    }
                    else {
                        // TODO: Give them an error message.
                        Log.error("Failed creating new user.")
                        self.reallyLogOut()
                    }
                })
            }
        }
    }
    
    // It seems really hard to fully logout!!! The following helps.
    private func reallyLogOut() {
        let deletepermission = FBSDKGraphRequest(graphPath: "me/permissions/", parameters: nil, HTTPMethod: "DELETE")
        deletepermission.startWithCompletionHandler({ (connection, result, error) in
            print("the delete permission is \(result)")
            FBSDKLoginManager().logOut()
            self.activeSignInDelegate.smUserSignIn(userJustSignedOut: self)
        })
    }
}

