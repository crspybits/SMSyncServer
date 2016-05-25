//
//  SMUploadFileOperation.swift
//  SMSyncServer
//
//  Created by Christopher Prince on 4/9/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import CoreData
import SMCoreLib

class SMUploadFileOperation: SMUploadOperation {
    enum OperationStage : String {
        // There are two main server stages in uploads and upload-deletions

        // 1) Upload, when the operation needs to be queued in our server
        case ServerUpload
        
        // 2) When the file needs to be transferred to cloud storage or deleted from cloud storage
        case CloudStorage
    }
    
    // Don't access .internalOperationStage directly.
    var operationStage: OperationStage {
        set {
            self.internalOperationStage = newValue.rawValue
            CoreData.sessionNamed(SMCoreData.name).saveContext()
        }
        get {
            return OperationStage(rawValue: self.internalOperationStage!)!
        }
    }
    
    func convertToServerFile() -> SMServerFile {
        let localFile = self.localFile!
        Log.msg("SMUploadFileOperation: \(self)")
        
        let localVersion:Int = localFile.localVersion!.integerValue
        Log.msg("Local file version: \(localVersion)")
        
        let serverFile = SMServerFile(uuid: NSUUID(UUIDString: localFile.uuid!)!, remoteFileName: localFile.remoteFileName!, mimeType: localFile.mimeType!, appMetaData: localFile.appMetaData, version: localVersion)
        
        var deleted = false
        if let _ = self as? SMUploadDeletion {
            deleted = true
        }
        
        serverFile.deleted = deleted
        serverFile.localFile = localFile
        
        return serverFile
    }
    
    class func convertToServerFiles(uploadFiles:[SMUploadFileOperation]) -> [SMServerFile]? {
        var result = [SMServerFile]()
        
        for uploadFile in uploadFiles {
            result.append(uploadFile.convertToServerFile())
        }
        
        if result.count > 0 {
            return result
        }
        else {
            return nil
        }
    }
}
