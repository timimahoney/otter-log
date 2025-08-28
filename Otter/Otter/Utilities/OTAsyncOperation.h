//
//  OTAsyncOperation.h
//  Otter
//
//  Created by Tim Mahoney on 2/3/24.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OTAsyncOperation : NSOperation

+ (instancetype)operationWithBlock:(void (^)(void (^operationFinishedBlock)(void)))block;

@end

NS_ASSUME_NONNULL_END
