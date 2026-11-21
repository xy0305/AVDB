#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const AVDB115ExternalLibraryErrorDomain;
typedef NS_ENUM(NSInteger, AVDB115ExternalLibraryErrorCode) {
    AVDB115ExternalLibraryErrorInvalidURL = 1,
    AVDB115ExternalLibraryErrorInvalidToken,
    AVDB115ExternalLibraryErrorEndpointNeedsToken,
    AVDB115ExternalLibraryErrorKeychain,
    AVDB115ExternalLibraryErrorHTTP,
    AVDB115ExternalLibraryErrorTransport,
    AVDB115ExternalLibraryErrorSchema,
};

/// User-configurable HTTP External Library (AVDB ExternalLibraryClient), not a JSON file import.
@interface AVDB115ExternalLink : NSObject
@property (nonatomic, readonly) NSInteger identifier;
@property (nonatomic, readonly, nullable) NSString *title;
@property (nonatomic, readonly) NSString *downloadURL;
@property (nonatomic, readonly, nullable) NSNumber *sizeMB;
@property (nonatomic, readonly, nullable) NSNumber *seeders;
@property (nonatomic, readonly, nullable) NSNumber *chinese;
@property (nonatomic, readonly, nullable) NSNumber *uncensored;
@property (nonatomic, readonly, nullable) NSNumber *uhd;
@property (nonatomic, readonly) BOOL isMagnet;
@property (nonatomic, readonly) BOOL isED2K;
+ (nullable instancetype)linkWithDictionary:(NSDictionary *)dict;
+ (nullable NSArray<AVDB115ExternalLink *> *)linksFromEnvelopeJSON:(NSData *)data error:(NSError **)error;
@end

@interface AVDB115ExternalLibrarySettings : NSObject
@property (class, readonly) AVDB115ExternalLibrarySettings *shared;
@property (nonatomic, readonly) NSString *baseURL;
@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) BOOL hasToken;
@property (nonatomic, readonly) NSUInteger revision;
@property (class, readonly) NSString *defaultBaseURL;
+ (nullable NSString *)normalizedURL:(NSString *)raw error:(NSError **)error;
+ (BOOL)isValidToken:(NSString *)token;
- (nullable NSString *)tokenWithError:(NSError **)error;
- (BOOL)saveBaseURL:(NSString *)raw enabled:(BOOL)enabled replacementToken:(NSString *)replacementToken error:(NSError **)error;
- (BOOL)clearTokenWithError:(NSError **)error;
@end

typedef void (^AVDB115ExternalLibraryCompletion)(NSArray<AVDB115ExternalLink *> * _Nullable links, NSError * _Nullable error);

@interface AVDB115ExternalLibraryClient : NSObject
@property (class, readonly) AVDB115ExternalLibraryClient *shared;
- (void)cancelRequests;
/// Returns an empty array (no error) when disabled or token is missing, matching AVDB fetchLinks.
- (void)fetchLinksForNumber:(NSString *)number completion:(AVDB115ExternalLibraryCompletion)completion;
@end

NS_ASSUME_NONNULL_END
