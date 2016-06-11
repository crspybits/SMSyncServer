//
//  SMSyncServerSharing.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 6/10/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import SMCoreLib

// Enable non-owning (e.g., Facebook) users to access sync server data.

// Handles urls of the form: <BundleId>.authorize://?code=<UUID>&username=<UserName>
// code needs to be first query param, and username needs to be second (if given).
// Username can be an email address, or other string descriptively identifying the user.
// TODO: Should we restrict the set of characters that can be in a username?
public class SMSyncServerSharing {
    private let queryItemAuthorizationCode = "code"
    private let queryItemUserName = "username"
    
    // The upper/lower case sense of this is ignored.
    private var urlScheme:String
    
    public static let session = SMSyncServerSharing()
    
    private init() {
        self.urlScheme = SMIdentifiers.session().APP_BUNDLE_IDENTIFIER() + ".authorize"
    }
    
    // Returns true iff can handle the url.
    public func application(application: UIApplication!, openURL url: NSURL!, sourceApplication: String!, annotation: AnyObject!) -> Bool {
        Log.msg("url: \(url)")
        
        // Use case insensitive comparison because the incoming url scheme will be lower case.
        if url.scheme.caseInsensitiveCompare(self.urlScheme) == NSComparisonResult.OrderedSame {
            if let components = NSURLComponents(URL: url, resolvingAgainstBaseURL: false) {
                Log.msg("components.queryItems: \(components.queryItems)")
                if components.queryItems != nil && components.queryItems!.count == 2 {
                    let queryItemCode = components.queryItems![0]
                    if queryItemCode.name == self.queryItemAuthorizationCode && queryItemCode.value != nil  {
                        Log.msg("queryItemCode.value: \(queryItemCode.value!)")
                        
                        let queryItemUserName = components.queryItems![1]

                        if queryItemUserName.name == self.queryItemUserName && queryItemUserName.value != nil {
                            Log.msg("queryItemEmail.value: \(queryItemUserName.value!)")
                        }
                        
                        // Need to ask person if they want to sign-in now with their Facebook creds.
                        // In general we could allow an authorized user to sign-in with various kinds of creds. Facebook, Twitter, Google.
                    }
                }
            }
            
            return true
        }
        else {
            return false
        }
    }
    
    // The account types that sharing users have available to them to access sync server data.
    public enum AccountType : String {
        case Facebook
    }
    
    /*
    public struct SharingUser {
        var capabilityMask:UserCapabilityMask
        var email:String
        var authorizationCode:String
        var codeExpiry:NSDate
        var accountTypeRedeemed:AccountType?
    }
    
    // The sharing users operations provided below apply with respect to the currently signed in user and the sync server data of that user.
    
    public func addSharingUser(userCapabilityMask:UserCapabilityMask, userEmail:String, callback:(user:SharingUser?, error:NSError?)->()) {
    }
    
    public func getSharingUsers(callback:([SharingUser], error:NSError?)->()) {
    }
    
    // Giving a nil userCapabilityMask will remove all authorizations for that user.
    public func updateSharingUser(userCapabilityMask:UserCapabilityMask?, userEmail:String, callback:(error:NSError?)->()) {
    }
    
    public func deleteSharingUser(userEmail:String, callback:(error:NSError?)->()) {
    }
    */
}
