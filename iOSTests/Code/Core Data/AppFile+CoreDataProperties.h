//
//  AppFile+CoreDataProperties.h
//  
//
//  Created by Christopher Prince on 12/12/15.
//
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

#import "AppFile.h"

NS_ASSUME_NONNULL_BEGIN

@interface AppFile (CoreDataProperties)

@property (nullable, nonatomic, retain) NSString *uuid;
@property (nullable, nonatomic, retain) NSString *fileName;

@end

NS_ASSUME_NONNULL_END
