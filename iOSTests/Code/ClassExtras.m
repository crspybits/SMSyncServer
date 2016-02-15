//
//  ClassExtras.m
//  Tests
//
//  Created by Christopher Prince on 2/13/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

#import "ClassExtras.h"
#import <objc/runtime.h>

@implementation ClassExtras

/* I tried to do this first as a method returning the names of all classes. But ran into a crash with CNZombie. It seems you can't call object such as CNZombie with isSubclassOfClass.
2016-02-14 01:54:56 +0000: [fg0,0,255;Class name: SBSApplicationShortcutService[; [testCases() in TwoDeviceTestCase.swift, line 24]
2016-02-14 01:54:56 +0000: [fg0,0,255;Class name: NSFileReadingWritingClaim[; [testCases() in TwoDeviceTestCase.swift, line 24]
2016-02-14 01:54:56 +0000: [fg0,0,255;Class name: PKDiscoveryLSWatcher[; [testCases() in TwoDeviceTestCase.swift, line 24]
2016-02-14 01:54:56 +0000: [fg0,0,255;Class name: _CNZombie_[; [testCases() in TwoDeviceTestCase.swift, line 24]
*** CNZombie 737: -[ isSubclassOfClass:] sent to deallocated instance 0x1a0f88e10
Writing to file...
Wrote stacks to /var/mobile/Containers/Data/Application/FD4FEA3C-9237-4FF4-BFA0-7C83216CCA15/Library/Caches/ContactsZombies/CNZombiesStacks-737-0x1a0f88e10.plist
Wrote stack mapping to /var/mobile/Containers/Data/Application/FD4FEA3C-9237-4FF4-BFA0-7C83216CCA15/Library/Caches/ContactsZombies/CNZombiesStacksMapping-737-0x1a0f88e10.plist
*/
+ (NSArray *) classesWithPrefix: (NSString *) classNamePrefix andSubclassesOf: (Class) class;
{
    // Use reflection to get a list of all class names.
    // See https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Reference/ObjCRuntimeRef/index.html
    // and http://stackoverflow.com/questions/19298553/get-list-of-all-native-classes-in-ios
    int numClasses;
    Class *classes = NULL;

    numClasses = objc_getClassList(NULL, 0);
    
    NSMutableArray *result = NULL;
    
    if (numClasses > 0 ) {
        result = [NSMutableArray new];
        
        classes = (__unsafe_unretained Class *)malloc(sizeof(Class) * numClasses);
        numClasses = objc_getClassList(classes, numClasses);
        
        // 12/28/14; In Swift projects, class names have a prefix <ProjectName>.
        NSString *projectName = [[NSBundle mainBundle]objectForInfoDictionaryKey:@"CFBundleExecutable"];
        NSString *projectNamePrefix = [NSString stringWithFormat:@"%@.%@", projectName, classNamePrefix];
        
        for (NSUInteger i = 0; i < numClasses; i++) {
            Class c = classes[i];
            //NSLog(@"class Name: %s", class_getName(c));
            NSString *className = NSStringFromClass(c);
  
            if ([className hasPrefix:projectNamePrefix]) {
                if ([c isSubclassOfClass:class]) {
                    [result addObject: c];
                }
            }
        }
        
        free(classes);
    }
    
    return result;
}

+ (id) createObjectFrom: (Class) aClass;
{
    return [aClass new];
}

@end
