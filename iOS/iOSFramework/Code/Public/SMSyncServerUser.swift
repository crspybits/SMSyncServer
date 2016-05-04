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
public protocol SMCloudStorageUserDelegate : class {
    // This will be called just once, when the app is launching. It is assumed that appLaunchSetup will do any initial network interaction needed to sign in the user.
    func syncServerAppLaunchSetup()
    
    // Is a user currently signed in?
    var syncServerUserIsSignedIn: Bool {get}
    
    // Credentials specific to the cloud storage system being used.
    // Returns non-nil value iff syncServerUserSignedIn is true.
    var syncServerSignedInUser:SMCloudStorageUser? {get}
}

// "class" so its delegate var can be weak.
internal protocol SMUserServerParamsDelegate : class {
    var serverParams:[String:AnyObject]? {get}
}

// This enum is the interface from the client app to the SMSyncServer framework providing client credential information to the server.
public enum SMCloudStorageUser {
    // When using as a parameter to call createNewUser, authCode must not be nil.
    case GoogleDrive(idToken:String!, authCode:String?)
    
    // case Dropbox
    // case AppleDrive
}

public class SMSyncServerUser {
    private var _internalUserId:String?
    
    // A distinct UUID for this user mobile device.
    // I'm going to persist this in the keychain not so much because it needs to be secure, but rather because it will survive app deletions/reinstallations.
    private static let MobileDeviceUUID = SMPersistItemString(name: "SMSyncServerUser.MobileDeviceUUID", initialStringValue: "", persistType: .KeyChain)
    
    private var _signInCallback = NSObject()
    // var signInCompletion:((error:NSError?)->(Void))?
    
    internal weak var delegate:SMCloudStorageUserDelegate!
    
    public static var session = SMSyncServerUser()
    
    private init() {
        self._signInCallback.resetTargets()
    }
    
    // You *must* set this (e.g., shortly after app launch). Currently, this must be a single name, with no subfolders, relative to the root. Don't put any "/" character in the name.
    // 1/18/16; I just moved this here, from SMCloudStorageCredentials because it seems like the cloudFolderPath should be at a different level of abstraction, or at least seems independent of the details of cloud storage user creds.
    // 1/18/16; I've now made this public because the folder used in cloud storage is fundamentally a client app decision-- i.e., it is a decision made by the user of SMSyncServer, e.g., Petunia.
    // TODO: Eventually give the user a way to change the cloud folder path. BUT: It's a big change. i.e., the user shouldn't change this lightly because it will mean all of their data has to be moved or re-synced. (Plus, the SMSyncServer currently has no means to do such a move or re-sync-- it would have to be handled at a layer above the SMSyncServer).
    public var cloudFolderPath:String?
    
    internal func appLaunchSetup(withCloudStorageUserDelegate cloudStorageUserDelegate:SMCloudStorageUserDelegate!) {
    
        if 0 == SMSyncServerUser.MobileDeviceUUID.stringValue.characters.count {
            SMSyncServerUser.MobileDeviceUUID.stringValue = UUID.make()
        }
        
        self.delegate = cloudStorageUserDelegate
        SMServerAPI.session.userDelegate = self

        // Do this last because it could lead to invocation of the signInProcessCompleted callbacks.
        self.delegate.syncServerAppLaunchSetup()
    }
    
    // Add target/selector to this to get a callback when the user sign-in process completes.
    public var signInProcessCompleted:TargetsAndSelectors {
        get {
            return self._signInCallback
        }
    }
    
    // So we don't have to expose the delegate publicly.
    public var signedIn:Bool {
        get {
            return self.delegate.syncServerUserIsSignedIn
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
    
    // This method doesn't keep a reference to userCreds; it just allows the caller to check for an existing user on the server.
    public func checkForExistingUser(userCreds:SMCloudStorageUser, completion:((error: NSError?)->())?) {
    
        SMServerAPI.session.checkForExistingUser(
            self.serverParameters(userCreds)) { internalUserId, cfeuResult in
            self._internalUserId = internalUserId
            let returnError = self.processSignInResult(forExistingUser: true, apiResult: cfeuResult)
            self.callSignInCompletion(withError: returnError)
            completion?(error: returnError)
        }
    }
    
    // This method doesn't keep a reference to userCreds; it just allows the caller to create a new user on the server.
    public func createNewUser(userCreds:SMCloudStorageUser, completion:((error: NSError?)->())?) {
    
        switch (userCreds) {
        case .GoogleDrive(_, let authCode):
            Assert.If(nil == authCode, thenPrintThisString: "The authCode must be non-nil when calling createNewUser for a Google user")
        }
        
        SMServerAPI.session.createNewUser(self.serverParameters(userCreds)) { internalUserId, cnuResult in
            self._internalUserId = internalUserId
            let returnError = self.processSignInResult(forExistingUser: false, apiResult: cnuResult)
            self.callSignInCompletion(withError: returnError)
            completion?(error: returnError)
        }
    }
    
    private func callSignInCompletion(withError error:NSError?) {
        if error == nil {
            self._signInCallback.forEachTargetInCallbacksDo() { (obj:AnyObject?, sel:Selector, dict:NSMutableDictionary!) in
                if let nsObject = obj as? NSObject {
                    nsObject.performSelector(sel)
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
    // TODO: Do we still need this additionalCredentials param after the changes of 1/18/16?
    private func serverParameters(userCredsData:SMCloudStorageUser, additionalCredentials additionalCreds:[String:AnyObject]?=nil) -> [String:AnyObject] {
        
        var serverParameters = [String:AnyObject]()
        var userCredentials = [String:AnyObject]()
        
        if (additionalCreds != nil) {
            userCredentials = additionalCreds!
        }
        
        Assert.If(0 == SMSyncServerUser.MobileDeviceUUID.stringValue.characters.count, thenPrintThisString: "Whoops: No device UUID!")
        
        userCredentials[SMServerConstants.mobileDeviceUUIDKey] = SMSyncServerUser.MobileDeviceUUID.stringValue
        userCredentials[SMServerConstants.cloudFolderPath] = self.cloudFolderPath!
        
        switch (userCredsData) {
        case .GoogleDrive(let idToken, let authCode):
            Log.msg("Sending IdToken: \(idToken)")
            
            userCredentials[SMServerConstants.cloudType] = SMServerConstants.cloudTypeGoogle
            userCredentials[SMServerConstants.googleUserCredentialsIdToken] = idToken

            if (authCode != nil) {
                userCredentials[SMServerConstants.googleUserCredentialsAuthCode] = authCode!
            }
        }

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

extension SMSyncServerUser : SMUserServerParamsDelegate {
    var serverParams:[String:AnyObject]? {
        get {
            Assert.If(!self.delegate.syncServerUserIsSignedIn, thenPrintThisString: "Yikes: There is no signed in user!")
            return self.serverParameters(self.delegate.syncServerSignedInUser!)
        }
    }
}

