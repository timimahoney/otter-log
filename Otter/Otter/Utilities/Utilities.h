//
//  Utilities.h
//  Otter
//
//  Created by Tim Mahoney on 12/16/23.
//

#import <Foundation/Foundation.h>
#import <OSLog/OSLog.h>

NS_ASSUME_NONNULL_BEGIN

NS_INLINE NSException * _Nullable OtterExecuteWithObjCExceptionHandling(void(NS_NOESCAPE^_Nonnull tryBlock)(void)) {
    @try {
        tryBlock();
    }
    @catch (NSException *exception) {
        return exception;
    }
    return nil;
}

typedef NS_ENUM(unsigned long long, OTSystemEventType) {
    OTSystemEventTypeActivity = 513,
    OTSystemEventTypeLog = 1024,
};

typedef NS_ENUM(unsigned long long, OTSystemLogType) {
    OTSystemLogTypeDebug = 2,
    OTSystemLogTypeInfo = 1,
    OTSystemLogTypeDefault = 0,
    OTSystemLogTypeError = 16,
    OTSystemLogTypeFault = 17,
};

#define OTLogLoading os_log_create("com.jollycode.otter", "Loading")

@protocol OTSystemLogEntry

@property (readonly, nonatomic) OTSystemEventType type;

@property (readonly, nonatomic) NSDate *date;
@property (readonly, nonatomic) NSString *composedMessage;

@property (readonly, nonatomic, nullable) NSString *process;
@property (readonly, nonatomic, nullable) NSUUID *processImageUUID;
@property (readonly, nonatomic) int processIdentifier;
@property (readonly, nonatomic) NSString *sender;
@property (readonly, nonatomic) unsigned long long activityIdentifier;
@property (readonly, nonatomic) unsigned long long threadIdentifier;

// Log
@property (readonly, nonatomic) OTSystemLogType logType;
@property (readonly, nonatomic, nullable) NSString *category;
@property (readonly, nonatomic, nullable) NSString *subsystem;

// Activity
@property (readonly, nonatomic) unsigned long long parentActivityIdentifier;

// Signpost
@property (readonly, nonatomic, nullable) NSString *signpostName;
@property (readonly, nonatomic) unsigned long long signpostScope;
@property (readonly, nonatomic) unsigned long long signpostType;
@property (readonly, nonatomic) unsigned long long signpostIdentifier;

@end

// Fast Enumeration

@interface OtterFastEnumeration : NSObject

+ (void)fastEnumerate:(NSURL *)logarchiveFileURL 
           progresses:(NSDictionary<NSNumber /* Time Interval Since End Of Archive */ *, NSProgress *> *)progresses
           rangeBlock:(void (^)(NSDate *, NSDate *))rangeBlock
                block:(id _Nullable (^)(NSInteger, id<OTSystemLogEntry>))block
        finishedChunk:(void (^)(NSInteger, NSInteger, NSArray *))finishedChunk
    completionHandler:(void (^)(NSError * _Nullable error))completionHandler;

+ (void)fastEnumerate:(NSURL *)logarchiveFileURL
               chunks:(NSInteger)chunkCount
                power:(double)power
           concurrent:(NSInteger)concurrentStreamCount
           progresses:(NSDictionary<NSNumber /* Time Interval Since End Of Archive */ *, NSProgress *> *)progresses
           rangeBlock:(void (^)(NSDate /* Archive Start */ *, NSDate /* Archive End */ *))rangeBlock
                block:(id _Nullable (^)(NSInteger chunkIndex, id<OTSystemLogEntry>))block
        finishedChunk:(void (^)(NSInteger finishedChunkIndex, NSInteger totalChunkCount, NSArray *))finishedChunk
    completionHandler:(void (^)(NSError * _Nullable error))completionHandler;

@end

NS_ASSUME_NONNULL_END
