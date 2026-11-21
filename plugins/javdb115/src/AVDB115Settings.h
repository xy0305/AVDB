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
/// Read iOS Settings.app staging fields, move the cookie into Keychain, and delete plaintext UserDefaults.
+ (void)synchronizeFromSystemSettings;
@property (nonatomic, readonly) NSString *cookieStatus;
@end

NS_ASSUME_NONNULL_END
