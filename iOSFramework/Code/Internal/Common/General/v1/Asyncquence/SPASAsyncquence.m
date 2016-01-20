//
//  SPASAsyncquence.m
//  Petunia
//
//  Created by Christopher Prince on 1/13/15.
//  Copyright (c) 2015 Spastic Muffin, LLC. All rights reserved.
//

#import "SPASAsyncquence.h"
#import "NSArray+Extras.h"

@implementation SPASAsyncquence

// typedef void (^SPASAsyncquenceBlock)(void (^asyncCallback)(NSError *error));

// Elements are of type SPASAsyncquenceReturn
// Each block is executed in turn. If blocks[i] calls asyncCallback with nil, then block[i+1] be executed (unless at end of sequence). If blocks[i] calls asyncCallback with non-nil, or does not callback, then the next block is not executed.
+ (void) do: (NSArray *) blocks;
{
    if (![blocks count]) return;
    SPASAsyncquenceBlock block = blocks[0];
    
    SPASAsyncquenceCallback callback = ^(SPASAsyncquenceContinueType doNext) {
        switch (doNext) {
            case SPASAsyncquenceContinueTypeDoNext:
                [self do: [blocks tail]];
                break;
                
            case SPASAsyncquenceContinueTypeEnd:
                break;
        }
    };
    
    block(callback);
}

#ifdef DEBUG
+ (void) test;
{
    [SPASAsyncquence do: @[
        ^(SPASAsyncquenceCallback callback) {
            SPASLog(@"Test1");
            callback(SPASAsyncquenceContinueTypeDoNext);
        }
        ,
        ^(SPASAsyncquenceCallback callback) {
            SPASLog(@"Test2");
            callback(SPASAsyncquenceContinueTypeEnd);
        },
        ^(SPASAsyncquenceCallback callback) {
            SPASLog(@"Test3");
            callback(SPASAsyncquenceContinueTypeDoNext);
        }
    ]];
}
#endif


@end
