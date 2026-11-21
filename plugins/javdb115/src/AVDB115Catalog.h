#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Public DMM label → (prefix, pad width) seed from AVDB Build 282 / DMMLabelSeed.
NSDictionary<NSString *, NSDictionary *> *AVDB115DMMSeedTable(void);
NSDictionary * _Nullable AVDB115DMMSeedRuleForLabel(NSString *label);

@interface AVDB115CatalogNumber : NSObject
@property (nonatomic, readonly) NSString *label;   // lowercase, e.g. "ssis"
@property (nonatomic, readonly) NSInteger serial;  // 1
+ (nullable instancetype)parse:(NSString *)raw;
+ (nullable NSString *)identityKey:(NSString *)raw; // "SSIS-1"
+ (BOOL)identity:(NSString *)candidate matches:(NSString *)wanted;
@end

@interface AVDB115DMMCoverURLs : NSObject
+ (NSString *)awsHost;
+ (NSString *)picsHost;
+ (NSArray<NSString *> *)cidCandidatesForNumber:(NSString *)number;
+ (NSArray<NSString *> *)digitalURLsForCID:(NSString *)cid;
+ (NSArray<NSString *> *)legacyURLsForCID:(NSString *)cid;
+ (nullable NSString *)cidFromImageURL:(NSString *)source;
+ (NSArray<NSString *> *)upgradeImageURL:(NSString *)source;
@end

@interface AVDB115MGSCoverURLs : NSObject
+ (NSArray<NSString *> *)candidatesForNumber:(NSString *)number;
@end

@interface AVDB115AmazonImage : NSObject
+ (nullable NSURL *)originalImage:(NSURL *)url;
+ (BOOL)allowedImage:(NSURL *)url;
@end

@interface AVDB115CoverPolicy : NSObject
+ (BOOL)allowedPublicImageURL:(NSURL *)url;
+ (BOOL)allowedJavBusCoverURL:(NSURL *)url;
+ (BOOL)eligiblePortraitWidth:(NSInteger)width height:(NSInteger)height;
+ (BOOL)htmlLooksLikeChallenge:(NSString *)html finalURL:(nullable NSURL *)finalURL;
@end

NS_ASSUME_NONNULL_END
