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
    private var responseCount = [Bool]()
    private let appDelegate: AppDelegate!
    
    private var pullResponseJsons = [String: JSON]()
    
    private var dateFormatter = NSDateFormatter()
    
    private var lastSyncDate: NSDate?
    private var startSyncDate: NSDate?
    private var pushRequestData = [AnyObject]()
    private var syncAction = [Bool]()
    private var syncingStatus = false
    
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
        if !syncingStatus {
            syncingStatus = true
            pullResponseJsons.removeAll()
            lastSyncDate = nil
            startSyncDate = nil
            responseCount.removeAll()
            syncAction.removeAll()
            pushRequestData.removeAll()
            
            appDelegate.saveContext()
            if self.isConnectedToNetwork() {
                //        let date1 = NSDate()
                //        var date2 = date1.timeIntervalSince1970
                //        date2 = date2.advancedBy(24*60*60*5)
                //        if date1.compare(NSDate(timeIntervalSince1970: date2)) == NSComparisonResult.OrderedDescending {
                //            print("date 1 greater than date 2")
                //        }
                startSyncDate = NSDate()
                setLastDateSynced()
                //self.syncCompleted()
                classesToSync.removeValueForKey("SyncInfo")
                for (className, _) in classesToSync {
                    self.getDataFromRemote(className, parameters: getDataFetchParameters())
                    self.dataToPushToRemote(className)
                }
                self.pushDataToRemote(["requests": pushRequestData])
            } else {
                print("no internet connection")
            }
        }
    }
    
    private func dataToPushToRemote(className: String) {
        let parseData = ParseData()
        
        if let objectsToCreateInRemote = objectsToCreate(className) {
            
            for object in objectsToCreateInRemote {
                var dictForObject = [String: AnyObject]()
                dictForObject["method"] = "POST"
                dictForObject["path"] = "/\(parseData.version)/classes/\(className)"
                dictForObject["body"] = self.parametersForNewObject(object)
                self.pushRequestData.append(dictForObject)
            }
        }
        if let _ = self.lastSyncDate {
            if let objectsToUpdateInRemote = objectsToUpdate(className) {
                for object in objectsToUpdateInRemote {
                    var dictForObject = [String: AnyObject]()
                    dictForObject["method"] = "PUT"
                    dictForObject["path"] = "/\(parseData.version)/classes/\(className)/\(object.valueForKey("objectIDInAPI")!)"
                    dictForObject["body"] = self.parametersForNewObject(object)
                    self.pushRequestData.append(dictForObject)
                }
            }
            
            if let objectsToDeleteInRemote = objectsToDelete(className) {
                for object in objectsToDeleteInRemote {
                    var dictForObject = [String: AnyObject]()
                    dictForObject["method"] = "DELETE"
                    dictForObject["path"] = "/\(parseData.version)/classes/\(className)/\(object.valueForKey("objectIDInAPI")!)"
                    self.pushRequestData.append(dictForObject)
                }
            }
        }
    }
    
    private func pushDataToRemote(parameters: [String: AnyObject]?) {
        let URl = "https://api.parse.com/1/batch"
        let headers = createHeaders()
        // print(lastSyncDate)
        print(parameters)
        if pushRequestData.count > 0 {
            Alamofire.request(.POST, URl, parameters: parameters, encoding: .JSON, headers: headers).responseJSON { (response) -> Void in
                switch response.result {
                case .Success(let data):
                    let json = JSON(data)
                    self.syncAction.append(true)
                    print(json)
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
            predicate = NSPredicate(format: "updatedAt > %@ AND delete = YES", lastSyncDate)
        }
        return fetchDataFromCoreData(className, predicate: predicate)
    }
    
    private func fetchDataFromCoreData(className: String, predicate: NSPredicate?) -> [NSManagedObject]? {
        //print(predicate)
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
    //    private func objectsToDelete() -> [NSManagedObject] {
    //
    //    }
    //    private func objectsToUpdate() -> [NSManagedObject] {
    //
    //    }
    
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
                //print(self.responseCount.count)
                //print(self.classesToSync.count)
                if self.responseCount.count == self.classesToSync.count {
                    self.processResponse()
                }
            case .Failure(let errors):
                print("Request failed with error for entity: \(className): \(errors)")
            }
        }
    }
    
    private func processResponse(){
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
                            print(self.dateUsingStringFromAPI(object["createdAt"].stringValue))
                            newObject.createdAt = (self.dateUsingStringFromAPI(object["createdAt"].stringValue))
                            
                            newObject.updatedAt = self.startSyncDate!
                            print(object["createdAt"].stringValue)
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
        appDelegate.saveContext()
        pullResponseJsons.removeAll()
        lastSyncDate = nil
        startSyncDate = nil
        responseCount.removeAll()
        syncAction.removeAll()
        pushRequestData.removeAll()
        syncingStatus = false
        //        let fetchRequest = NSFetchRequest(entityName: "SyncInfo")
        //        do {
        //            let results = try appDelegate.managedObjectContext.executeFetchRequest(fetchRequest) as! [NSManagedObject]
        //            for result: NSManagedObject in results {
        //                print(result)
        //                print(result.valueForKey("syncDate"))
        //            }
        //        } catch {
        //            print(error)
        //        }
        //        print("_____")
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
        //print(URL)
        return URL
    }
}