//
//  TwoDeviceTests.swift
//  Tests
//
//  Created by Christopher Prince on 2/7/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import UIKit
import SMCoreLib
@testable import SMSyncServer

class TwoDeviceTests : UIViewController {
    let cellIdentifier = "CellIdentifier"
    let switchControl = UISwitch()
    var weAreDevice1:Bool {
        return self.switchControl.on
    }
    
    private var tableRowData:[TwoDeviceTestInstance]!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.createTestDataRows()
        self.createViews()
    }

    func createViews() {
        self.correctStartingPosition()
        
        self.view.backgroundColor = UIColor.whiteColor()
        self.title = "Two Device Tests"
        
        let leftLabel = UILabel()
        leftLabel.text = "Device 1"
        leftLabel.sizeToFit()
        let rightLabel = UILabel()
        rightLabel.text = "Device 2"
        rightLabel.sizeToFit()

        switchControl.sizeToFit()
        
        let horizontalPadding:CGFloat = 10
        let verticalPadding:CGFloat = 10

        let verticalPositionOfSwitch:CGFloat = 5
        
        let switchView = UIView()
        switchView.addSubview(leftLabel)
        switchView.addSubview(switchControl)
        switchView.addSubview(rightLabel)
        switchControl.frameX = leftLabel.frameMaxX + horizontalPadding
        rightLabel.frameX = switchControl.frameMaxX + horizontalPadding
        self.view.addSubview(switchView)
        switchView.frameWidth = rightLabel.frameMaxX
        switchView.frameHeight = max(leftLabel.frameHeight, switchControl.frameHeight)
        rightLabel.centerVerticallyInSuperview()
        leftLabel.centerVerticallyInSuperview()
        switchControl.centerVerticallyInSuperview()
        
        switchView.centerHorizontallyInSuperview()
        switchView.frameY = verticalPositionOfSwitch
        
        let tableView = UITableView()
        tableView.frame = CGRect(x: 0, y: switchView.frameMaxY + verticalPadding, width: self.view.frameWidth, height: self.view.frameHeight-switchView.frameMaxY)
        self.view.addSubview(tableView)
        tableView.delegate = self
        tableView.dataSource = self
        
        tableView.registerClass(UITableViewCell.self, forCellReuseIdentifier: self.cellIdentifier)
    }
}

extension TwoDeviceTests : UITableViewDelegate, UITableViewDataSource {
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.tableRowData.count
    }

    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier(self.cellIdentifier, forIndexPath: indexPath)
        let rowData = self.tableRowData[indexPath.row]
        cell.textLabel!.text = rowData.testLabel
        return cell
    }
    
    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        tableView.deselectRowAtIndexPath(indexPath, animated: true)
        
        let rowData = self.tableRowData[indexPath.row]
        
        if self.weAreDevice1 {
            rowData.device1()
        }
        else {
            rowData.device2()
        }
    }
}

extension TwoDeviceTests /* Create Test Data Array */ {
    func createTestDataRows() {
        self.tableRowData = [
            TestThatServerHasNewFileWorks()
        ]
    }
}

class TwoDeviceTestInstance : SMSyncServerDelegate {
    var testLabel:String!
    
    init(withTestLabel testLabel:String) {
        self.testLabel = testLabel
    }
    
    func device1() {
    }
    
    func device2() {
    }
    
    // The callee owns the localFile after this call completes. The file is temporary in the sense that it will not be backed up to iCloud, could be removed when the device or app is restarted, and should be moved to a more permanent location.
    func syncServerSingleFileDownloadComplete(temporaryLocalFile:NSURL, withFileAttributes attr: SMSyncAttributes) {
        Assert.badMojo(alwaysPrintThisString: "Not expected")
    }
    
    // Called at the end of all downloads, on a non-error condition, if at least one download carried out.
    func syncServerAllDownloadsComplete() {
        Assert.badMojo(alwaysPrintThisString: "Not expected")
    }
    
    // Called after a deletion indication has been received from the server. I.e., this file has been deleted on the server.
    func syncServerDeletionReceived(uuid uuid:NSUUID) {
        Assert.badMojo(alwaysPrintThisString: "Not expected")
    }
    
    // Called after a single file/item has been uploaded to the SyncServer. Transfer of the file to cloud storage hasn't yet occurred.
    func syncServerSingleUploadComplete(uuid uuid:NSUUID) {
        Assert.badMojo(alwaysPrintThisString: "Not expected")
    }
    
    // Called after deletion operations have been sent to the SyncServer. All pending deletion operations are sent as a group. Deletion of the file from cloud storage hasn't yet occurred.
    func syncServerDeletionsSent(uuids:[NSUUID]) {
        Assert.badMojo(alwaysPrintThisString: "Not expected")
    }
    
    // This is called after the server has finished performing the transfers of files to cloud storage/deletions in cloud storage. numberOperations includes upload and deletion operations.
    func syncServerCommitComplete(numberOperations numberOperations:Int?) {
        Assert.badMojo(alwaysPrintThisString: "Not expected")
    }
    
    // This reports recovery progress from recoverable errors. Mostly useful for testing and debugging.
    func syncServerRecovery(progress:SMSyncServerRecovery) {
        Assert.badMojo(alwaysPrintThisString: "Not expected")
    }
    
    func syncServerError(error:NSError) {
        Assert.badMojo(alwaysPrintThisString: "Not expected")
    }
    
    func syncServerNoFilesToDownload() {
        Assert.badMojo(alwaysPrintThisString: "Not expected")
    }
}

// TODO: Two clients signed on to the server, with different Google Drive Id's.

// Server has a file which doesn't yet exist on app/client.
private class TestThatServerHasNewFileWorks : TwoDeviceTestInstance {

    init() {
        super.init(withTestLabel: "Server has new file")
        TestBasics.session.failure = {
            Assert.badMojo(alwaysPrintThisString: "Test failed")
        }
    }
    
    var uploader:Bool = false
    var createFile:(file:AppFile, fileSizeInBytes:Int)!
    var uuidString:String! {
        return self.createFile.file.uuid!
    }
    var fileUUID: NSUUID {
        return NSUUID(UUIDString: self.uuidString)!
    }
    
    var numberUploads:Int = 0
    var numberDownloads:Int = 0
    var device2Checks:Int = 0
    
    // Device2
    var timer:RepeatingTimer!

    // Upload file to server.
    override func device1() {
        self.uploader = true
        
        let fileName = "ServerHasNewFile"
        self.createFile = TestBasics.session.createFile(withName: fileName)

        let fileAttributes = SMSyncAttributes(withUUID: self.fileUUID, mimeType: "text/plain", andRemoteFileName: fileName)
    
        SMSyncServer.session.uploadImmutableFile(self.createFile.file.url(), withFileAttributes: fileAttributes)
        SMSyncServer.session.commit()
    }
    
    override func syncServerSingleUploadComplete(uuid uuid:NSUUID) {
        if !self.uploader {
            Assert.badMojo(alwaysPrintThisString: "Not expected!")
        }
        
        self.numberUploads += 1
        
        Assert.If(self.numberUploads > 1, thenPrintThisString: "More than one upload")
        Assert.If(uuid.UUIDString == self.uuidString, thenPrintThisString: "Unexpected UUUID")
    }
    
    override func syncServerCommitComplete(numberOperations numberOperations: Int?) {
        if !self.uploader {
            Assert.badMojo(alwaysPrintThisString: "Not expected!")
        }
        
        Assert.If(numberUploads != 1, thenPrintThisString: "More than one upload")
        TestBasics.session.checkFileSize(self.uuidString, size: self.createFile.fileSizeInBytes) {
            let fileAttr = SMSyncServer.session.fileStatus(self.fileUUID)
            Assert.If(fileAttr == nil, thenPrintThisString: "No file attr")
            Assert.If(fileAttr!.deleted!, thenPrintThisString: "File was deleted")
        }
    }
    
    // Receive new file.
    override func device2() {
        self.uploader = false
        
        self.timer = RepeatingTimer(interval: 10.0, selector: "device2Timer", andTarget: self)
        self.timer.start()
    }
    
    func device2Timer() {
        self.device2Checks += 1
        if self.device2Checks > 10 {
            Assert.badMojo(alwaysPrintThisString: "Too many checks")
        }
        
        SMDownloadFiles.session.checkForDownloads()
    }
    
    override func syncServerSingleFileDownloadComplete(temporaryLocalFile:NSURL, withFileAttributes attr: SMSyncAttributes) {
        if self.uploader {
            Assert.badMojo(alwaysPrintThisString: "Not expected!")
        }
        
        self.numberDownloads += 1
        
        Assert.If(self.numberDownloads > 1, thenPrintThisString: "More than one download")
    }

    override func syncServerAllDownloadsComplete() {
        if self.uploader {
            Assert.badMojo(alwaysPrintThisString: "Not expected!")
        }
        
        self.timer.cancel()
    }
}

// TODO: Server has a single file which is an updated version of that on app/client.



