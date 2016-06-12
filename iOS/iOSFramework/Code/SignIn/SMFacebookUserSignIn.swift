//
//  SMFacebookUserSignIn.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 6/11/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import SMSyncServer
import SMCoreLib
import FBSDKLoginKit

public class SMFacebookUserSignIn : SMUserSignIn {
    public static let displayName = "Facebook"
    
    override public var displayName:String? {
        return SMFacebookUserSignIn.displayName
    }
    
    public override init() {
        super.init()
    }
    
    override public func syncServerAppLaunchSetup() {
    }
    
    override public func application(application: UIApplication!, openURL url: NSURL!, sourceApplication: String!, annotation: AnyObject!) -> Bool {
        return false
    }
    
    override public var syncServerUserIsSignedIn: Bool {
        get {
            return FBSDKAccessToken.currentAccessToken() != nil
        }
    }
    
    override public var syncServerSignedInUser:SMUserCredentials? {
        get {
            if self.syncServerUserIsSignedIn {
                return nil
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
            Log.msg("result: \(result); error: \(error)")
            Log.msg("FBSDKAccessToken.currentAccessToken().userID: \(FBSDKAccessToken.currentAccessToken().userID)")
            
            // Adapted from http://stackoverflow.com/questions/29323244/facebook-ios-sdk-4-0how-to-get-user-email-address-from-fbsdkprofile
            let parameters = ["fields" : "email, id, name"]
            FBSDKGraphRequest(graphPath: "me", parameters: parameters).startWithCompletionHandler { (connection:FBSDKGraphRequestConnection!, result: AnyObject!, error: NSError!) in
                Log.msg("result: \(result); error: \(error)")
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
        })
    }
}

