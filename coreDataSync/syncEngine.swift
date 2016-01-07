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
import SystemConfiguration

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
    
    private let appDelegate: AppDelegate!
    private var syncingStatus = false
    private var responseCount = [Bool]()
    private var syncAction = [Bool]()
    private var pullResponseJsons = [String: JSON]()
    private var pushRequestObjects = [NSManagedObject]()
    private var dateFormatter = NSDateFormatter()
    private var lastSyncDate: NSDate?
    private var startSyncDate: NSDate?
    
    
    init(){
        appDelegate = UIApplication.sharedApplication().delegate as! AppDelegate
    }
    
    func isConnectedToNetwork() -> Bool {
        var zeroAddress = sockaddr_in()
        zeroAddress.sin_len = UInt8(sizeofValue(zeroAddress))
        zeroAddress.sin_family = sa_family_t(AF_INET)
        let defaultRouteReachability = withUnsafePointer(&zeroAddress) {
            SCNetworkReachabilityCreateWithAddress(nil, UnsafePointer($0))
        }
        var flags = SCNetworkReachabilityFlags()
        if !SCNetworkReachabilityGetFlags(defaultRouteReachability!, &flags) {
            return false
        }
        let isReachable = (flags.rawValue & UInt32(kSCNetworkFlagsReachable)) != 0
        let needsConnection = (flags.rawValue & UInt32(kSCNetworkFlagsConnectionRequired)) != 0
        return (isReachable && !needsConnection)
    }
    
    func startSync(){
        if !self.syncingStatus && self.isConnectedToNetwork() {
            self.resetAllVariables()
            self.setLastDateSynced()
            
            var dataArray = [AnyObject]()
            
            for (className, _) in self.classesToSync {
                self.getDataFromRemote(className, parameters: getDataFetchParameters())
                
                dataArray = self.dataToPushToRemote(className, dataArray: dataArray)
            }
            self.pushDataToRemote(["requests": dataArray])
        }
    }
    
    private func resetAllVariables(){
        self.appDelegate.saveContext()
        self.classesToSync.removeValueForKey("SyncInfo")
        self.syncingStatus = !self.syncingStatus
        self.pullResponseJsons.removeAll()
        self.lastSyncDate = nil
        self.startSyncDate = NSDate()
        self.responseCount.removeAll()
        self.syncAction.removeAll()
        self.pushRequestObjects.removeAll()
    }
    
    private func dataToPushToRemote(className: String, dataArray: [AnyObject]) -> [AnyObject] {
        let parseData = ParseData()
        var dataArrayToAddData = dataArray
        if let objectsToCreateInRemote = objectsToCreate(className) {
            
            for object in objectsToCreateInRemote {
                var dictForObject = [String: AnyObject]()
                dictForObject["method"] = "POST"
                dictForObject["path"] = "/\(parseData.version)/classes/\(className)"
                dictForObject["body"] = self.parametersForNewObject(object)
                dataArrayToAddData.append(dictForObject)
                self.pushRequestObjects.append(object)
            }
        }
        if let _ = self.lastSyncDate {
            if let objectsToUpdateInRemote = objectsToUpdate(className) {
                for object in objectsToUpdateInRemote {
                    var dictForObject = [String: AnyObject]()
                    dictForObject["method"] = "PUT"
                    dictForObject["path"] = "/\(parseData.version)/classes/\(className)/\(object.valueForKey("objectIDInAPI")!)"
                    dictForObject["body"] = self.parametersForNewObject(object)
                    dataArrayToAddData.append(dictForObject)
                    self.pushRequestObjects.append(object)
                }
            }
            
            if let objectsToDeleteInRemote = objectsToDelete(className) {
                for object in objectsToDeleteInRemote {
                    var dictForObject = [String: AnyObject]()
                    dictForObject["method"] = "DELETE"
                    dictForObject["path"] = "/\(parseData.version)/classes/\(className)/\(object.valueForKey("objectIDInAPI")!)"
                    dataArrayToAddData.append(dictForObject)
                    self.pushRequestObjects.append(object)
                }
            }
        }
        return dataArrayToAddData
    }
    
    private func pushDataToRemote(parameters: [String: AnyObject]?) {
        let URl = "https://api.parse.com/1/batch"
        let headers = createHeaders()
        if pushRequestObjects.count > 0 {
            Alamofire.request(.POST, URl, parameters: parameters, encoding: .JSON, headers: headers).responseJSON { (response) -> Void in
                switch response.result {
                case .Success(let data):
                    let json = JSON(data)
                    self.syncAction.append(true)
                    self.processPushResponses(json)
                    
                    if self.syncAction.count == 2 {
                        self.syncCompleted()
                    }
                case .Failure(let errors):
                    print("Request failed with error for entity: \(errors)")
                }
            }
        } else {
            self.syncAction.append(true)
            if syncAction.count == 2 {
                self.syncCompleted()
            }
        }
        
    }
    
    private func processPushResponses(json: JSON){
        self.appDelegate.saveContext()
        for (jsonIndex, jsonEach)  in json {
           
            let managedObject = self.pushRequestObjects[Int(jsonIndex)!]
            for (index,value) in jsonEach{
                                if index == "success" {
                    if value.count == 0 {
                        managedObject.managedObjectContext?.deleteObject(managedObject)
                        print("object deleted")
                    } else if value["objectId"].isExists() {
                        managedObject.setValue(String(value["objectId"]), forKey: "objectIDInAPI")
                        managedObject.setValue(lastSyncDate, forKey: "updatedAt")
                        print("object created")
                    } else {
                        print("object updated")
                    }
                } else {
                    if "\(jsonEach["error"]["code"])" == "101" {
                        managedObject.managedObjectContext?.deleteObject(managedObject)
                        print("object locally deleted")
                    }
                    print("ERROR: \(jsonEach["error"]["error"]) Code \(jsonEach["error"]["code"])")
                }
            }
            
                    }
        
        
        
    }
    private func parametersForNewObject(managedObject: NSManagedObject) -> [String: AnyObject]? {
        var jsonObject = [String: AnyObject]()
        
        let attributes = managedObject.entity.attributesByName
        for (attributeName, _) in attributes {
            if attributeName != "updatedAt" && attributeName != "createdAt" && attributeName != "delete" && attributeName != "objectIDInAPI" {
                jsonObject[attributeName] = managedObject.valueForKey(attributeName)
            }
        }
        if jsonObject.count > 0 {
            return jsonObject
        } else {
            return nil
        }
    }
    
    private func objectsToCreate(className: String) -> [NSManagedObject]? {
        var predicate: NSPredicate?
        if let lastSyncDate = lastSyncDate {
            predicate = NSPredicate(format: "updatedAt > %@ AND createdAt > %@", lastSyncDate, lastSyncDate)
        }
        return fetchDataFromCoreData(className, predicate: predicate)
    }
    
    private func objectsToUpdate(className: String) -> [NSManagedObject]? {
        var predicate: NSPredicate?
        if let lastSyncDate = lastSyncDate {
            predicate = NSPredicate(format: "updatedAt > %@ AND createdAt < %@", lastSyncDate, lastSyncDate)
        }
        return fetchDataFromCoreData(className, predicate: predicate)
    }
    
    private func objectsToDelete(className: String) -> [NSManagedObject]? {
        var predicate: NSPredicate?
        if let lastSyncDate = lastSyncDate {
            predicate = NSPredicate(format: "delete = YES", lastSyncDate)
        }
        return fetchDataFromCoreData(className, predicate: predicate)
    }
    
    private func fetchDataFromCoreData(className: String, predicate: NSPredicate?) -> [NSManagedObject]? {
        let fetchRequest = NSFetchRequest(entityName: className)
        fetchRequest.predicate = predicate
        do {
            let results = try appDelegate.managedObjectContext.executeFetchRequest(fetchRequest) as! [NSManagedObject]
            if results.count > 0 {
                return results
            }
        } catch {
            print(error)
        }
        return nil
    }
    
    private func setLastDateSynced() {
        let fetchRequest = NSFetchRequest(entityName: "SyncInfo")
        let sortDesctiptor = NSSortDescriptor(key: "syncDate", ascending: false)
        fetchRequest.sortDescriptors = [sortDesctiptor]
        do {
            let result = try appDelegate.managedObjectContext.executeFetchRequest(fetchRequest) as! [SyncInfo]
            if let date = result.first?.syncDate {
                lastSyncDate = date
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
                    self.pullResponseJsons[className] = json
                }
                if self.responseCount.count == self.classesToSync.count {
                    self.processPullResponse()
                }
            case .Failure(let errors):
                print("Request failed with error for entity: \(className): \(errors)")
            }
        }
    }
    
    private func processPullResponse(){
        for (className, json) in pullResponseJsons {
            for (_ ,object) in json["results"] {
                let objectId = object["objectId"].stringValue
                let fetchRequest = NSFetchRequest(entityName: className)
                let predicate = NSPredicate(format: "objectIDInAPI = %@", objectId)
                fetchRequest.predicate = predicate
                fetchRequest.fetchLimit = 1
                do {
                    let result = try appDelegate.managedObjectContext.executeFetchRequest(fetchRequest) as! [Person]
                    if let person = result.first {
                        person.name = object["name"].stringValue
                        person.address = object["address"].stringValue
                        let updatedDate = self.dateUsingStringFromAPI(object["updatedAt"].stringValue)
                        person.updatedAt = updatedDate
                    }else {
                        if let newManagedObject = self.createNSManagedObjectForClass(className){
                            let newObject = newManagedObject as! Person
                            newObject.objectIDInAPI = objectId
                            newObject.name = object["name"].stringValue
                            newObject.address = object["address"].stringValue
                            newObject.createdAt = (self.dateUsingStringFromAPI(object["createdAt"].stringValue))
                            newObject.updatedAt = self.startSyncDate!
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
            self.syncAction.append(true)
            if self.syncAction.count == 2 {
                self.syncCompleted()
            }
        }catch {
            print(error)
        }
    }
    
    private func syncCompleted(){
        let entityDesc = NSEntityDescription.entityForName("SyncInfo", inManagedObjectContext: appDelegate.managedObjectContext)
        let syncDateObject = SyncInfo(entity: entityDesc!, insertIntoManagedObjectContext: appDelegate.managedObjectContext)
        syncDateObject.syncDate = self.startSyncDate

        self.resetAllVariables()
        
        print("Sync complete")
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
        self.dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:sss'Z'"
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
    
    private func getLastUpdatedOrCreatedeDateOfClassInCoreData(className: String) -> NSDate?{
        let fetchRequest = NSFetchRequest(entityName: className)
        let sortDescriptor = NSSortDescriptor(key: "updatedAt", ascending: false)
        fetchRequest.sortDescriptors = [sortDescriptor]
        fetchRequest.fetchLimit = 1
        
        do {
            let result = try appDelegate.managedObjectContext.executeFetchRequest(fetchRequest) as! [Person]
            if let date = result.first?.updatedAt {
                return date
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
        return URL
    }
}