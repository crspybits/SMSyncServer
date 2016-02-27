//
//  SMSyncServerModes.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 2/26/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import SMCoreLib

public enum SMRunningMode : Int {
    // MARK: Upload modes
    
    case Upload
    
    // Edge case between modes.
    case BetweenUploadAndOutBoundTransfer

    case OutboundTransfer
    
    // MARK: Download modes
    
    case InboundTransfer
    case Download
}

// The SMModeType distinction doesn't change operation of the SMSyncServer, but is for debugging/testing purposes.
public enum SMModeType : Int {
    case Operating // non-recovery; normal operation.
    case Recovery
}

// Modes are general temporally extended states of operation. Modes span both upload and download operations because: (a) SMSync enforces a rule where we only do operations sequentially (e.g., we can't have an upload and a download happening at the same time), (b) so that the syncServerRecovery delegate method can report using a single enum type, and (c) there are some shared modes across upload and download (i.e., Normal, and NonRecoverableError).
// Aside from the Normal and NonRecoverableError modes, the SMSyncServer client should not depend on the specifics of the modes. I.e., these first two modes are for helping operation of the client/app. The remaining modes reflect internal structure of the SMSyncServer itself and, while they can be useful for debugging/testing, they should only generally be relied on.
public enum SMClientMode {
    // Non-error, non-recovery operating condition, not currently downloading or uploading.
    case Idle

    case Running(SMRunningMode, SMModeType)
    
    /* An error that SMSyncServer couldn't recover from. It's up to the client app to deal with this.
    This error can occur in one of two types of circumstances:
    1) There was a client API error in which the user of the SMSyncServer (e.g., caller of this interface) made an error (e.g., using the same cloud file name with two different UUID's).
    2) There was an error that, after internal SMSyncServer recovery attempts, could not be dealt with.
    */
    case NonRecoverableError(NSError)
}

internal class SMClientModeWrapper : NSObject, NSCoding
{
    var mode:SMClientMode
    init(withMode mode:SMClientMode) {
        self.mode = mode
        super.init()
    }

    @objc required init(coder aDecoder: NSCoder) {
        let name = aDecoder.decodeObjectForKey("name") as! String
        
        switch name {
        case "Idle":
            self.mode = .Idle

        case "NonRecoverableError":
            let error = aDecoder.decodeObjectForKey("error") as! NSError
            self.mode = .NonRecoverableError(error)

        case "Running":
            let type = SMModeType(rawValue: Int(aDecoder.decodeInt32ForKey("modeType")))!
            let runningMode = SMRunningMode(rawValue: Int(aDecoder.decodeInt32ForKey("runningMode")))!
            self.mode = .Running(runningMode, type)
        
        default:
            Assert.badMojo(alwaysPrintThisString: "Should not get here")
            self.mode = .Idle // Without this, get compiler error.
        }
        
        super.init()
    }

    @objc func encodeWithCoder(aCoder: NSCoder) {
        var name:String!
        var error:NSError?
        var modeType:SMModeType?
        var runningMode:SMRunningMode?
        
        switch self.mode {
        case .Idle:
            name = "Idle"

        case .NonRecoverableError(let err):
            name = "NonRecoverableError"
            error = err

        case .Running(let runMode, let type):
            name = "Running"
            runningMode = runMode
            modeType = type
        }
        
        aCoder.encodeObject(name, forKey: "name")
        if modeType != nil {
            aCoder.encodeInt(Int32(modeType!.rawValue), forKey: "modeType")
            aCoder.encodeInt(Int32(runningMode!.rawValue), forKey: "runningMode")
        }
        
        if error != nil {
            aCoder.encodeObject(error, forKey: "error")
        }
    }
    
    class func convertToRecovery(mode:SMClientMode) -> SMClientMode {
        switch mode {
        case .Running(let runningMode, _):
            return .Running(runningMode, .Recovery)
            
        default:
            Assert.badMojo(alwaysPrintThisString: "Should not get here")
            return .Idle // Avoiding compiler complaints.
        }
    }
}
