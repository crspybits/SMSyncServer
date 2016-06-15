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
    
    override public func syncServerAppLaunchSetup(silentSignIn silentSignIn: Bool) {
        // TODO: What can be done for a silent sign-in?
        
        // FBSDKLoginManager public class func renewSystemCredentials(handler: ((ACAccountCredentialRenewResult, NSError!) -> Void)!)
        
        Log.msg("FBSDKAccessToken.currentAccessToken(): \(FBSDKAccessToken.currentAccessToken())")
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
        if !result.isCancelled {
            self.activeSignInDelegate.smUserSignIn(userJustSignedIn: self)

            Log.msg("result: \(result); error: \(error)")
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
                
                // We can't directly create a new sharing user. So, if we don't have an invitation code, check to see if this user is already on the system.
                if AppDelegate.sharingInvitationCode == nil {
                    SMSyncServerUser.session.checkForExistingUser(self.syncServerSignedInUser!, completion: { error in
                        
                    })
                }
                else {
                    // Going to redeem the invitation even if we get an error checking for email/name. That doesn't seem vital at this point.
                    SMSyncServerUser.session.redeemSharingInvitation(invitationCode: AppDelegate.sharingInvitationCode!, completion: { error in
                        
                    })
                }
            }
            
            // Does *not* return friends in the way that would be useful to us here.
            /*
            // See https://developers.facebook.com/docs/graph-api/reference/user/friends/
            FBSDKGraphRequest(graphPath: "me/friends", parameters: ["fields" : "data"]).startWithCompletionHandler { (connection:FBSDKGraphRequestConnection!, result: AnyObject!, error: NSError!) in
                Log.msg("result: \(result); error: \(error)")
            }*/
        }
    }

    public func loginButtonDidLogOut(loginButton: FBSDKLoginButton!) {
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

