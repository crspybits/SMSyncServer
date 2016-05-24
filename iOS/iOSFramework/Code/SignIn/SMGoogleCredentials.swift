
//
//  SMGoogleCredentials.swift
//  NetDb
//
//  Created by Christopher Prince on 11/26/15.
//  Copyright © 2015 Christopher Prince. All rights reserved.
//

import Foundation
import SMSyncServer
import SMCoreLib
import Google

// See https://developers.google.com/identity/sign-in/ios/sign-in
public class SMGoogleCredentials : SMCloudStorageCredentials {

    // Specific to Google Credentials. I'm not sure it's needed really (i.e., could it be obtained each time the app launches on sign in-- since to be signed in really assumes we're connected to the network?), but I'll store this in the Keychain since it's credential info.
    // Hmmmm. I may be making incorrect assumptions about the longevity of these IdTokens. See https://github.com/google/google-auth-library-nodejs/issues/46 Does silently signing the user in generate a new IdToken?
    private static let IdToken = SMPersistItemString(name: "SMGoogleCredentials.IdToken", initialStringValue: "", persistType: .KeyChain)
    
    private let serverClientID:String!
    
    private var googleUser:GIDGoogleUser?
    private var currentlyRefreshing = false
    
    private var idToken:String! {
        set {
            SMGoogleCredentials.IdToken.stringValue = newValue
        }
        
        get {
            return SMGoogleCredentials.IdToken.stringValue
        }
    }
   
    public init(serverClientID theServerClientID:String) {
        self.serverClientID = theServerClientID
        super.init()
    }
    
    override public func syncServerAppLaunchSetup() {
        var configureError: NSError?
        GGLContext.sharedInstance().configureWithError(&configureError)
        assert(configureError == nil, "Error configuring Google services: \(configureError)")
        
        GIDSignIn.sharedInstance().delegate = self
        
        // Seem to need the following for accessing the serverAuthCode. Plus, you seem to need a "fresh" sign-in (not a silent sign-in). PLUS: serverAuthCode is *only* available when you don't do the silent sign in.
        // https://developers.google.com/identity/sign-in/ios/offline-access?hl=en
        GIDSignIn.sharedInstance().serverClientID = self.serverClientID 

        GIDSignIn.sharedInstance().scopes.append("https://www.googleapis.com/auth/drive.file")
        
        // 12/20/15; Trying to resolve my user sign in issue
        // It looks like, at least for Google Drive, calling this method is sufficient for dealing with rcStaleUserSecurityInfo. I.e., having the IdToken for Google become stale. (Note that while it deals with the IdToken becoming stale, dealing with an expired access token on the server is a different matter-- and the server seems to need to refresh the access token from the refresh token to deal with this independently).
        // See also this on refreshing of idTokens: http://stackoverflow.com/questions/33279485/how-to-refresh-authentication-idtoken-with-gidsignin-or-gidauthentication
        GIDSignIn.sharedInstance().signInSilently()
    }
    
    override public func handleURL(url: NSURL, sourceApplication: String?, annotation: AnyObject) -> Bool {
        return GIDSignIn.sharedInstance().handleURL(url, sourceApplication: sourceApplication,
            annotation: annotation)
    }
    
    /* Sometimes I get this when I try to silently sign in:
    
    Error signing in: Error Domain=com.google.GIDSignIn Code=-4 "(null)"
    ***** Error signing in: Optional(Error Domain=com.google.GIDSignIn Code=-4 "(null)")
    2015-12-11 02:55:21 +0000: [fg0,0,255;type: UserDefaults; name: DefsUserIsSignedIn; initialValue: 0; initialValueType: ImplicitlyUnwrappedOptional<AnyObject>[; [init(name:initialValue:persistType:) in SMPersistVars.swift, line 43]
    Error signing in: Error Domain=com.google.GIDSignIn Code=-4 "(null)"
    ***** Error signing in: Optional(Error Domain=com.google.GIDSignIn Code=-4 "(null)")         
    */
    // See http://stackoverflow.com/questions/31461139/signinsilently-generates-an-error-code-4
    // And see https://github.com/googlesamples/google-services/issues/27
    /* How is this Code=-4 error related (if at all) to the "verifyIdToken error: TypeError: Not a buffer" issue I'm getting on the server? Could it be that when I rebuild the iOS app, this occurs? To test this, I could wait for a considerable period of time (e.g., 1 day), and try to do an operation like Get File Index, all without rebuilding the iOS app. If I still get the "Not a buffer" error, when previously, the IdToken was working fine, then this is not an issue about rebuilding the app.
    On the client side, it seems that once I've gotten the "Not a buffer" error from the server, and I try to do the silent sign-in again on the client, I get this Code=-4 error.
    */
    /* I just got "User security token is stale" on the server, and a Code=-4 on the client when I tried to do the silently sign in. This happened to be after I did a deletion and rebuild of the app.
    */
    /* 12/13/15; I just got the "error: Not a buffer" on the server. Then I tried a silent sign in from the app, it worked. Note that while I had just rebuilt the app, I hadn't deleted it immediately before rebuilding.
    */
    /* 12/15/15; I just got the "error: Not a buffer" on the server. Then I tried a silent sign in from the app, and it failed with the Code=-4 error. I had just rebuilt the app, but I hadn't deleted the app immediately before.
    */
    // See https://cocoapods.org/pods/GoogleSignIn for current version of GoogleSignIn
    
    override public func makeSignInController() -> UIViewController! {
        return SMGoogleSignInController()
    }
    
    override public var syncServerUserIsSignedIn: Bool {
        get {
            return GIDSignIn.sharedInstance().hasAuthInKeychain()
        }
    }
    
    override public var syncServerSignedInUser:SMCloudStorageUser? {
        get {
            if self.syncServerUserIsSignedIn {
                return SMCloudStorageUser.GoogleDrive(idToken: self.idToken, authCode: nil)
            }
            else {
                return nil
            }
        }
    }
    
    override public func syncServerSignOutUser() {
        GIDSignIn.sharedInstance().signOut()
    }
    
    // 5/23/16; I just added this to deal with the case where the app has been in the foreground for a period of time, and the IdToken has expired.
    override public func syncServerRefreshUserCredentials() {
        // See also this on refreshing of idTokens: http://stackoverflow.com/questions/33279485/how-to-refresh-authentication-idtoken-with-gidsignin-or-gidauthentication
        
        guard self.googleUser != nil
        else {
            return
        }
        
        Synchronized.block(self) {
            if self.currentlyRefreshing {
                return
            }
            
            self.currentlyRefreshing = true
        }
        
        Log.special("refreshTokensWithHandler")
        
        self.googleUser!.authentication.refreshTokensWithHandler() { auth, error in
            self.currentlyRefreshing = false
            
            if error == nil {
                Log.special("refreshTokensWithHandler: Success")
                self.idToken = auth.idToken;
            }
            else {
                Log.error("Error refreshing tokens: \(error)")
            }
        }
    }
}

/* 1/24/16; I just got this:
Error signing in: Error Domain=com.google.HTTPStatus Code=500 "(null)" UserInfo={json={
    error = "internal_failure";
    "error_description" = "Backend Error";
}, data=<7b0a2022 6572726f 72223a20 22696e74 65726e61 6c5f6661 696c7572 65222c0a 20226572 726f725f 64657363 72697074 696f6e22 3a202242 61636b65 6e642045 72726f72 220a7d0a>}
*/

extension SMGoogleCredentials : GIDSignInDelegate {

    public func signIn(signIn: GIDSignIn!, didSignInForUser user: GIDGoogleUser!,
        withError error: NSError!) {
            if (error == nil) {
                self.googleUser = user
                
                Log.msg("Attempting to sign in to server...")
                // Perform any operations on signed in user here.
                // let userId = user.userID     // For client-side use only!
                // let name = user.profile.name
                // let email = user.profile.email
                
                // user.serverAuthCode can be nil if the user didn't do a "fresh" signin. i.e., if we silently signed in the user.
                /* We're going to handle this in two cases:
                a) user.serverAuthCode is present: Try to create a new user
                b) user.serverAuthCode is not present: Try to check for an existing user
                */
                
                Log.msg("Attempting to sign in: idToken: \(user.authentication.idToken); user.serverAuthCode: \(user.serverAuthCode)")
                
                let syncServerGoogleUser = SMCloudStorageUser.GoogleDrive(idToken:user.authentication.idToken, authCode:user.serverAuthCode)
                
                if user.serverAuthCode == nil {
                    SMSyncServerUser.session.checkForExistingUser(syncServerGoogleUser) { error in
                        if nil == error {
                            self.idToken = user.authentication.idToken;
                        }
                    }
                }
                else {
                    SMSyncServerUser.session.createNewUser(syncServerGoogleUser) { error in
                        if nil == error {
                            self.idToken = user.authentication.idToken;
                        }
                    }
                }
            } else {
                Log.error("Error signing in: \(error)")
            }
    }
    
    public func signIn(signIn: GIDSignIn!, didDisconnectWithUser user:GIDGoogleUser!,
        withError error: NSError!) {
            // Perform any operations when the user disconnects from app here.
            // ...
    }
}

