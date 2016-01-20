//
//  MainPageVC.swift
//  NetDb
//
//  Created by Christopher Prince on 12/9/15.
//  Copyright © 2015 Spastic Muffin, LLC. All rights reserved.
//

// Provides access to the files stored by the app, and enables navigation to Settings.

import Foundation
import UIKit
import SMCoreLib

class MainPageVC : UIViewController {
    static let FileNameIndex = SMPersistItemInt(name: "MainPageVC.FileNameIndex", initialIntValue: 0, persistType: .UserDefaults)
    
    let cellIdentifier = "cellFile"
    let tableView = UITableView()
    var coreDataSource:CoreDataSource!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.coreDataSource = CoreDataSource(delegate: self)
        self.coreDataSource.fetchData()
        
        let settingsButton = UIBarButtonItem(title: "Settings", style: .Plain, target: self, action: "settingsButtonAction")
        let addButton = UIBarButtonItem(title: "Add", style: .Plain, target: self, action: "addButtonAction")
        self.navigationItem.rightBarButtonItems = [settingsButton, addButton]
        
        self.tableView.frame = self.view.frame
        self.view.addSubview(self.tableView)
        self.tableView.registerClass(UITableViewCell.self, forCellReuseIdentifier: self.cellIdentifier)
        self.tableView.dataSource = self
        self.tableView.delegate = self
    }
        
    func settingsButtonAction() {
        let settings = Settings()
        self.navigationController!.pushViewController(settings, animated: true)
    }
    
    func addButtonAction() {
        self.makeNewFile()
    }
    
    // The new local file meta info is added into Core Data.
    func makeNewFile() {
        let file = AppFile.newObjectAndMakeUUID(true)
        
        let fileIndex = MainPageVC.FileNameIndex.intValue
        MainPageVC.FileNameIndex.intValue++
        file.fileName = "file\(fileIndex)"
        
        let path = FileStorage.pathToItem(file.fileName)
        NSFileManager.defaultManager().createFileAtPath(path, contents: nil, attributes: nil)

        CoreData.sessionNamed(CoreDataTests.name).saveContext()
    }
}

extension MainPageVC : UITableViewDelegate, UITableViewDataSource {

    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Int(self.coreDataSource.numberOfRowsInSection(0))
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier(self.cellIdentifier, forIndexPath: indexPath)
        
        let file = self.coreDataSource.objectAtIndexPath(indexPath) as! AppFile
        cell.textLabel!.text = file.fileName
        
        return cell
    }
    
    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        tableView.deselectRowAtIndexPath(indexPath, animated: true)
        
        let fileViewer = FileViewerVC()
        let file = self.coreDataSource.objectAtIndexPath(indexPath) as! AppFile
        fileViewer.file = file
        self.navigationController!.pushViewController(fileViewer, animated: true)
    }
}

extension MainPageVC : CoreDataSourceDelegate {
    func coreDataSourceFetchRequest(cds: CoreDataSource) -> NSFetchRequest {
        return AppFile.fetchRequestForAllObjectsInContext(nil)
    }
    
    func coreDataSourceContext(cds: CoreDataSource) -> NSManagedObjectContext {
        return CoreData.sessionNamed(CoreDataTests.name).context
    }
    
    func coreDataSource(cds: CoreDataSource!, objectWasDeleted indexPathOfDeletedObject: NSIndexPath!) {
        self.tableView.reloadData()
    }
    
    func coreDataSource(cds: CoreDataSource!, objectWasInserted indexPathOfInsertedObject: NSIndexPath!) {
        self.tableView.reloadData()
    }
    
    func coreDataSource(cds: CoreDataSource!, objectWasUpdated indexPathOfUpdatedObject: NSIndexPath!) {
        self.tableView.reloadData()
    }
}


