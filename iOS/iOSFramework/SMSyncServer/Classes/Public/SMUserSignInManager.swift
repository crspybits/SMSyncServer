//
//  SMUserSignInManager.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 11/26/15.
//  Copyright © 2015 Christopher Prince. All rights reserved.
//

import Foundation
import SMCoreLib

public protocol SMUserSignInManagerDelegate {
    // Need to ask person if they want to sign-in now with their Facebook creds.
    // In general we could allow an authorized user to sign-in with various kinds of creds. Facebook, Twitter, Google.
    func didReceiveSharingInvitation(manager:SMUserSignInManager, invitationCode: String, userName: String?)
}

public class SMUserSignInManager {
    // The keys are the displayName's for the specific credentials.
    private var _possibleAccounts = [String: SMUserSignInAccount]()
    
    private static let _sharingInvitation = SMPersistItemString(name: "SMUserSignIn.sharingInvitation", initialStringValue: "", persistType: .UserDefaults)
    
    // I'd like to have this type be: SMLazyWeakRef<SMUserSignInAccountDelegate>, but Swift doesn't like that!
    private var _lazyCurrentUser:SMLazyWeakRef<SMUserSignInAccount>!

    private init() {
        SMSharingInvitations.session.callback = { invitationCode, userName in
            self.delegate?.didReceiveSharingInvitation(self, invitationCode: invitationCode, userName: userName)
        }
        
        self._lazyCurrentUser = SMLazyWeakRef<SMUserSignInAccount>() {
            var current:SMUserSignInAccount?
            
            for signInAccount in self._possibleAccounts.values {
                Log.msg("CHECKING: if signed in to account: \(signInAccount.displayNameI)")
                if signInAccount.delegate.smUserSignIn(activelySignedIn: signInAccount) {
                    Assert.If(current != nil, thenPrintThisString: "Yikes: Signed into more than one account!")
                    current = signInAccount
                    Log.msg("YES: Signed in to account! \(signInAccount.displayNameI)")
                }
            }
            
            return current
        }
    }
    
    public static let session = SMUserSignInManager()
    
    public var delegate:SMUserSignInManagerDelegate?

    // Account that the user is currently signed into, if any, as a lazy weak reference. (This is a lazy reference because the specific sign in account may change over time).
    public var lazyCurrentUser:SMLazyWeakRef<SMUserSignInAccount> {
        return self._lazyCurrentUser
    }
    
    // External callers should set this to nil when they know they have used the invitation code.
    public var sharingInvitationCode:String? {
        get {
            return SMUserSignInManager._sharingInvitation.stringValue == "" ? nil : SMUserSignInManager._sharingInvitation.stringValue
        }
        set {
            SMUserSignInManager._sharingInvitation.stringValue = newValue == nil ? "" : newValue!
        }
    }
    
    // Since this has no setter, user won't be able to modify.
    public var possibleAccounts:[String:SMUserSignInAccount] {
        return _possibleAccounts
    }

    // Call this method at app launch because it will invoke the syncServerAppLaunchSetup() method of the account. When you call this, you must have established the value for activeSignInDelegate for the SMUserSignIn object.
    public func addSignInAccount(signIn: SMUserSignInAccount, launchOptions:[NSObject: AnyObject]?) {
        self._possibleAccounts[signIn.displayNameI!] = signIn
        
        let silentSignIn = signIn.delegate.smUserSignIn(activelySignedIn: signIn)
        
        signIn.syncServerAppLaunchSetup(silentSignIn: silentSignIn, launchOptions:launchOptions)
    }
    
    // Call this from the corresponding method in the AppDelegate.
    public func application(application: UIApplication!, openURL url: NSURL!, sourceApplication: String!, annotation: AnyObject!) -> Bool {
        for signInAccount in _possibleAccounts.values {
            Log.msg("CHECKING: if account can handle openURL: \(signInAccount.displayNameI)")
            if signInAccount.application(application, openURL: url, sourceApplication: sourceApplication, annotation: annotation) {
                Log.msg("YES: account could handle openURL! \(signInAccount.displayNameI)")
                return true
            }
        }
               
        if SMSharingInvitations.session.application(application, openURL: url, sourceApplication: sourceApplication, annotation: annotation) {
            return true
        }
        
        return false
    }
}

// Enable non-owning (e.g., Facebook) users to access sync server data.
public class SMSharingInvitations {
    private let queryItemAuthorizationCode = "code"
    private let queryItemUserName = "username"
    
    private static let session = SMSharingInvitations()
    
    // Called when it gets an invitation.
    private var callback:((invitationCode:String, userName:String?)->())?
    
    // The upper/lower case sense of this is ignored.
    static let urlScheme = SMIdentifiers.session().APP_BUNDLE_IDENTIFIER() + ".invitation"
    
    private init() {
    }
    
    // This URL/String is suitable for sending in an email to the person being invited.
    // Handles urls of the form: 
    //      <BundleId>.invitation://?code=<InvitationCode>&username=<UserName>
    //      where <BundleId> is something like biz.SpasticMuffin.SharedNotes
    // code needs to be first query param, and username needs to be second (if given).
    // Username can be an email address, or other string descriptively identifying the user.
    // TODO: Should we restrict the set of characters that can be in a username?
    public static func createSharingURL(invitationCode invitationCode:String, username:String?) -> String {
    
        var usernameParam = ""
        if username != nil {
            if let escapedUserName = username!.stringByAddingPercentEscapesUsingEncoding(NSUTF8StringEncoding) {
                usernameParam = "&username=" + escapedUserName
            }
        }
        
        let urlString = self.urlScheme + "://?code=" + invitationCode + usernameParam
        
        return urlString
    }
    
    // Returns true iff can handle the url.
    private func application(application: UIApplication!, openURL url: NSURL!, sourceApplication: String!, annotation: AnyObject!) -> Bool {
        Log.msg("url: \(url)")
        
        var returnResult = false
        
        // Use case insensitive comparison because the incoming url scheme will be lower case.
        if url.scheme.caseInsensitiveCompare(SMSharingInvitations.urlScheme) == NSComparisonResult.OrderedSame {
            if let components = NSURLComponents(URL: url, resolvingAgainstBaseURL: false) {
                Log.msg("components.queryItems: \(components.queryItems)")
                if components.queryItems != nil {
                    let queryItemCode = components.queryItems![0]
                    if queryItemCode.name == self.queryItemAuthorizationCode && queryItemCode.value != nil  {
                        Log.msg("queryItemCode.value: \(queryItemCode.value!)")
                        
                        var username:String?
                        
                        if components.queryItems!.count == 2 {
                            let queryItemUserName = components.queryItems![1]

                            if queryItemUserName.name == self.queryItemUserName && queryItemUserName.value != nil {
                                Log.msg("queryItemUserName.value: \(queryItemUserName.value!)")
                            }
                        }
                        
                        returnResult = true
                        callback?(invitationCode:queryItemCode.value!, userName: username)
                    }
                }
            }
        }

        return returnResult
    }
}
