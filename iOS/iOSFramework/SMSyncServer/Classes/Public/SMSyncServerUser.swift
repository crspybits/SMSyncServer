//
//  SMSyncServerUser.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 1/18/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

// Provides user sign-in & authentication for the SyncServer.

import Foundation
import SMCoreLib

// "class" so its delegate var can be weak.
internal protocol SMServerAPIUserDelegate : class {
    var userCredentialParams:[String:AnyObject]? {get}
    func refreshUserCredentials()
}

public struct SMLinkedAccount {
    // This is the userId assigned by the sync server, not by the specific account system.
    public var internalUserId:SMInternalUserId
    public var userName:String?
    public var sharingType:SMSharingType
}

public enum SMUserType : Equatable {
    case OwningUser
    
    // The owningUserId selects the specific shared/linked account being shared. It should only be nil when you are first creating the account, or redeeming a new sharing invitation.
    case SharingUser(owningUserId:SMInternalUserId?)
    
    public func toString() -> String {
        switch self {
        case .OwningUser:
            return SMServerConstants.userTypeOwning
        case .SharingUser:
            return SMServerConstants.userTypeSharing
        }
    }
}

public func ==(lhs:SMUserType, rhs:SMUserType) -> Bool {
    switch lhs {
    case .OwningUser:
        switch rhs {
        case .OwningUser:
            return true
        case .SharingUser(_):
            return false
        }
        
    case .SharingUser(_):
        switch rhs {
        case .OwningUser:
            return false
        case .SharingUser(_):
            return true
        }
    }
}

// This enum is the interface from the client app to the SMSyncServer framework providing client credential information to the server.
public enum SMUserCredentials {
    // In the following,
    
    // userType *must* be OwningUser.
    // When using as a parameter to call createNewUser, authCode must not be nil.
    case Google(userType:SMUserType, idToken:String!, authCode:String?, userName:String?)

    // userType *must* be SharingUser
    case Facebook(userType:SMUserType, accessToken:String!, userId:String!, userName:String?)
    
    internal func toServerParameterDictionary() -> [String:AnyObject] {
        var userCredentials = [String:AnyObject]()
        
        switch self {
        case .Google(userType: let userType, idToken: let idToken, authCode: let authCode, userName: let userName):
            Assert.If(userType != .OwningUser, thenPrintThisString: "Yikes: Google accounts with userTypeSharing not yet implemented!")
            Log.msg("Sending IdToken: \(idToken)")
            
            userCredentials[SMServerConstants.userType] = userType.toString()
            userCredentials[SMServerConstants.accountType] = SMServerConstants.accountTypeGoogle
            userCredentials[SMServerConstants.googleUserIdToken] = idToken
            userCredentials[SMServerConstants.googleUserAuthCode] = authCode
            userCredentials[SMServerConstants.accountUserName] = userName
        
        case .Facebook(userType: let userType, accessToken: let accessToken, userId: let userId, userName: let userName):

            switch userType {
            case .OwningUser:
                Assert.badMojo(alwaysPrintThisString: "Yikes: Not allowed!")
            
            case .SharingUser(owningUserId: let owningUserId):
                Log.msg("owningUserId: \(owningUserId)")
                userCredentials[SMServerConstants.linkedOwningUserId] = owningUserId
            }
            
            userCredentials[SMServerConstants.userType] = userType.toString()
            userCredentials[SMServerConstants.accountType] = SMServerConstants.accountTypeFacebook
            userCredentials[SMServerConstants.facebookUserId] = userId
            userCredentials[SMServerConstants.facebookUserAccessToken] = accessToken
            userCredentials[SMServerConstants.accountUserName] = userName
        }
        
        return userCredentials
    }
}

// This class is *not* intended to be subclassed for particular sign-in systems.
public class SMSyncServerUser {
    private var _internalUserId:String?
    
    // A distinct UUID for this user mobile device.
    // I'm going to persist this in the keychain not so much because it needs to be secure, but rather because it will survive app deletions/reinstallations.
    private static let MobileDeviceUUID = SMPersistItemString(name: "SMSyncServerUser.MobileDeviceUUID", initialStringValue: "", persistType: .KeyChain)
    
    private var _signInCallback = NSObject()
    // var signInCompletion:((error:NSError?)->(Void))?
    
    internal weak var delegate: SMLazyWeakRef<SMUserSignInAccount>!
    
    public static var session = SMSyncServerUser()
    
    private init() {
        self._signInCallback.resetTargets()
    }
    
    // You *must* set this (e.g., shortly after app launch). Currently, this must be a single name, with no subfolders, relative to the root. Don't put any "/" character in the name.
    // 1/18/16; I just moved this here, from SMCloudStorageCredentials because it seems like the cloudFolderPath should be at a different level of abstraction, or at least seems independent of the details of cloud storage user creds.
    // 1/18/16; I've now made this public because the folder used in cloud storage is fundamentally a client app decision-- i.e., it is a decision made by the user of SMSyncServer, e.g., Petunia.
    // TODO: Eventually it would seem like a good idea to give the user a way to change the cloud folder path. BUT: It's a big change. i.e., the user shouldn't change this lightly because it will mean all of their data has to be moved or re-synced. (Plus, the SMSyncServer currently has no means to do such a move or re-sync-- it would have to be handled at a layer above the SMSyncServer).
    public var cloudFolderPath:String?
    
    internal func appLaunchSetup(withUserSignInLazyDelegate userSignInLazyDelegate:SMLazyWeakRef<SMUserSignInAccount>!) {
    
        if 0 == SMSyncServerUser.MobileDeviceUUID.stringValue.characters.count {
            SMSyncServerUser.MobileDeviceUUID.stringValue = UUID.make()
        }
        
        self.delegate = userSignInLazyDelegate
        SMServerAPI.session.userDelegate = self
    }
    
    // Add target/selector to this to get a callback when the user sign-in process completes.
    // An NSError? parameter is passed to each target/selector you give, which will be nil if there was no error in the sign-in process, and non-nil if there was an error in signing in.
    public var signInProcessCompleted:TargetsAndSelectors {
        get {
            return self._signInCallback
        }
    }
    
    // Is the user signed in? (So we don't have to expose the delegate publicly.)
    public var signedIn:Bool {
        get {
            if let result = self.delegate.lazyRef?.syncServerUserIsSignedIn {
                return result
            }
            else {
                return false
            }
        }
    }
    
    // A string giving the identifier used internally on the SMSyncServer server to refer to a users cloud storage account. Has no meaning with respect to any specific cloud storage system (e.g., Google Drive).
    // Returns non-nil value iff signedIn is true.
    public var internalUserId:String? {
        get {
            if self.signedIn {
                Assert.If(self._internalUserId == nil, thenPrintThisString: "Yikes: Nil internal user id")
                return self._internalUserId
            }
            else {
                return nil
            }
        }
    }
    
    public func signOut() {
        self.delegate.lazyRef?.syncServerSignOutUser()
    }
    
    // This method doesn't keep a reference to userCreds; it just allows the caller to create a new user on the server.
    public func createNewUser(callbacksAfterSigninSuccess callbacksAfterSignin:Bool=true, userCreds:SMUserCredentials, completion:((error: NSError?)->())?) {
    
        switch (userCreds) {
        case .Google(userType: _, idToken: _, authCode: let authCode, userName: _):
            Assert.If(nil == authCode, thenPrintThisString: "The authCode must be non-nil when calling createNewUser for a Google user")

        case .Facebook:
            break
        }
        
        SMServerAPI.session.createNewUser(self.serverParameters(userCreds)) { internalUserId, cnuResult in
            self._internalUserId = internalUserId
            let returnError = self.processSignInResult(forExistingUser: false, apiResult: cnuResult)
            completion?(error: returnError)
            if callbacksAfterSignin {
                self.callSignInCompletion(withError: returnError)
            }
        }
    }
    
    // This method doesn't keep a reference to userCreds; it just allows the caller to check for an existing user on the server.
    public func checkForExistingUser(userCreds:SMUserCredentials, completion:((error: NSError?)->())?) {
    
        SMServerAPI.session.checkForExistingUser(
            self.serverParameters(userCreds)) { internalUserId, cfeuResult in
            self._internalUserId = internalUserId
            let returnError = self.processSignInResult(forExistingUser: true, apiResult: cfeuResult)
            completion?(error: returnError)
            self.callSignInCompletion(withError: returnError)
        }
    }
    
    public func createSharingInvitation(sharingType:SMSharingType, completion:((invitationCode:String?, error:NSError?)->(Void))?) {
        
        SMServerAPI.session.createSharingInvitation(sharingType: sharingType.rawValue) { invitationCode, apiResult in
            completion?(invitationCode: invitationCode, error: apiResult.error)
        }
    }
    
    // Optionally can have a currently signed in user. i.e., if you give userCreds, they will be used. Otherwise, the currently signed in user creds are used.
    // If there is no error on redeeming the invitation, the sign in callbacks are called.
    public func redeemSharingInvitation(invitationCode invitationCode:String, userCreds:SMUserCredentials?=nil, completion:((linkedOwningUserId:SMInternalUserId?, error: NSError?)->())?) {
        
        var userCredParams:[String:AnyObject]
        if userCreds == nil {
            userCredParams = self.userCredentialParams!
        }
        else {
            userCredParams = self.serverParameters(userCreds!)
        }
        
        SMServerAPI.session.redeemSharingInvitation(
            userCredParams, invitationCode: invitationCode, completion: { (linkedOwningUserId, internalUserId, apiResult) in
            Log.msg("SMServerAPI linkedOwningUserId: \(linkedOwningUserId)")
            let returnError = self.processSignInResult(forExistingUser: true, apiResult: apiResult)
            completion?(linkedOwningUserId:linkedOwningUserId, error: returnError)
            self.callSignInCompletion(withError: returnError)
        })
    }
    
    public func getLinkedAccountsForSharingUser(userCreds:SMUserCredentials?=nil, completion:((linkedAccounts:[SMLinkedAccount]?, error:NSError?)->(Void))?) {
        
        var userCredParams:[String:AnyObject]
        if userCreds == nil {
            userCredParams = self.userCredentialParams!
        }
        else {
            userCredParams = self.serverParameters(userCreds!)
        }
        
        SMServerAPI.session.getLinkedAccountsForSharingUser(userCredParams) { (linkedAccounts, apiResult) -> (Void) in
            completion?(linkedAccounts:linkedAccounts, error:apiResult.error)
        }
    }
    
    private func callSignInCompletion(withError error:NSError?) {
        if error == nil {
            self._signInCallback.forEachTargetInCallbacksDo() { (obj:AnyObject?, sel:Selector, dict:NSMutableDictionary!) in
                if let nsObject = obj as? NSObject {
                    nsObject.performSelector(sel, withObject: error)
                }
                else {
                    Assert.badMojo(alwaysPrintThisString: "Objects should be NSObject's")
                }
            }
        }
        else {
            Log.error("Could not sign in: \(error)")
        }
    }
    
    // Parameters in a REST API call to be provided to the server for a user's credentials & other info (e.g., deviceId, cloudFolderPath).
    private func serverParameters(userCreds:SMUserCredentials) -> [String:AnyObject] {
        Assert.If(0 == SMSyncServerUser.MobileDeviceUUID.stringValue.characters.count, thenPrintThisString: "Whoops: No device UUID!")
        
        var userCredentials = userCreds.toServerParameterDictionary()
        
        userCredentials[SMServerConstants.mobileDeviceUUIDKey] = SMSyncServerUser.MobileDeviceUUID.stringValue
        userCredentials[SMServerConstants.cloudFolderPath] = self.cloudFolderPath!
        
        var serverParameters = [String:AnyObject]()
        serverParameters[SMServerConstants.userCredentialsDataKey] = userCredentials
        
        return serverParameters
    }
    
    private func processSignInResult(forExistingUser existingUser:Bool, apiResult:SMServerAPIResult) -> NSError? {
        // Not all non-nil "errors" actually indicate an error in our context. Check the return code first.
        var returnError = apiResult.error
        
        if apiResult.returnCode != nil {
            switch (apiResult.returnCode!) {
            case SMServerConstants.rcOK:
                returnError = nil
                
            case SMServerConstants.rcUserOnSystem:
                returnError = nil
                
            case SMServerConstants.rcUserNotOnSystem:
                if existingUser {
                    returnError = Error.Create("That user doesn't exist yet-- you need to create the user first!")
                }
                
            default:
                returnError = Error.Create("An error occurred when trying to sign in (return code: \(apiResult.returnCode))")
            }
        }
        
        return returnError
    }
}

extension SMSyncServerUser : SMServerAPIUserDelegate {
    var userCredentialParams:[String:AnyObject]? {
        get {
            Assert.If(!self.signedIn, thenPrintThisString: "Yikes: There is no signed in user!")
            if let creds = self.delegate.lazyRef?.syncServerSignedInUser {
                return self.serverParameters(creds)
            }
            else {
                return nil
            }
        }
    }
    
    func refreshUserCredentials() {
        self.delegate.lazyRef?.syncServerRefreshUserCredentials()
    }
}

