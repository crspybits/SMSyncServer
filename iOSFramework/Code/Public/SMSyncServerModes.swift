//
//  SMSyncServerModes.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 2/26/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import SMCoreLib

public enum SMSyncServerMode {
    // The SMSyncServer client is not performing any operation.
    case Idle

    // SMSyncServer client is performing an operation, e.g., downloading or uploading.
    case Synchronizing
    
    // This is not an error, but indicates a loss of network connection. Normal operation will resume once the network is connected again.
    case NetworkNotConnected
    
    // The modes below are errors that the SMSyncServer couldn't recover from. It's up to the client app to deal with these.
    
    // There was a client API error in which the user of the SMSyncServer (e.g., caller of this interface) made an error (e.g., using the same cloud file name with two different UUID's).
    case ClientAPIError(NSError)
    
    // There was an error that, after internal SMSyncServer recovery attempts, could not be dealt with.
    case NonRecoverableError(NSError)
    
    // An error within the SMSyncServer framework. Ooops. Please report this to the SMSyncServer developers!
    case InternalError(NSError)
}

internal class SMSyncServerModeWrapper : NSObject, NSCoding
{
    var mode:SMSyncServerMode
    init(withMode mode:SMSyncServerMode) {
        self.mode = mode
        super.init()
    }

    @objc required init(coder aDecoder: NSCoder) {
        let name = aDecoder.decodeObjectForKey("name") as! String
        
        switch name {
        case "Idle":
            self.mode = .Idle
            
        case "Synchronizing":
            self.mode = .Synchronizing
            
        case "NetworkNotConnected":
            self.mode = .NetworkNotConnected
            
        case "NonRecoverableError":
            let error = aDecoder.decodeObjectForKey("error") as! NSError
            self.mode = .NonRecoverableError(error)

        case "ClientAPIError":
            let error = aDecoder.decodeObjectForKey("error") as! NSError
            self.mode = .ClientAPIError(error)
            
        case "InternalError":
            let error = aDecoder.decodeObjectForKey("error") as! NSError
            self.mode = .InternalError(error)
        
        default:
            Assert.badMojo(alwaysPrintThisString: "Should not get here")
            self.mode = .Idle // Without this, get compiler error.
        }
        
        super.init()
    }

    @objc func encodeWithCoder(aCoder: NSCoder) {
        var name:String!
        var error:NSError?
        
        switch self.mode {
        case .Idle:
            name = "Idle"
        
        case .Synchronizing:
            name = "Synchronizing"
            
        case .NetworkNotConnected:
            name = "NetworkNotConnected"
            
        case .NonRecoverableError(let err):
            name = "NonRecoverableError"
            error = err
            
        case .ClientAPIError(let err):
            name = "ClientAPIError"
            error = err
            
        case .InternalError(let err):
            name = "InternalError"
            error = err
        }
        
        aCoder.encodeObject(name, forKey: "name")
        
        if error != nil {
            aCoder.encodeObject(error, forKey: "error")
        }
    }
}
