//
//  LocalFile.m
//  
//
//  Created by Christopher Prince on 12/12/15.
//
//

#define FILE_NAME @"fileName"

#import "AppFile.h"
#import "App-Swift.h"

@import SMCoreLib;

@implementation AppFile

- (NSURL *) url;
{
    return [FileStorage urlOfItem:self.fileName];
}

+ (NSString *) entityName;
{
    return NSStringFromClass([self class]);
}

+ (AppFile *) newObjectAndMakeUUID: (BOOL) makeUUID;
{
    AppFile *file = (AppFile *) [[CoreData sessionNamed:[CoreDataTests name]] newObjectWithEntityName:[self entityName]];
    
    if (makeUUID) {
        AssertIf(![file respondsToSelector:@selector(setUuid:)], @"Yikes: No uuid property on managed object");
        file.uuid = [UUID make];
    }
    
    
    [[CoreData sessionNamed:[CoreDataTests name]] saveContext];
    
    return file;
}

+ (AppFile *) newObject;
{
    return (AppFile *) [self newObjectAndMakeUUID:NO];
}

+ (NSFetchRequest *) fetchRequestForAllObjectsInContext:(NSManagedObjectContext*) context;
{
    NSFetchRequest * fetchRequest = [[CoreData sessionNamed:[CoreDataTests name]] fetchRequestWithEntityName:[self entityName] modifyingFetchRequestWith:nil];
    
    NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:FILE_NAME ascending:NO];
    fetchRequest.sortDescriptors = @[sortDescriptor];
    
    return fetchRequest;
}

@end
