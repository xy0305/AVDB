#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AVDB115AdBlockSettings : NSObject
@property (class, readonly) AVDB115AdBlockSettings *shared;
/// Default YES. Only blocks reliably identified in-house ad API requests.
@property (nonatomic) BOOL enabled;
@property (nonatomic, readonly) NSString *status;
@end

@interface AVDB115AdBlockPolicy : NSObject
/// True only for JavDB in-house ad inventory/log endpoints.
+ (BOOL)isAdRequestURL:(nullable NSString *)urlString;
+ (BOOL)isAdRequestURLObject:(nullable NSURL *)url;
/// True for movie/cover/playback/payment/auth/115/HQ sources that must never be blocked.
+ (BOOL)isProtectedURL:(nullable NSString *)urlString;
+ (void)installNativeHooks;
@end

NS_ASSUME_NONNULL_END
