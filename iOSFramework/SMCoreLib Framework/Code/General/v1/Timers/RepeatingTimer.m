//
//  RepeatingTimer.m
//  Petunia
//
//  Created by Christopher Prince on 11/16/13.
//  Copyright (c) 2013 Spastic Muffin, LLC. All rights reserved.
//

#import "RepeatingTimer.h"

@interface RepeatingTimer()
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSInvocation * invocation;
@end

@implementation RepeatingTimer

- (id) initWithInterval: (float) intervalInSeconds selector: (SEL) selector andTarget: (id) target {
    self = [super init];
    if (self) {
        NSMethodSignature * mySignature =
            [target methodSignatureForSelector:selector];
        self.invocation = [NSInvocation
                                     invocationWithMethodSignature:mySignature];
        [self.invocation setTarget:target];
        [self.invocation setSelector:selector];
        self.interval = intervalInSeconds;
    }
    return self;
}

- (BOOL) running {
    if (self.timer) return YES;
    return NO;
}

- (void) start {
    if (!self.timer) {
        self.timer = [NSTimer scheduledTimerWithTimeInterval:self.interval  invocation: self.invocation repeats:YES];
    }
}

- (void) cancel {
    [self.timer invalidate];
    self.timer = nil;
}

@end
