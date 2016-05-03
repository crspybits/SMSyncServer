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

internal class SlaveData : NSObject, NSCoding {
    var sizeInBytes:Int32 = 0
    
    override init() {
        super.init()
    }
    
    internal required init?(coder aDecoder: NSCoder) {
        self.sizeInBytes = aDecoder.decodeInt32ForKey("sizeInBytes")
    }
    
    internal func encodeWithCoder(aCoder: NSCoder) {
        aCoder.encodeInt32(self.sizeInBytes, forKey: "sizeInBytes")
    }
}

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
        
        result.sortInPlace { (testCase1, testCase2) -> Bool in
            testCase1.testLabel < testCase2.testLabel
        }
        
        return result
    }
    
    weak var delegate:TestResultDelegate?
    
    // This is called exactly once.
    func createDataForSlave() -> NSData? {
        return nil
    }
    
    func master() {
        SMSyncServer.session.delegate = self
        self.isMaster = true
    }
    
    func slave(dataForSlave dataForSlave:NSData?) {
        SMSyncServer.session.delegate = self
        self.isMaster = false
    }
    
    func failTest(message:String? = #function) {
        Log.error("failTest: \(message)")
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
    
    func syncServerDownloadsComplete(downloadedFiles: [(NSURL, SMSyncAttributes)], acknowledgement: () -> ()) {
        failTest()
    }

    func syncServerClientShouldDeleteFiles(uuids: [NSUUID], acknowledgement: () -> ()) {
        failTest()
    }
    
    func syncServerModeChange(newMode:SMSyncServerMode) {
        failTest()
    }
    
    func syncServerEventOccurred(event:SMSyncServerEvent) {
        failTest()
    }
}
