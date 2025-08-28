//
//  OTAsyncOperation.m
//  Otter
//
//  Created by Tim Mahoney on 2/3/24.
//

#import "OTAsyncOperation.h"

@interface OTAsyncOperation ()
@property (atomic, assign) BOOL isRunningBlock;
@property (atomic, assign) BOOL didRunBlock;
@property (nonatomic, copy) void (^block)(void (^)(void));


@end

@implementation OTAsyncOperation


+ (instancetype)operationWithBlock:(void (^)(void (^operationFinishedBlock)(void)))block {
    return [[OTAsyncOperation alloc] initWithBlock:block];
}

- (instancetype)initWithBlock:(void (^)(void (^operationFinishedBlock)(void)))block {
    self = [super init];
    if (self) {
        self.block = block;
    }
    return self;
}

- (BOOL)isAsynchronous {
    return YES;
}

- (BOOL)isExecuting {
    return self.isRunningBlock;
}

- (BOOL)isFinished {
    return self.didRunBlock;
}

- (void)start {
    [self willChangeValueForKey:@"isExecuting"];
    self.isRunningBlock = YES;
    [self didChangeValueForKey:@"isExecuting"];
    self.block(^{
        [self willChangeValueForKey:@"isExecuting"];
        [self willChangeValueForKey:@"isFinished"];
        self.isRunningBlock = NO;
        self.didRunBlock = YES;
        [self didChangeValueForKey:@"isExecuting"];
        [self didChangeValueForKey:@"isFinished"];
    });
}

@end
