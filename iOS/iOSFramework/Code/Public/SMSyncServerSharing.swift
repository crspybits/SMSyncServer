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

// Handles urls of the form: <BundleId>.authorize://?code=<UUID>&email=<EmailAddress>
// code needs to be first query param, and email needs to be second.
// Email address is being required to give a unique identifier for that person on the sync server.
public class SMSyncServerSharing {
    private let queryItemAuthorizationCode = "code"
    private let queryItemEmailAddress = "email"
    
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
                    let queryItemEmail = components.queryItems![1]
                    if queryItemCode.name == self.queryItemAuthorizationCode && queryItemCode.value != nil && queryItemEmail.name == self.queryItemEmailAddress && queryItemEmail.value != nil  {
                        Log.msg("queryItemCode.value: \(queryItemCode.value!)")
                        Log.msg("queryItemEmail.value: \(queryItemEmail.value!)")
                        
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
    
    // Modified from http://www.swift-studies.com/blog/2015/6/17/exploring-swift-20-optionsettypes
    public struct UserCapabilityMask : OptionSetType {
        private enum UserCapability : Int, CustomStringConvertible {
            case Create /* Objects */ = 1
            case Read /* Objects */ = 2
            case Update /* Objects */ = 4
            case Delete /* Objects */ = 8
            case Authorize /* NewUsers */ = 16
            
            private var allAsStrings:[String] {
                return ["Create", "Read", "Update", "Delete", "Authorize"]
            }
            
            var description : String {
                var shift = 0
                while (self.rawValue >> shift != 1) {
                    shift += 1
                }
                return self.allAsStrings[shift]
            }
        }
        
        public let rawValue : Int
        public init(rawValue:Int){ self.rawValue = rawValue}
        private init(_ capability:UserCapability) {
            self.rawValue = capability.rawValue
        }

        public static let Create = UserCapabilityMask(UserCapability.Create)
        public static let Read = UserCapabilityMask(UserCapability.Read)
        public static let Update = UserCapabilityMask(UserCapability.Update)
        public static let Delete = UserCapabilityMask(UserCapability.Delete)
        public static let CRUD:UserCapabilityMask = [Create, Read, Update, Delete]
        public static let Authorize = UserCapabilityMask(UserCapability.Authorize)
        public static let ALL:UserCapabilityMask = [CRUD, Authorize]
        
        public var description : String {
            var result = ""
            var shift = 0

            while let currentCapability = UserCapability(rawValue: 1 << shift) {
                shift += 1
                if self.contains(UserCapabilityMask(currentCapability)) {
                    result += (result.characters.count == 0) ? "\(currentCapability)" : ",\(currentCapability)"
                }
            }

            return "[\(result)]"
        }
    }
    
    // The account types that sharing users have available to them to access sync server data.
    public enum AccountType : String {
        case Facebook
    }
    
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
}
