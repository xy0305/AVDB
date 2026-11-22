#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Capture-at-load / capture-at-build hooks for already-parsed Magnets.
///
/// JavDB 1.9.41:
/// - Magnets.fromJson (FAT 0xa03fc / vm 0x9c3fc) is an instance initializer:
///   x1 = this, and it returns null (x22). Hash/url are written onto this.
/// - MagnetListItem.build (FAT 0x57bacc / vm 0x577acc): x1 = this; the
///   Magnets field is at tagged 0x0f. build paints name / type / files_count
///   but does not drop hash/url from the object.
///
/// Does not hook or call getMovieMagnets, and does not forge jdsignature.
@interface AVDB115MagnetCaptureHook : NSObject
+ (void)install;
+ (BOOL)fromJsonInstalled;
+ (BOOL)buildInstalled;
@end

NS_ASSUME_NONNULL_END
