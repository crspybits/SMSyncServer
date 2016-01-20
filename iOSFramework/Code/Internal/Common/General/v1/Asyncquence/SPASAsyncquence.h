//
//  SPASAsyncquence.h
//  Petunia
//
//  Created by Christopher Prince on 1/13/15.
//  Copyright (c) 2015 Spastic Muffin, LLC. All rights reserved.
//

// Execute asynchronous blocks in a sequential manner.

#import <Foundation/Foundation.h>

@interface SPASAsyncquence : NSObject

typedef NS_ENUM(NSInteger, SPASAsyncquenceContinueType) {
    SPASAsyncquenceContinueTypeEnd,
    SPASAsyncquenceContinueTypeDoNext,
};

typedef void (^SPASAsyncquenceCallback)(SPASAsyncquenceContinueType doNext);
typedef void (^SPASAsyncquenceBlock)(SPASAsyncquenceCallback asyncCallback);

// Elements are of type SPASAsyncquenceBlock
// Each SPASAsyncquenceBlock block is executed in turn. If blocks[i] calls asyncCallback with SPASAsyncquenceContinueTypeDoNext, then block[i+1] will be executed (unless at end of sequence). If blocks[i] calls asyncCallback with SPASAsyncquenceContinueTypeEnd, or does not call the callback, then the next block is not executed.
+ (void) do: (NSArray *) blocks;

// Usage example:
/*
 
 [SPASAsyncquence do: @[
    ^(SPASAsyncquenceCallback decideTo) {
        SPASLog(@"Test1");
        decideTo(SPASAsyncquenceContinueTypeDoNext);
    }
    ,
    ^(SPASAsyncquenceCallback decideTo) {
        SPASLog(@"Test2");
        decideTo(SPASAsyncquenceContinueTypeEnd);
    },
    ^(SPASAsyncquenceCallback decideTo) {
        SPASLog(@"Test3");
        decideTo(SPASAsyncquenceContinueTypeDoNext);
    }
 ]];
 
 */

- (void) add: (SPASAsyncquenceBlock) sequenceComponent;
- (void) addIf: (SPASAsyncquenceBlock) sequenceComponent;
- (void) addYesIf: (SPASAsyncquenceBlock) sequenceComponent;
- (void) addNoIf: (SPASAsyncquenceBlock) sequenceComponent;
- (void) go;

#ifdef DEBUG
+ (void) test;
#endif

@end
