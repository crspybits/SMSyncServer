//
//  TwoDeviceTestCase.swift
//  Tests
//
//  Created by Christopher Prince on 2/13/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
@testable import SMSyncServer
import SMCoreLib

// Must derive from NSObject because subclasses use RepeatingTimer
class TwoDeviceTestCase : NSObject, SMSyncServerDelegate {
    var testLabel:String!
    var isMaster:Bool = true
    var isSlave:Bool {
        return !isMaster
    }
    
    init(withTestLabel testLabel:String) {
        self.testLabel = testLabel
    }
    
    // Each test class needs to have this prefix, and be a subclass of TwoDeviceTestCase
    static let classPrefix = "SMTwoDeviceTest"
    
    class func testCases() -> [TwoDeviceTestCase] {
        var result = [TwoDeviceTestCase]()
        
        if let classes = ClassExtras.classesWithPrefix(classPrefix, andSubclassesOf: TwoDeviceTestCase.self) as? [AnyClass] {
            for aClass in classes {
                Log.msg("Class: \(aClass)")
                let obj = ClassExtras.createObjectFrom(aClass) as! TwoDeviceTestCase
                result.append(obj)
            }
        }
        
        return result
    }
    
    weak var delegate:TestResultDelegate?
    
    func master() {
        SMSyncServer.session.delegate = self
        self.isMaster = true
    }
    
    func slave() {
        SMSyncServer.session.delegate = self
        self.isMaster = false
    }
    
    func failTest(message:String? = __FUNCTION__) {
        let alert = UIAlertView(title: "Test Failed", message: message, delegate: nil, cancelButtonTitle: "OK")
        UserMessage.session().showAlert(alert, ofType: .Error)
        self.delegate?.running(self, gaveResult: .Failed)
    }
    
    func passTest() {
        self.delegate?.running(self, gaveResult: .Passed)
    }
    
    func assertIf(condition: Bool, thenFailAndGiveMessage message:String) {
        if condition {
            failTest(message)
        }
    }
    
    // The callee owns the localFile after this call completes. The file is temporary in the sense that it will not be backed up to iCloud, could be removed when the device or app is restarted, and should be moved to a more permanent location.
    func syncServerSingleFileDownloadComplete(temporaryLocalFile:NSURL, withFileAttributes attr: SMSyncAttributes) {
        failTest()
    }
    
    // Called at the end of all downloads, on a non-error condition, if at least one download carried out.
    func syncServerAllDownloadsComplete() {
        failTest()
    }
    
    // Called after a deletion indication has been received from the server. I.e., this file has been deleted on the server.
    func syncServerDeletionReceived(uuid uuid:NSUUID) {
        failTest()
    }
    
    // Called after a single file/item has been uploaded to the SyncServer. Transfer of the file to cloud storage hasn't yet occurred.
    func syncServerSingleUploadComplete(uuid uuid:NSUUID) {
        failTest()
    }
    
    // Called after deletion operations have been sent to the SyncServer. All pending deletion operations are sent as a group. Deletion of the file from cloud storage hasn't yet occurred.
    func syncServerDeletionsSent(uuids:[NSUUID]) {
        failTest()
    }
    
    // This is called after the server has finished performing the transfers of files to cloud storage/deletions in cloud storage. numberOperations includes upload and deletion operations.
    func syncServerCommitComplete(numberOperations numberOperations:Int?) {
        failTest()
    }
    
    // This reports recovery progress from recoverable errors. Mostly useful for testing and debugging.
    func syncServerRecovery(progress:SMSyncServerRecovery) {
        failTest()
    }
    
    func syncServerError(error:NSError) {
        failTest()
    }
    
    func syncServerNoFilesToDownload() {
        failTest()
    }
}
