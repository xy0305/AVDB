//
//  AVDB-Bridging-Header.h
//  AVDB
//
//  Build 353 full restoration, stage D (synced from AVFan Build 59,
//  run 45239463298 verified): exposes the MPlayNative-style spatial
//  audio ABI (MPlaySpatialBridge.h, which in turn includes the
//  vendored LibTrueHD / LibDTSX headers) and the custom
//  stream-protocol bridge (MPlayStreamBridge.h) to Swift.  This is
//  the app's only bridging surface; everything else in the target is
//  pure Swift / clang modules.  The import paths are relative to
//  this file so they resolve without relying on the headermap.
//

#import "Services/MPlayKit/Spatial/MPlaySpatialBridge.h"
#import "Services/MPlayKit/MPlayStreamBridge.h"
