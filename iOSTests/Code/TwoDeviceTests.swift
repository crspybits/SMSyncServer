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

enum TestResult {
    case Running
    case Passed
    case Failed
}

class TwoDeviceTests : UIViewController {

    // Persistent array of UIColor's
    let testResults = SMPersistItemArray(name: "TwoDeviceTests.testResults", initialArrayValue: [], persistType: .UserDefaults)
    
    var currentTest:Int = 0
    let cellIdentifier = "CellIdentifier"
    let switchControl = UISwitch()
    let multiPeer = SMMultiPeer()
    var weAreMaster:Bool {
        return !self.switchControl.on
    }
    
    private var tableRowData:[TwoDeviceTestCase]!
    
    var tableView:UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.tableRowData = TwoDeviceTestCase.testCases()
        
        if self.tableRowData.count != testResults.arrayValue.count {
            testResults.arrayValue = []
            let noColor = UIColor.whiteColor()
            for _ in 1...(self.tableRowData.count) {
                testResults.arrayValue.addObject(noColor)
            }
        }
        
        self.createViews()
        self.multiPeer.delegate = self
    }
    
    func setTest(testNumber:Int, testResult:TestResult) {
        var color:UIColor!
        switch testResult {
            case .Running:
                color = UIColor.yellowColor()
            
            case .Failed:
                color = UIColor.redColor()
            
            case .Passed:
                color = UIColor.greenColor()
        }
        
        self.testResults.arrayValue[testNumber] = color
        self.tableView.reloadData()
    }

    func createViews() {
        self.correctStartingPosition()
        
        self.view.backgroundColor = UIColor.whiteColor()
        self.title = "Two Device Tests"
        
        let leftLabel = UILabel()
        leftLabel.text = "Master"
        leftLabel.sizeToFit()
        let rightLabel = UILabel()
        rightLabel.text = "Slave"
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
        
        self.tableView = UITableView()
        self.tableView.frame = CGRect(x: 0, y: switchView.frameMaxY + verticalPadding, width: self.view.frameWidth, height: self.view.frameHeight-switchView.frameMaxY)
        self.view.addSubview(self.tableView)
        self.tableView.delegate = self
        self.tableView.dataSource = self
        
        self.tableView.registerClass(UITableViewCell.self, forCellReuseIdentifier: self.cellIdentifier)
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
        cell.backgroundColor = self.testResults.arrayValue[indexPath.row] as? UIColor
        return cell
    }
    
    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        tableView.deselectRowAtIndexPath(indexPath, animated: true)
        
        let rowData = self.tableRowData[indexPath.row]
        rowData.delegate = self
        self.currentTest = indexPath.row
        if self.weAreMaster {
            if self.sendTestNumberToSlave(self.currentTest) {
                self.setTest(self.currentTest, testResult: .Running)
                rowData.master()
            }
        }
    }
}

extension TwoDeviceTests : SMMultiPeerDelegate {
    func didReceive(string string:String, fromPeer peer:String) {
        Log.msg("didReceive: " + string + " from peer: " + peer)
        let testNumber = Int(string)
        Assert.If(self.weAreMaster, thenPrintThisString: "Yikes: We are the master!")
        let rowData = self.tableRowData[testNumber!]
        rowData.delegate = self
        self.currentTest = testNumber!
        self.setTest(self.currentTest, testResult: .Running)
        rowData.slave()
    }
    
    // Sending a single integer to the slave device, the row number of the data in self.tableRowData, encoded as a string. i.e., the test number.
    func sendTestNumberToSlave(testNumber:Int) -> Bool {
        return self.multiPeer.sendString(String(testNumber))
    }
}

extension TwoDeviceTests : TestResultDelegate {
    func running(test:TwoDeviceTestCase, gaveResult result:TestResult) {
        self.setTest(self.currentTest, testResult: result)
    }
}

protocol TestResultDelegate : class {
    func running(test:TwoDeviceTestCase, gaveResult:TestResult)
}

