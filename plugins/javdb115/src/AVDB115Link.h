#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AVDB115Link : NSObject
+ (BOOL)isOfflineResource:(nullable NSString *)text;
+ (nullable NSString *)firstOfflineResourceIn:(nullable NSString *)text;
+ (NSArray<NSString *> *)offlineResourcesIn:(nullable NSString *)text;
+ (nullable NSString *)infoHashFromMagnet:(NSString *)magnet;
+ (nullable NSString *)displayNameFromLink:(NSString *)link;
@end

NS_ASSUME_NONNULL_END
