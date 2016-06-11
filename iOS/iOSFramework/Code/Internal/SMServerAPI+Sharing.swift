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
    // Must have a signed in owning user.
    internal func createSharingInvitation(capabilities:SMSharingUserCapabilityMask, completion:((authorizationCode:String?, apiResult:SMServerAPIResult)->(Void))?) {
        
        let userParams = self.userDelegate.userCredentialParams
        Assert.If(nil == userParams, thenPrintThisString: "No user server params!")
        
        var parameters = userParams!
        parameters[SMServerConstants.userCapabilities] = capabilities.sendable
        
        let serverOpURL = NSURL(string: self.serverURLString +
                        "/" + SMServerConstants.operationCreateSharingInvitation)!
        
        SMServerNetworking.session.sendServerRequestTo(toURL: serverOpURL, withParameters: parameters) { (serverResponse:[String:AnyObject]?, error:NSError?) in
            
            var result = self.initialServerResponseProcessing(serverResponse, error: error)
            
            var authorizationCode:String?
            if nil == result.error {
                authorizationCode = serverResponse![SMServerConstants.internalUserId] as? String
                if nil == authorizationCode {
                    result.error = Error.Create("Didn't get an Authorization Code back from server")
                }
            }
            
            completion?(authorizationCode: authorizationCode, apiResult: result)
        }
    }
}
