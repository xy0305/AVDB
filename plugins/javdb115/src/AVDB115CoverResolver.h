#pragma once
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AVDB115CoverCandidate : NSObject
@property (nonatomic, readonly) NSString *url;
@property (nonatomic, readonly) NSString *source; // DMM / MGS / Avbase / JavBus / Amazon
@property (nonatomic, readonly) BOOL probed;
@property (nonatomic, readonly) BOOL reachable;
@property (nonatomic, readonly, nullable) NSString *message;
@property (nonatomic, readonly) NSInteger width;
@property (nonatomic, readonly) NSInteger height;
@property (nonatomic, readonly) BOOL eligiblePortrait;
@property (nonatomic, readonly, nullable) NSString *cachePath;
@end

@interface AVDB115CoverResolveResult : NSObject
@property (nonatomic, readonly) NSString *number;
@property (nonatomic, readonly) NSArray<AVDB115CoverCandidate *> *candidates;
@property (nonatomic, readonly) NSArray<NSString *> *notes; // scope, blocked sources, etc.
@end

typedef void (^AVDB115CoverCompletion)(AVDB115CoverResolveResult * _Nullable result, NSError * _Nullable error);
typedef void (^AVDB115CoverProgress)(AVDB115CoverResolveResult *partial);

@interface AVDB115CoverResolver : NSObject
@property (class, readonly) AVDB115CoverResolver *shared;
@property (nonatomic) BOOL enableDMM;
@property (nonatomic) BOOL enableMGS;
@property (nonatomic) BOOL enableAvbase;
@property (nonatomic) BOOL enableJavBus;
- (void)cancel;
- (void)clearCache;
- (NSUInteger)cacheFileCount;
- (void)resolveNumber:(NSString *)number
             progress:(nullable AVDB115CoverProgress)progress
           completion:(AVDB115CoverCompletion)completion;
+ (NSArray<NSDictionary *> *)deterministicCandidatesForNumber:(NSString *)number
                                                       enableDMM:(BOOL)dmm
                                                       enableMGS:(BOOL)mgs;
@end

NS_ASSUME_NONNULL_END
