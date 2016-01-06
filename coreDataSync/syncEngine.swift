//
//  syncEngine.swift
//  coreDataSync
//
//  Created by DARI on 1/5/16.
//  Copyright © 2016 DARI. All rights reserved.
//

import Foundation
import Alamofire
import CoreData
import SwiftyJSON

struct ParseData {
    let appID = "vxuUaJG3RUD8MavMhvrSSeMUSfEiiXfkR39v3n25"
    let clientKey = "HspimS3hD4XTcYQHHKYFTtwgdkX1gd7DGhuWbgk0"
    let restKey = "xbgkNA5BpbKiUgmPuiGyM7C7AQ1aMB9rcvzMK4cg"
    let version = 1
    let baseURL = "https://api.parse.com/"
}

enum SyncFlag: Int16 {
    case locally = 1, fromServer
}

class SyncCoreData {
    static let singletonInstance = SyncCoreData()
    
    lazy private var classesToSync = {
        return (UIApplication.sharedApplication().delegate as! AppDelegate).managedObjectModel.entitiesByName
    }()
    private var responseCount = [Bool]()
    private let appDelegate: AppDelegate!
    
    private var jsons = [String: JSON]()
    
    private var dateFormatter = NSDateFormatter()
    
    private var lastSyncDate: NSDate?
    private var startSyncDate: NSDate?
    
    init(){
        appDelegate = UIApplication.sharedApplication().delegate as! AppDelegate
        
    }
    
    func startSync(){
        startSyncDate = NSDate()
        setLastDateSynced()
        for (className, _) in classesToSync {
            getDataFromRemote(className, parameters: getDataFetchParameters())
        }
    }
    
    private func setLastDateSynced() {
        let fetchRequest = NSFetchRequest(entityName: "SyncInfo")
        let sortDesctiptor = NSSortDescriptor(key: "syncDate", ascending: false)
        fetchRequest.sortDescriptors = [sortDesctiptor]
        do {
            let result = try appDelegate.managedObjectContext.executeFetchRequest(fetchRequest) as! [SyncInfo]
            if let date = result.first?.syncDate {
                lastSyncDate = NSDate(timeIntervalSince1970: date)
            }
        } catch {
            print(error)
        }
    }
    
    private func getDataFromRemote(className: String, parameters:[String: String]?){
        
        let URl = createURLForClass(className)
        let headers = createHeaders()
        
        Alamofire.request(.GET, URl, parameters: parameters, headers: headers).responseJSON { (response) -> Void in
            switch response.result {
            case .Success(let data):
                let json = JSON(data)
                self.responseCount.append(true)
                if json["results"].count != 0 {
                    self.jsons[className] = json
                }
                print(self.responseCount.count)
                print(self.classesToSync.count)
                if self.responseCount.count == self.classesToSync.count {
                    self.processResponse()
                }
            case .Failure(let errors):
                print("Request failed with error for entity: \(className): \(errors)")
            }
        }
    }
    
    private func processResponse(){
        for (className, json) in jsons {
            for (_ ,object) in json["results"] {
                let name = object["name"].stringValue
                let fetchRequest = NSFetchRequest(entityName: className)
                let predicate = NSPredicate(format: "name = %@", name)
                fetchRequest.predicate = predicate
                fetchRequest.fetchLimit = 1
                do {
                    let result = try appDelegate.managedObjectContext.executeFetchRequest(fetchRequest) as! [Person]
                    if let person = result.first {
                        person.address = object["address"].stringValue
                        let updatedDate = self.dateUsingStringFromAPI(object["updatedAt"].stringValue)
                        person.updatedAt = updatedDate.timeIntervalSince1970
                    }else {
                        if let newManagedObject = self.createNSManagedObjectForClass(className){
                            let newObject = newManagedObject as! Person
                            newObject.name = name
                            newObject.address = object["address"].stringValue
                            newObject.createdAt = (self.dateUsingStringFromAPI(object["createdAt"].stringValue)).timeIntervalSince1970
                            newObject.updatedAt = (self.startSyncDate?.timeIntervalSince1970)!
                        }else {
                            print("error in creating object")
                        }
                    }
                } catch {
                    print(error)
                }
            }
        }
        do {
            try appDelegate.managedObjectContext.save()
        }catch {
            print(error)
        }
    }
    
    private func createNSManagedObjectForClass(className: String) -> NSManagedObject? {
        let entityDescription = NSEntityDescription.entityForName(className, inManagedObjectContext: appDelegate.managedObjectContext)
        if let entityDescription = entityDescription {
            let managedObject = NSManagedObject(entity: entityDescription, insertIntoManagedObjectContext: appDelegate.managedObjectContext)
            return managedObject
        }
        return nil
    }
    
    private func initializeDateFormatter() {
        self.dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        self.dateFormatter.timeZone = NSTimeZone(abbreviation: "GMT")
    }
    
    private func dateUsingStringFromAPI(dateString: String) -> NSDate {
        self.initializeDateFormatter()
        let dateStringWithoutMSAndTimeZone = dateString.substringWithRange(Range<String.Index>(start: dateString.startIndex, end: dateString.endIndex.advancedBy(-5)))
        return self.dateFormatter.dateFromString(dateStringWithoutMSAndTimeZone)!
    }
    
    private func dateUsingDateFromAPI(date: NSDate) -> String {
        self.initializeDateFormatter()
        var dateString = self.dateFormatter.stringFromDate(date)
        dateString = dateString.substringWithRange(Range<String.Index>(start: dateString.startIndex, end: dateString.endIndex.advancedBy(-1)))
        dateString = dateString.stringByAppendingFormat(".000Z")
        
        return dateString
    }
    
    private func getDataFetchParameters() -> [String: String]?{
        let dateFormatter = NSDateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.'999Z'"
        dateFormatter.timeZone = NSTimeZone(abbreviation: "GMT")
        if let _ = lastSyncDate {
            let parameterJsonString = String(format: "{\"updatedAt\":{\"$gte\":{\"__type\":\"Date\",\"iso\":\"%@\"}}}", dateFormatter.stringFromDate(lastSyncDate!))
            return ["where": parameterJsonString]
        }
        return nil
    }
    
    private func createHeaders() -> [String: String]? {
        let parseData = ParseData()
        return ["X-Parse-Application-Id" : parseData.appID , "X-Parse-REST-API-Key" : parseData.restKey]
    }
    //    private func getLastDateSyncedFromServer() -> NSDate? {
    //        return self.getSyncDate(false)
    //    }
    //
    //    private func getLastDateSyncedToServer() -> NSDate? {
    //        return self.getSyncDate(true)
    //    }
    //
    //    private func getSyncDate(isToServerFromLocal: Bool) -> NSDate? {
    //        let fetchRequest = NSFetchRequest(entityName: "syncInfo")
    //        let sortDesctiptor = NSSortDescriptor(key: "syncDate", ascending: false)
    //        let predicate = NSPredicate(format: "toOrFrom = %@", isToServerFromLocal)
    //        fetchRequest.sortDescriptors = [sortDesctiptor]
    //        fetchRequest.predicate = predicate
    //
    //        do {
    //            let result = try appDelegate.managedObjectContext.executeFetchRequest(fetchRequest) as! [SyncInfo]
    //            if let date = result.first?.syncDate {
    //                return NSDate(timeIntervalSince1970: date)
    //            }
    //        } catch {
    //            print(error)
    //        }
    //        return nil
    //   }
    
    private func getLastUpdatedDateOfClassInCoreData(className: String) -> NSDate?{
        let fetchRequest = NSFetchRequest(entityName: className)
        let sortDescriptor = NSSortDescriptor(key: "updatedAt", ascending: false)
        fetchRequest.sortDescriptors = [sortDescriptor]
        fetchRequest.fetchLimit = 1
        
        do {
            let result = try appDelegate.managedObjectContext.executeFetchRequest(fetchRequest) as! [Person]
            if let date = result.first?.updatedAt {
                return NSDate(timeIntervalSince1970: date)
            }
        } catch {
            print(error)
        }
        return nil
    }
    
    private func createURLForClass(className: String) -> String{
        var URL = String()
        let parseData = ParseData()
        URL = URL +  "\(parseData.baseURL)\(parseData.version)/classes/\(className)/"
        print(URL)
        return URL
    }
}