//
//  ViewController.swift
//  coreDataSync
//
//  Created by DARI on 1/4/16.
//  Copyright © 2016 DARI. All rights reserved.
//

import UIKit
import CoreData

class ViewController: UIViewController {
    
    @IBOutlet weak var tableView: UITableView!
    
    lazy var fetchedResultsController: NSFetchedResultsController = {
        let appDelegate = UIApplication.sharedApplication().delegate as! AppDelegate
        let fetchRequest = NSFetchRequest(entityName: "Person")
        let sortDescriptor = NSSortDescriptor(key: "createdAt", ascending: true)
        let predicate = NSPredicate(format: "delete = %@", false)
        fetchRequest.sortDescriptors = [sortDescriptor]
        fetchRequest.predicate = predicate
        
        let fetchedResultController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: appDelegate.managedObjectContext, sectionNameKeyPath: nil, cacheName: nil)
        
        fetchedResultController.delegate = self
        return fetchedResultController
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        SyncCoreData.singletonInstance.startSync()
        do {
            try self.fetchedResultsController.performFetch()
        } catch {
            print(error)
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if segue.identifier == "updatePersonSegue" {
            let viewController = segue.destinationViewController as! UpdateViewController
            let indexPath = self.tableView.indexPathForSelectedRow
           
            let recordToUpdate = self.fetchedResultsController.objectAtIndexPath(indexPath!) as! Person
            viewController.person = recordToUpdate
        }
    }
    @IBAction func syncDataPressed(sender: AnyObject) {
        SyncCoreData.singletonInstance.startSync()
    }
}

//MARK: - Core data
extension ViewController {
    
    private func saveManagedObjectContext() {
        let appDelegate = UIApplication.sharedApplication().delegate as! AppDelegate
        appDelegate.saveContext()
//        let managedObjectContext = appDelegate.managedObjectContext
//        managedObjectContext.
    }
    
}

//MARK: -FetchedResultsControllerDelegate
extension ViewController: NSFetchedResultsControllerDelegate {
    
    func controllerWillChangeContent(controller: NSFetchedResultsController) {
        tableView.beginUpdates()
    }
    
    func controller(controller: NSFetchedResultsController, didChangeObject anObject: AnyObject, atIndexPath indexPath: NSIndexPath?, forChangeType type: NSFetchedResultsChangeType, newIndexPath: NSIndexPath?) {
        switch type {
        case .Delete:
            if let deleteIndexPath = indexPath {
                tableView.deleteRowsAtIndexPaths([deleteIndexPath], withRowAnimation: .Fade)
            }
        case .Insert:
            if let newIndexPath = newIndexPath {
                tableView.insertRowsAtIndexPaths([newIndexPath], withRowAnimation: .Fade)
            }
        case .Update:
            if let updateIndexPath = indexPath {
                let cell = tableView.cellForRowAtIndexPath(updateIndexPath)
                configureCell(cell!, indexPath: updateIndexPath)
            }
        case .Move:
            if let moveIndexPath = indexPath {
                tableView.deleteRowsAtIndexPaths([moveIndexPath], withRowAnimation: .Fade)
            }
            if let newIndexPath = newIndexPath {
                tableView.insertRowsAtIndexPaths([newIndexPath], withRowAnimation: .Fade)
            }
        }
        
    }
    
    func controllerDidChangeContent(controller: NSFetchedResultsController) {
        tableView.endUpdates()
        self.saveManagedObjectContext()
    }
    
}
//MARK: Tableview datasource and delegate
extension ViewController: UITableViewDelegate {
    func tableView(tableView: UITableView, didDeselectRowAtIndexPath indexPath: NSIndexPath) {
        tableView.deselectRowAtIndexPath(indexPath, animated: true)
    }
}

extension ViewController: UITableViewDataSource {
    //MARK: Mandatory funcs
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if let sections = self.fetchedResultsController.sections {
            let sectionInfo = sections[section]
            return sectionInfo.numberOfObjects
        }
        return 0
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("reuseCell", forIndexPath: indexPath)
        configureCell(cell, indexPath: indexPath)
        return cell
    }
    
    //MARK: Optional funcs
    func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        return true
    }
    
    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        if let sections = self.fetchedResultsController.sections {
            return sections.count
        }
        return 0
    }
    
    func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        if editingStyle == UITableViewCellEditingStyle.Delete {
            let deletingRecord = fetchedResultsController.objectAtIndexPath(indexPath) as! Person
            //self.fetchedResultsController.managedObjectContext.deleteObject(deletingRecord)
            deletingRecord.delete = true
        }
    }
    
    //MARK: Custom functions for support
    private func configureCell(cell: UITableViewCell, indexPath: NSIndexPath){
        let Object = self.fetchedResultsController.objectAtIndexPath(indexPath) as! Person
        if let name = Object.name {
            cell.textLabel?.text = name
        }
        if let address = Object.address {
            cell.detailTextLabel?.text = address
        }
    }
}


