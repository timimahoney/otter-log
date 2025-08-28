//
//  Utilities.m
//  Otter
//
//  Created by Tim Mahoney on 12/16/23.
//

#import "Utilities.h"
#import "OTAsyncOperation.h"
#import <os/lock.h>
#import <OSLog/OSLog.h>

@class OSLogEventStore;

@protocol OTEventStore <NSObject>
- (id)initWithArchiveURL:(NSURL *)arg1;
- (void)prepareWithCompletionHandler:(id)arg1;
@end

@protocol OTEventStream <NSObject>
- (id)initWithSource:(id)source;
- (void)setFlags:(unsigned long long)flags;
- (void)setTarget:(dispatch_queue_t)target;
- (void)setEventHandler:(id)arg1;
- (void)setInvalidationHandler:(id)handler;
- (void)activateStreamFromDate:(id)date toDate:(id)endDate;
@end

@protocol OTEventSource <NSObject>
@property (nonatomic, readonly) NSDate *newestDate;
@property (nonatomic, readonly) NSDate *oldestDate;
@end

static NSErrorDomain const OTErrorDomain = @"Otter";

typedef NS_ENUM(NSInteger, OTErrorCode) {
    OTErrorNoClass    = -666,
    OTErrorNoMethod   = -777,
    OTErrorNoSource   = -888,
};

@interface NSError (Helper)

+ (instancetype)OTErrorWithCode:(OTErrorCode)code description:(NSString *)description;
+ (instancetype)OTErrorForNoClass:(NSString *)className;
+ (instancetype)OTErrorForNoMethod:(NSString *)methodName;

@end

typedef NS_OPTIONS(unsigned long long, OTStreamFlag) {
    OTStreamFlagInfo = 1,
    OTStreamFlagDebug = 1 << 1,
    // Unknown what the other flags are...
};

@interface OTLoadingChunk : NSObject
@property (nullable, nonatomic, copy) NSDate *start;
@property (nullable, nonatomic, copy) NSDate *end;
@end
@implementation OTLoadingChunk
- (NSString *)description {
    NSString *durationString = nil;
    NSDate *start = self.start;
    NSDate *end = self.end;
    if (start && end) {
        NSTimeInterval span = [self.end timeIntervalSinceDate:self.start];
        durationString = [[self.class durationStringFromTimeInterval:span] stringByAppendingString:@" "];
    } else if (start) {
        durationString = @"end ";
    } else if (end) {
        durationString = @"begin ";
    } else {
        durationString = @"full ";
    }
    return [NSString stringWithFormat:@"LoadingChunk(%@start=<%@> end=<%@>)", durationString, self.start, self.end];
}

+ (NSString *)durationStringFromTimeInterval:(NSTimeInterval)duration {
    if (duration < 60) {
        return [NSString stringWithFormat:@"%.0fs", duration];
    } else if (duration < 60 * 60) {
        return [NSString stringWithFormat:@"%.0fm", duration / 60];
    } else if (duration < 60 * 60 * 24) {
        return [NSString stringWithFormat:@"%.0fh", duration / 60 / 60];
    } else {
        return [NSString stringWithFormat:@"%.0fd", duration / 60 / 60 / 24];
    }
}
@end

@implementation NSError (Helper)

+ (instancetype)OTErrorWithCode:(OTErrorCode)code description:(NSString *)description {
    return [NSError errorWithDomain:OTErrorDomain code:code userInfo:@{ NSLocalizedDescriptionKey : description }];
}

+ (instancetype)OTErrorForNoClass:(NSString *)className {
    return [self OTErrorWithCode:OTErrorNoClass description:[NSString stringWithFormat: @"No %@ class", className]];
}

+ (instancetype)OTErrorForNoMethod:(NSString *)methodName {
    return [self OTErrorWithCode:OTErrorNoMethod description:[NSString stringWithFormat: @"No %@ method", methodName]];
}

@end

@implementation OtterFastEnumeration

// MARK: - ¡Introspection!

+ (nullable Class)getClass:(NSString *)className error:(NSError **)outError {
    Class theClass = NSClassFromString(className);
    if (theClass == nil) {
        if (outError) *outError = [NSError OTErrorForNoClass:className];
        return nil;
    }
    return theClass;
}

+ (BOOL)checkClass:(Class)aClass respondsToSelector:(SEL)selector error:(NSError **)outError {
    if (![aClass instancesRespondToSelector:selector]) {
        if (outError) *outError = [NSError OTErrorForNoMethod:NSStringFromSelector(selector)];
        return NO;
    }
    return YES;
}

+ (BOOL)checkObject:(id<NSObject>)object respondsToSelector:(SEL)selector error:(NSError **)outError {
    if (![object respondsToSelector:selector]) {
        if (outError) *outError = [NSError OTErrorForNoMethod:NSStringFromSelector(selector)];
        return NO;
    }
    return YES;
}

+ (Class)eventStreamClassWithError:(NSError **)outError {
    Class eventStreamClass = [self getClass:@"OSLogEventStream" error:outError];
    if (!eventStreamClass) return nil;
    if (![self checkClass:eventStreamClass respondsToSelector:@selector(activateStreamFromDate:toDate:) error:outError]) { return nil; }
    if (![self checkClass:eventStreamClass respondsToSelector:@selector(setFlags:) error:outError]) { return nil; }
    if (![self checkClass:eventStreamClass respondsToSelector:@selector(setTarget:) error:outError]) { return nil; }
    return eventStreamClass;
}

// MARK: - Fast Enumeration

+ (void)fastEnumerate:(NSURL *)logarchiveFileURL progresses:(NSDictionary<NSNumber *, NSProgress *> *)progresses rangeBlock:(void (^)(NSDate *, NSDate *))rangeBlock block:(id _Nullable (^)(NSInteger, id<OTSystemLogEntry>))block finishedChunk:(void (^)(NSInteger, NSInteger, NSArray *))finishedChunk completionHandler:(void (^)(NSError * _Nullable error))completionHandler {
    // Set the number of concurrent streams based on the number of cores available.
    NSUInteger cores = NSProcessInfo.processInfo.activeProcessorCount;
    NSUInteger concurrentStreamCount = MAX(cores, 8); // Ensure at most 8 concurrent to save the planet.
    concurrentStreamCount = MAX(4, concurrentStreamCount); // Ensure at least 4 concurrent to save time.
    
    [self fastEnumerate:logarchiveFileURL
                 chunks:73
                  power:1.2
             concurrent:concurrentStreamCount
             progresses:progresses
             rangeBlock:rangeBlock
                  block:block
          finishedChunk:finishedChunk
      completionHandler:completionHandler];
}

+ (void)fastEnumerate:(NSURL *)logarchiveFileURL
               chunks:(NSInteger)chunkCount
                power:(double)power
           concurrent:(NSInteger)concurrentStreamCount
           progresses:(NSDictionary<NSNumber *, NSProgress *> *)progresses
           rangeBlock:(void (^)(NSDate *, NSDate *))rangeBlock
                block:(id _Nullable (^)(NSInteger, id<OTSystemLogEntry>))block
        finishedChunk:(void (^)(NSInteger, NSInteger, NSArray *))finishedChunk
    completionHandler:(void (^)(NSError * _Nullable error))completionHandler {
    os_log_t log = OTLogLoading;
    os_log(log, "Will attempt fast loading for archive at %@", logarchiveFileURL);
    
    __block NSError *error = nil;
    
    // Check to make sure we can actually use this SPI.
    Class eventStoreClass = [self getClass:@"OSLogEventStore" error:&error];
    if (!eventStoreClass) { completionHandler(error); return; }
    Class eventStreamClass = [self eventStreamClassWithError:&error];
    if (!eventStreamClass) { completionHandler(error); return; }
    Class eventSourceClass = [self getClass:@"OSLogEventSource" error:&error];
    if (!eventSourceClass) { completionHandler(error); return; }
    if (![self checkClass:eventStoreClass respondsToSelector:@selector(initWithArchiveURL:) error:&error]) { completionHandler(error); return; }
    
    os_log_info(log, "Looks like we might be able to load pretty fast!");
    
    NSDate *loadingStart = [NSDate date];
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    
    id eventStore = [[eventStoreClass alloc] initWithArchiveURL:logarchiveFileURL];
    
    // First, get some initial data about the store like the start and end dates.
    [self prepareEventSourceFromStore:eventStore completionHandler:^(id<OTEventSource> initialEventSource, NSError *preparationError) {
        if (!initialEventSource || preparationError) {
            error = preparationError;
            os_log_error(log, "Failed to prepare initial event source: %@", error);
            dispatch_group_leave(group);
            return;
        }
        
        // Generate a list of date ranges that we'll parse.
        NSDate *start = [initialEventSource oldestDate];
        NSDate *end = [initialEventSource newestDate];
        if (rangeBlock) rangeBlock(start, end);
        NSArray<OTLoadingChunk *> *chunks = [self loadingChunksFromDate:start toDate:end min:concurrentStreamCount max:chunkCount power:power];
        __block int remainingStreams = (int)chunks.count;
        
        // Map the NSProgresses to the loading chunks.
        // The "total" unit count of the progress will be the number of chunks that need to load to include everything for that progress.
        // The "completed" unit count will be the number of those chunks loaded.
        NSMutableDictionary<NSNumber *, NSMutableSet<OTLoadingChunk *> *> *remainingChunksPerProgress = [NSMutableDictionary new];
        [progresses enumerateKeysAndObjectsUsingBlock:^(NSNumber *progressTimeIntervalSinceEnd, NSProgress *progress, BOOL *stop) {
            
            NSMutableSet<OTLoadingChunk *> *chunksForThisProgress = [NSMutableSet set];
            if (progressTimeIntervalSinceEnd.doubleValue == -1) {
                [chunksForThisProgress addObjectsFromArray:chunks];
            } else {
                NSDate *progressStart = [end dateByAddingTimeInterval:-progressTimeIntervalSinceEnd.doubleValue];
                [chunks enumerateObjectsUsingBlock:^(OTLoadingChunk *chunk, NSUInteger chunkIndex, BOOL *chunkStop) {
                    [chunksForThisProgress addObject:chunk];
                    if ([chunk.start compare:progressStart] == NSOrderedAscending) {
                        *chunkStop = YES;
                    }
                }];
            }
            remainingChunksPerProgress[progressTimeIntervalSinceEnd] = chunksForThisProgress;
            progress.totalUnitCount = chunksForThisProgress.count;
        }];
        
        NSTimeInterval span = [end timeIntervalSinceDate:start];
        NSString *durationString = [OTLoadingChunk durationStringFromTimeInterval:span];
        os_log_info(log, "Will stream %lu chunks with %lu concurrent streams using power %.1f spanning %{public}@ from start=%@ to end=%@: %@", (unsigned long)chunks.count, concurrentStreamCount, power, durationString, start, end, chunks);
        
        NSOperationQueue *queue = [[NSOperationQueue alloc] init];
        queue.maxConcurrentOperationCount = concurrentStreamCount;
        
        // Keep track of some data so we can log about speed.
        __block NSUInteger totalEntryCount = 0;
        __block NSUInteger currentIntervalCount = 0;
        __block NSUInteger reportingInterval = 234567;
        __block NSDate *reportingIntervalStart = [NSDate date];
        NSNumberFormatter *formatter = [NSNumberFormatter new];
        formatter.numberStyle = NSNumberFormatterDecimalStyle;
        
        __block os_unfair_lock progressLock = OS_UNFAIR_LOCK_INIT;
        
        NSInteger i = 0;
        for (OTLoadingChunk *chunk in chunks) {
            dispatch_group_enter(group);
            
            NSInteger chunkIndex = i;
            i += 1;
            OTAsyncOperation *operation = [OTAsyncOperation operationWithBlock:^(void (^operationFinished)(void)) {
                NSDate *chunkStreamStart = [NSDate date];
                [self streamChunk:chunk store:eventStore block:^id (id<OTSystemLogEntry> entry) {
                    
                    // Log about the speed.
                    os_unfair_lock_lock(&progressLock);
                    totalEntryCount += 1;
                    currentIntervalCount += 1;
                    if (currentIntervalCount > reportingInterval) {
                        NSUInteger currentSpeed = round(currentIntervalCount / -reportingIntervalStart.timeIntervalSinceNow);
                        NSUInteger overallSpeed = round(totalEntryCount / -loadingStart.timeIntervalSinceNow);
                        currentIntervalCount = 0;
                        reportingIntervalStart = [NSDate date];
                        os_log_debug(log, "Loaded %@ entries. current: %@/s, overall: %@/s", [formatter stringFromNumber:@(totalEntryCount)], [formatter stringFromNumber:@(currentSpeed)], [formatter stringFromNumber:@(overallSpeed)]);
                    }
                    os_unfair_lock_unlock(&progressLock);
                    
                    return block(chunkIndex, entry);
                    
                } completionHandler:^(NSArray *events, NSError *streamError) {
                    @synchronized (self) {
                        [remainingChunksPerProgress enumerateKeysAndObjectsUsingBlock:^(NSNumber *progressStart, NSMutableSet<OTLoadingChunk *> *progressChunks, BOOL *stop) {
                            [progressChunks removeObject:chunk];
                            NSProgress *progress = progresses[progressStart];
                            dispatch_async(dispatch_get_main_queue(), ^{
                                progress.completedUnitCount = progress.totalUnitCount - progressChunks.count;
                            });
                        }];
                        
                        if (streamError) {
                            error = streamError;
                        }
                        remainingStreams -= 1;
                        os_log_info(OTLogLoading, "Finished loading chunk %d in %.1fs with %@ entries (%d/%d remaining): %@", (int)chunkIndex, -chunkStreamStart.timeIntervalSinceNow, [formatter stringFromNumber:@(events.count)], remainingStreams, (int)chunks.count, chunk);
                    }
                    finishedChunk(chunkIndex, chunks.count, events);
                    operationFinished();
                    dispatch_group_leave(group);
                }];
            }];
            
            // Set the quality of service according to how close we are to the end of the log archive.
            // We really only want this so that we can properly order the chunk loading.
            if (chunkIndex < 7) {
                operation.qualityOfService = NSQualityOfServiceUserInitiated;
            } else if (chunkIndex < 20) {
                operation.qualityOfService = NSQualityOfServiceUtility;
            } else {
                operation.qualityOfService = NSQualityOfServiceBackground;
            }
            
            [queue addOperation:operation];
        }
        
        // Let's not return until our operation group is finished.
        // We should have added any operations to this in the loop over the chunks above.
        dispatch_group_enter(group);
        [queue addBarrierBlock:^{
            os_unfair_lock_lock(&progressLock);
            NSUInteger overallSpeed = round(totalEntryCount / -loadingStart.timeIntervalSinceNow);
            os_log_info(log, "All operations finished. Loaded %@ entries at %@/s", [formatter stringFromNumber:@(totalEntryCount)], [formatter stringFromNumber:@(overallSpeed)]);
            os_unfair_lock_unlock(&progressLock);
            dispatch_group_leave(group);
        }];
        
        // For the initial event source.
        dispatch_group_leave(group);
    }];
    
    dispatch_group_notify(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSString *errorString = (error ? [NSString stringWithFormat:@"with error: %@", error] : @"");
        os_log(log, "Finished fast load in %.2f seconds%@", -loadingStart.timeIntervalSinceNow, errorString);
        completionHandler(error);
    });
}

+ (void)streamChunk:(OTLoadingChunk *)chunk store:(id<OTEventStore>)eventStore block:(id _Nullable (^)(id<OTSystemLogEntry>))block completionHandler:(void (^)(NSArray * _Nullable, NSError * _Nullable))completionHandler {
    NSError *classError = nil;
    Class eventStreamClass = [self eventStreamClassWithError:&classError];
    if (!eventStreamClass) { completionHandler(nil, classError); return; }
    
    [self prepareEventSourceFromStore:eventStore completionHandler:^(id<OTEventSource> eventSource, NSError *preparationError) {
        if (!eventSource || preparationError) {
            os_log_error(OTLogLoading, "Failed to prepare event source for chunk %@: %@", chunk, preparationError);
            completionHandler(nil, preparationError);
            return;
        }
        
        os_log_info(OTLogLoading, "Will activate event source for chunk %@", chunk);
        
        id eventStream = [[eventStreamClass alloc] initWithSource:eventSource];
        
        dispatch_queue_attr_t loadingQueueAttr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL_WITH_AUTORELEASE_POOL, QOS_CLASS_UTILITY, -1);
        dispatch_queue_t loadingQueue = dispatch_queue_create("com.jollycode.otter.loading", loadingQueueAttr);
        [eventStream setTarget:loadingQueue];
        
        NSMutableArray *eventObjects = [[NSMutableArray alloc] initWithCapacity:100000];
        
        [eventStream setEventHandler:^(id<OTSystemLogEntry> event) {
            switch (event.type) {
                case OTSystemEventTypeLog:
                case OTSystemEventTypeActivity: {
                    id eventObject = block(event);
                    if (eventObject) {
                        [eventObjects addObject:eventObject];
                    }
                }
                default:
                    break;
            }
        }];
        [eventStream setInvalidationHandler:^{
            completionHandler(eventObjects, nil);
        }];
        
        [eventStream setFlags:OTStreamFlagDebug|OTStreamFlagInfo];
        [eventStream activateStreamFromDate:chunk.start toDate:chunk.end];
    }];
}

+ (void)prepareEventSourceFromStore:(id<OTEventStore>)eventStore completionHandler:(void (^)(id<OTEventSource> _Nullable, NSError * _Nullable))completionHandler {
    __block NSError *error = nil;
    [eventStore prepareWithCompletionHandler:^(id eventSource) {
        if (!eventSource) {
            error = [NSError OTErrorWithCode:OTErrorNoSource description:@"No event source after preparation"];
            completionHandler(nil, error);
        } else if (![self checkObject:eventSource respondsToSelector:@selector(newestDate) error:&error]) {
            completionHandler(nil, error);
        } else if (![self checkObject:eventSource respondsToSelector:@selector(oldestDate) error:&error]) {
            completionHandler(nil, error);
        } else {
            completionHandler(eventSource, nil);
        }
    }];
}

#define USE_KNOWN_CHUNK_SIZES 1

+ (NSArray<OTLoadingChunk *> *)loadingChunksFromDate:(NSDate *)start 
                                              toDate:(NSDate *)end
                                                 min:(NSUInteger)minChunkCount
                                                 max:(NSUInteger)maxChunkCount
                                               power:(double)power {
    
    // Generally, there will be more logs toward the end of the archive, so let's have smaller chunks there.
    NSMutableArray<OTLoadingChunk *> *chunks = [NSMutableArray array];
    
    // Generate a list of chunks to load from the log archive.
    // We have a max chunk count, but we might have less than that.
    // We work backward from the end of the archive in progressively larger chunks.
    NSDate *chunkStart = end;
    
    for (int i = 0; i < maxChunkCount && chunkStart != nil; i++) {
#if USE_KNOWN_CHUNK_SIZES
        // We have a well-known set of intervals for chunks depending on how close they are to the end of the archive.
        // For the last 10 minutes, create chunks of one minute each.
        NSTimeInterval interval = 60;
        if (i < 6) {
            interval = 1 * 60;
        } else if (i < 10) {
            interval = 15 * 60;
        } else if (i < 30) {
            interval = 30 * 60;
        } else if (i < 40) {
            interval = 2 * 60 * 60;
        } else if (i < 50) {
            interval = 4 * 60 * 60;
        } else if (i < 60) {
            interval = 8 * 60 * 60;
        } else {
            interval = 12 * 60 * 60;
        }
#else
        NSTimeInterval interval = pow(i + 1, power) * 60;
#endif
        NSDate *chunkEnd = chunkStart;
        chunkStart = [chunkEnd dateByAddingTimeInterval:-interval];
        
        // If this is our last chunk (working backward), then remove the start date filter.
        BOOL isMaxChunk = (i == (maxChunkCount - 1));
        BOOL chunkStartsBeforeBeginning = [chunkStart earlierDate:start] == chunkStart;
        if (isMaxChunk || chunkStartsBeforeBeginning) {
            chunkStart = nil;
        }
        
        // If this is our first chunk (working backward), then remove our end date filter.
        if (i == 0) {
            chunkEnd = nil;
        }
        
        OTLoadingChunk *chunk = [[OTLoadingChunk alloc] init];
        chunk.start = chunkStart;
        chunk.end = chunkEnd;
        [chunks addObject:chunk];
    }
    
#if !USE_KNOWN_CHUNK_SIZES
    // Sanity check to make sure we don't have wild chunks.
    NSTimeInterval timeOfLastChunk = [chunks.lastObject.end timeIntervalSinceDate:start];
    BOOL lastChunkIsTooChonky = timeOfLastChunk > (60 * 60 * 8);
    if (chunks.count < minChunkCount || lastChunkIsTooChonky) {
        // We couldn't hit our min chunk count. Let's just split it evenly.
        os_log_debug(OTLogLoading, "Will split chunks evenly");
        [chunks removeAllObjects];
        NSTimeInterval evenSplitInterval = [end timeIntervalSinceDate:start] / minChunkCount;
        chunkStart = end;
        for (int i = 0; i < minChunkCount; i++) {
            NSDate *chunkEnd = chunkStart;
            chunkStart = [chunkEnd dateByAddingTimeInterval:-evenSplitInterval];
            if (i == minChunkCount - 1) {
                chunkStart = nil;
            }
            if (i == 0) {
                chunkEnd = nil;
            }
            OTLoadingChunk *chunk = [[OTLoadingChunk alloc] init];
            chunk.start = chunkStart;
            chunk.end = chunkEnd;
            [chunks addObject:chunk];
        }
    }
#endif
    
    if (chunks.count == 0) {
        os_log_debug(OTLogLoading, "No chunks. Will load everything in one.");
        [chunks addObject:[OTLoadingChunk new]];
    }
    
    return [chunks copy];
}

// MARK: - Public

+ (BOOL)publicEnumerate:(NSURL *)logarchiveFileURL start:(NSDate *)start end:(NSDate *)end block:(BOOL (^)(id))block error:(NSError *__autoreleasing  _Nullable *)outError {
    NSError *error = nil;
    OSLogStore *store = [OSLogStore storeWithURL:logarchiveFileURL error:&error];
    
    if (!store || error) {
        if (outError) *outError = error;
        return NO;
    }
    
    OSLogPosition *position = nil;
    if (start) {
        position = [store positionWithDate:start];
    }
    
    OSLogEnumerator *enumerator = [store entriesEnumeratorWithOptions:0 position:position predicate:nil error:&error];
    if (!enumerator || error) {
        if (outError) *outError = error;
        return NO;
    }
    
    for (OSLogEntry *entry in enumerator) {
        __block BOOL stop = NO;
        NSDate *entryDate = entry.date;
        if ([entryDate compare:end] == NSOrderedDescending) {
            stop = YES;
        } else {
            stop = !block(entry);
        }
        
        if (stop) {
            break;
        }
    }
    
    return YES;
}

@end
