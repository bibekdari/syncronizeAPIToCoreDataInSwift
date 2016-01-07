//
//  AddViewController.swift
//  coreDataSync
//
//  Created by DARI on 1/4/16.
//  Copyright © 2016 DARI. All rights reserved.
//

import UIKit
import CoreData

class AddViewController: UIViewController {
    
    @IBOutlet weak var textFieldName: UITextField!
    @IBOutlet weak var textFieldAddress: UITextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Do any additional setup after loading the view.
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    @IBAction func cancelButtonPressed(sender: AnyObject) {
        navigationController?.popViewControllerAnimated(true)

    }
    @IBAction func saveButtonPressed(sender: AnyObject) {
        let name = textFieldName.text!
        let address = textFieldAddress.text!
        if !(name.isEmpty || address.isEmpty) {
            let appDelegate = UIApplication.sharedApplication().delegate as! AppDelegate
            
            let entityDesc = NSEntityDescription.entityForName("Person", inManagedObjectContext: appDelegate.managedObjectContext)
            
            let newPerson = Person(entity: entityDesc!, insertIntoManagedObjectContext: appDelegate.managedObjectContext)
            
            newPerson.name = name
            newPerson.address = address
            newPerson.createdAt = NSDate()
            newPerson.updatedAt = NSDate()
            
            navigationController?.popViewControllerAnimated(true)

        }
        else
        {
            showAlert("Warning", message: "Either name or address is empty.", actionTitle: "OK")
        }
    }
    
    private func showAlert(title: String, message: String, actionTitle: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .Alert)
        let okAction = UIAlertAction(title: actionTitle, style: .Default, handler: nil)
        alertController.addAction(okAction)
        presentViewController(alertController, animated: true, completion: nil)
    }
    
    /*
    // MARK: - Navigation
    
    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
    // Get the new view controller using segue.destinationViewController.
    // Pass the selected object to the new view controller.
    }
    */
    
}
