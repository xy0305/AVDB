#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Native (ObjC) intercept of HTTP(S) responses the app already requested.
/// Hooks NSURLSession completion handlers and a pass-through NSURLProtocol.
/// Does not issue a new getMovieMagnets / signed request, does not forge
/// jdsignature, and does not patch App.framework or Flutter TEXT.
///
/// JavDB 1.9.41 loads the 磁鏈下載 list with Dio + dart:io SecureSocket
/// (URL `{baseUrl}/api/v2/movies/{id}/magnets`). Flutter.framework has no
/// NSURLSession symbols, so this hook may not see that TLS traffic. It is
/// still installed because it is reliable when any list request does go
/// through CFNetwork, and because it needs no vm_protect of executable
/// segments (device evidence: App.framework entry hooks never hid the v6
/// overlay on v7–v12 resigned sideloads).
@interface AVDB115HttpIntercept : NSObject
+ (void)install;
+ (BOOL)isInstalled;
@end

NS_ASSUME_NONNULL_END
