//
//  ClassExtras.h
//  Petunia
//
//  Created by Christopher Prince on 12/4/14.
//  Copyright (c) 2014 Spastic Muffin, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ClassExtras : NSObject

// This is because the method conformsToProtocol doesn't check for method implementation. It just checks headers.
+ (BOOL) class: (Class) class implementsAllMethodsInProtocol: (Protocol *) protocol;

@end
