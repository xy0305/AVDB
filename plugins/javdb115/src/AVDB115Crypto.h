// AVDB115Crypto.h
// m115 protocol adapted from SheltonZhu/115driver (MIT).
// See third_party/115driver-MIT.txt. Protocol obfuscation, not a DRM bypass.
// Ported to match AVDB Pan115Client.swift (repo xy0305/AVDB, unchanged through build 354).

#pragma once
#include <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AVDB115Crypto : NSObject
+ (NSArray<NSNumber *> *)deriveKey:(NSArray<NSNumber *> *)key count:(NSUInteger)count;
+ (NSData *)xorData:(NSData *)bytes key:(NSData *)key;
+ (NSData *)randomBytes:(NSUInteger)count error:(NSError **)error;
+ (NSData *)transform:(NSData *)input error:(NSError **)error;
+ (NSString *)encodeJSONData:(NSData *)data key:(NSData *)key error:(NSError **)error;
+ (NSData *)decodeText:(NSString *)text key:(NSData *)key error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
