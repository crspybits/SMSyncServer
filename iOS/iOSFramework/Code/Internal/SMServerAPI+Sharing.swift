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
    // Must have a signed in owning user. Doesn't require a lock. The capabilities must not be empty.
    // capabilities is an optional value only to allow for error case testing on the server. In production builds, it *must* not be nil.
    internal func createSharingInvitation(capabilities capabilities:SMSharingUserCapabilityMask?, completion:((invitationCode:String?, apiResult:SMServerAPIResult)->(Void))?) {
        
        var capabilitiesStringArray:[String]?
        if capabilities != nil {
            capabilitiesStringArray = capabilities!.sendable
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
                completion?(authorizationCode: nil,
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
    
    // Redeem an existing sharing invitation. This binds the invitation to a specific sharing user account.
    internal func redeemSharingInvitation(invitationCode invitationCode:String, sharingUser:SMSharingUser, completion:((apiResult:SMServerAPIResult)->(Void))?) {

        let userParams = self.userDelegate.userCredentialParams
        Assert.If(nil == userParams, thenPrintThisString: "No user server params!")
        
        var parameters = userParams!
    
        parameters[SMServerConstants.sharingUserAccountKey] = sharingUser.sharingUserAccountDict()
        
        let serverOpURL = NSURL(string: self.serverURLString +
                        "/" + SMServerConstants.operationRedeemSharingInvitation)!
        
        SMServerNetworking.session.sendServerRequestTo(toURL: serverOpURL, withParameters: parameters) { (serverResponse:[String:AnyObject]?, error:NSError?) in
            
            let result = self.initialServerResponseProcessing(serverResponse, error: error)
            completion?(apiResult: result)
        }
    }
}
