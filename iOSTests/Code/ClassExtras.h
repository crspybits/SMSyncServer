//
//  ClassExtras.h
//  Tests
//
//  Created by Christopher Prince on 2/13/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ClassExtras : NSObject

// Returns Class objects.
+ (NSArray *) classesWithPrefix: (NSString *) classNamePrefix andSubclassesOf: (Class) class;

// Assumes class has an zero-argument constructor and uses this to create object.
+ (id) createObjectFrom: (Class) aClass;

@end
