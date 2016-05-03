//
//  ClassExtras.m
//  Petunia
//
//  Created by Christopher Prince on 12/4/14.
//  Copyright (c) 2014 Spastic Muffin, LLC. All rights reserved.
//

#import "ClassExtras.h"
#import <objc/runtime.h>

@implementation ClassExtras

// See http://stackoverflow.com/questions/21767576/how-can-i-check-if-a-class-implements-all-methods-in-a-protocol-in-obj-c
+ (BOOL) class: (Class) class implementsAllMethodsInProtocol: (Protocol *) protocol;
{
    unsigned int count;
    struct objc_method_description *methodDescriptions = protocol_copyMethodDescriptionList(protocol, NO, YES, &count);
    BOOL implementsAll = YES;
    for (unsigned int i = 0; i<count; i++) {
        if (![class instancesRespondToSelector:methodDescriptions[i].name]) {
            implementsAll = NO;
            break;
        }
    }
    free(methodDescriptions);
    return implementsAll;
}

@end
