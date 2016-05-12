//
//  AppFile.h
//  
//
//  Created by Christopher Prince on 12/12/15.
//
//

// For keeping track of files in the testing app.

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
@import SMCoreLib;

//NS_ASSUME_NONNULL_BEGIN

@interface AppFile : NSManagedObject

- (SMRelativeLocalURL *) url;
- (void) removeObject;

+ (NSString *) entityName;

+ (AppFile *) newObject;
+ (AppFile *) newObjectAndMakeUUID: (BOOL) makeUUID;

+ (NSFetchRequest *) fetchRequestForAllObjectsInContext:(NSManagedObjectContext*) context;

@end

//NS_ASSUME_NONNULL_END

#import "AppFile+CoreDataProperties.h"
