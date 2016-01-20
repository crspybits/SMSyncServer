//
//  GeneralDefines.h
//  Petunia
//
//  Created by Christopher Prince on 9/4/14.
//  Copyright (c) 2014 Spastic Muffin, LLC. All rights reserved.
//

#ifndef Petunia_GeneralDefines_h
#define Petunia_GeneralDefines_h

#define DefWelf __weak typeof(self) welf = self
#define WeakSelfDef(WELF) __weak typeof(self) WELF = self
#define WeakObjDef(WOBJ, OBJ) __weak typeof(OBJ) WOBJ = OBJ

#define CreateError(message)	[NSError errorWithDomain:@"" code:0 userInfo:@{NSLocalizedDescriptionKey:message}]
#define CreateErrorWithCode(message, CODE)	[NSError errorWithDomain:@"" code:CODE userInfo:@{NSLocalizedDescriptionKey:message}]

// 4/10/15; With Xcode6.3, getting errors on NSParameterAssert
// http://stackoverflow.com/questions/29549756/compilation-error-with-nsparameterassert-with-xcode-6-3
#undef NSParameterAssert
#define NSParameterAssert(condition)    ({\
do {\
_Pragma("clang diagnostic push")\
_Pragma("clang diagnostic ignored \"-Wcstring-format-directive\"")\
NSAssert((condition), @"Invalid parameter not satisfying: %s", #condition);\
_Pragma("clang diagnostic pop")\
} while(0);\
})

// Ignore -Wno-objc-property-synthesis warnings
// Starting with Xcode 6.3, they give you warnings if you override the class of a property defined in a superclass. Odd.
// See http://stackoverflow.com/questions/29534654/xcode-6-3-warning-synthesize-property/30113405#30113405
// And https://github.com/couchbase/couchbase-lite-ios/issues/660
#define StartIgnorePropertySynthesisWarning\
    _Pragma("clang diagnostic push")\
    _Pragma("clang diagnostic ignored \"-Wobjc-property-synthesis\"")

#define EndIgnoreWarning\
    _Pragma("clang diagnostic pop")

#endif
