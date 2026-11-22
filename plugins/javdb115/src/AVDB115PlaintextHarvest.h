#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Tap-time / opportunistic scan of already-mapped RW memory for UTF-8
/// magnet-list JSON (`"hash"` / `"url":"ed2k://"`) that may live in Dio
/// / dart:io buffers as raw bytes, not as Dart String objects (the v11
/// cid walk). Uses only heap-allocated state and vm_read_overwrite.
/// Does not patch App.framework and does not call getMovieMagnets.
@interface AVDB115PlaintextHarvest : NSObject
+ (NSUInteger)harvestMatchingCatalog:(nullable NSString *)number;
@end

NS_ASSUME_NONNULL_END
