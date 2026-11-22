#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Read Dio FileCacheStore bodies the app already wrote under `http_cache`
/// (and leftover `dio_cache.hive*`) after opening 磁鏈下載.
/// CachePolicy in this IPA is `request` (enum index 4); a body is only on
/// disk if the response was allowed to be stored. Never requests the API.
@interface AVDB115FileCacheHarvest : NSObject
+ (NSUInteger)harvest;
@end

NS_ASSUME_NONNULL_END
