#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AVDB115Settings : NSObject
@property (class, readonly) AVDB115Settings *shared;
@property (nonatomic, copy) NSString *cookie;
@property (nonatomic, copy) NSString *folderCID;
@property (nonatomic, readonly) BOOL isConfigured;
@property (nonatomic, readonly) NSString *missingHint;
+ (NSString *)normalizeCookie:(NSString *)raw;
+ (nullable NSString *)extractUIDFromCookie:(NSString *)cookie;
@end

NS_ASSUME_NONNULL_END
