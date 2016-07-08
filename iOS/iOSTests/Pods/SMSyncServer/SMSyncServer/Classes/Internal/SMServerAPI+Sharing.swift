//
//  SMServerAPI+Sharing.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 6/11/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

// Server calls for sharing with non-owning users

import Foundation
import SMCoreLib

internal extension SMServerAPI {

    // Create sharing invitation of current owning user's cloud storage data.
    // An owning user must currently be signed in. Doesn't require a lock. The capabilities must not be empty.
    // capabilities is an optional value only to allow for error case testing on the server. In production builds, it *must* not be nil.
    internal func createSharingInvitation(capabilities capabilities:SMSharingUserCapabilityMask?, completion:((invitationCode:String?, apiResult:SMServerAPIResult)->(Void))?) {
        
        var capabilitiesStringArray:[String]?
        if capabilities != nil {
            capabilitiesStringArray = capabilities!.stringArray
        }
 
        self.createSharingInvitation(capabilities: capabilitiesStringArray) { (invitationCode, apiResult) in
            completion?(invitationCode: invitationCode, apiResult: apiResult)
        }
    }
    
    // This is only marked as "internal" (and not private) for testing purposes. In regular (non-testing code), call the method above.
    internal func createSharingInvitation(capabilities capabilities:[String]?, completion:((invitationCode:String?, apiResult:SMServerAPIResult)->(Void))?) {

        let userParams = self.userDelegate.userCredentialParams
        Assert.If(nil == userParams, thenPrintThisString: "No user server params!")
        
        var parameters = userParams!
        
        #if !DEBUG
            if capabilities == nil || capabilities!.count == 0 {
                completion?(invitationCode: nil,
                    apiResult: SMServerAPIResult(returnCode: nil,
                        error: Error.Create("There were no capabilities!")))
                return
            }
        #endif
    
        parameters[SMServerConstants.userCapabilities] = capabilities
        
        let serverOpURL = NSURL(string: self.serverURLString +
                        "/" + SMServerConstants.operationCreateSharingInvitation)!
        
        SMServerNetworking.session.sendServerRequestTo(toURL: serverOpURL, withParameters: parameters) { (serverResponse:[String:AnyObject]?, error:NSError?) in
            
            var result = self.initialServerResponseProcessing(serverResponse, error: error)
            
            var invitationCode:String?
            if nil == result.error {
                invitationCode = serverResponse![SMServerConstants.sharingInvitationCode] as? String
                if nil == invitationCode {
                    result.error = Error.Create("Didn't get a Sharing Invitation Code back from server")
                }
            }
            
            completion?(invitationCode: invitationCode, apiResult: result)
        }
    }
    
    // This method is really just for testing. It's useful for looking up invitation info to make sure the invitation was stored on the server in its database.
    // You can only lookup invitations that you own/have sent. i.e., you can't lookup other people's invitations.
    internal func lookupSharingInvitation(invitationCode invitationCode:String, completion:((invitationContents:[String:AnyObject]?, apiResult:SMServerAPIResult)->(Void))?) {

        let userParams = self.userDelegate.userCredentialParams
        Assert.If(nil == userParams, thenPrintThisString: "No user server params!")
        
        var parameters = userParams!
    
        parameters[SMServerConstants.sharingInvitationCode] = invitationCode
        
        let serverOpURL = NSURL(string: self.serverURLString +
                        "/" + SMServerConstants.operationLookupSharingInvitation)!
        
        SMServerNetworking.session.sendServerRequestTo(toURL: serverOpURL, withParameters: parameters) { (serverResponse:[String:AnyObject]?, error:NSError?) in
            
            var result = self.initialServerResponseProcessing(serverResponse, error: error)
            
            var invitationContents:[String:AnyObject]?
            if nil == result.error {
                invitationContents = serverResponse![SMServerConstants.resultInvitationContentsKey] as? [String:AnyObject]
                if nil == invitationContents {
                    result.error = Error.Create("Didn't get Sharing Invitation Contents back from server")
                }
            }
            
            completion?(invitationContents: invitationContents, apiResult: result)
        }
    }
    
    // Does one of two main things: (a) user is already known to the system, it links the account/capabilities represented by the invitation to that user, (b) if the current user is not known to the system, this creates a new sharing user, and does the same kind of linking.
    // The user must be a sharing user. Will fail if the invitation has expired, or if the invitation has already been redeemed.
    // All user credentials parameters must be provided by serverCredentialParams.
    // Return code is SMServerConstants.rcCouldNotRedeemSharingInvitation when we could not redeem the sharing invitation.
    internal func redeemSharingInvitation(serverCredentialParams:[String:AnyObject],invitationCode:String, completion:((linkedOwningUserId: SMInternalUserId?, internalUserId:SMInternalUserId?, apiResult:SMServerAPIResult)->(Void))?) {
        
        var parameters = serverCredentialParams
        parameters[SMServerConstants.sharingInvitationCode] = invitationCode
        
        let serverOpURL = NSURL(string: self.serverURLString +
                        "/" + SMServerConstants.operationRedeemSharingInvitation)!
        
        SMServerNetworking.session.sendServerRequestTo(toURL: serverOpURL, withParameters: parameters) { (serverResponse:[String:AnyObject]?, error:NSError?) in
            
            var result = self.initialServerResponseProcessing(serverResponse, error: error)
            
            var internalUserId:SMInternalUserId?
            var linkedOwningUserId:SMInternalUserId?

            if nil == result.error || result.returnCode == SMServerConstants.rcUserOnSystem {
                internalUserId = serverResponse![SMServerConstants.internalUserId] as? String
                if nil == internalUserId {
                    result.error = Error.Create("Didn't get internalUserId back from server")
                }
                
                linkedOwningUserId = serverResponse![SMServerConstants.linkedOwningUserId] as? String
                if nil == linkedOwningUserId {
                    result.error = Error.Create("Didn't get linkedOwningUserId back from server")
                }
            }
            
            completion?(linkedOwningUserId:linkedOwningUserId, internalUserId: internalUserId, apiResult: result)
        }
    }
    
    // Look up the accounts that are shared with the current sharing user. serverCredentialParams is allowed as a parameter so that we can 
    internal func getLinkedAccountsForSharingUser(serverCredentialParams:[String:AnyObject]?,completion:((linkedAccounts:[SMLinkedAccount]?, apiResult:SMServerAPIResult)->(Void))?) {
        
        var userParams:[String:AnyObject]?
        if serverCredentialParams == nil {
            userParams = self.userDelegate.userCredentialParams
        }
        else {
            userParams = serverCredentialParams
        }
        
        Assert.If(nil == userParams, thenPrintThisString: "No user server params!")
        
        let serverOpURL = NSURL(string: self.serverURLString +
                        "/" + SMServerConstants.operationGetLinkedAccountsForSharingUser)!
        
        SMServerNetworking.session.sendServerRequestTo(toURL: serverOpURL, withParameters: userParams!) { (serverResponse:[String:AnyObject]?, error:NSError?) in
            
            var result = self.initialServerResponseProcessing(serverResponse, error: error)
            
            var linkedAccounts:[SMLinkedAccount]! = [SMLinkedAccount]()
            if nil == result.error {
                if let dictArray = serverResponse![SMServerConstants.resultLinkedAccountsKey] as? [[String:AnyObject]] {
                
                    Log.msg("dictArray: \(dictArray)")

                    for dict in dictArray {
                        if let internalUserId = dict[SMServerConstants.internalUserId] as? String,
                            let userName = dict[SMServerConstants.accountUserName] as? String,
                            let capabilities =  dict[SMServerConstants.accountCapabilities] as? [String],
                            let capabilityMask = SMSharingUserCapabilityMask(capabilityNameArray:capabilities)  {
                            
                            let linkedAccount = SMLinkedAccount(internalUserId: internalUserId, userName: userName, capabilityMask: capabilityMask)
                            linkedAccounts.append(linkedAccount)
                        }
                        else {
                            result.error = Error.Create("Didn't get expected dict element keys back from server: \(dict)")
                        }
                    }
                } else {
                    result.error = Error.Create("Didn't get array of dictionaries back from server: \(serverResponse![SMServerConstants.resultLinkedAccountsKey])")
                }
            }
            
            if linkedAccounts.count == 0 {
                linkedAccounts = nil
            }
            
            completion?(linkedAccounts: linkedAccounts, apiResult: result)
        }
    }
}
