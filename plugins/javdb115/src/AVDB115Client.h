#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AVDB115PushStatus) {
    AVDB115PushStatusSuccess = 0,
    AVDB115PushStatusExists,
    AVDB115PushStatusFailed,
};

@interface AVDB115PushResult : NSObject
@property (nonatomic, assign) AVDB115PushStatus status;
@property (nonatomic, copy) NSString *message;
@end

@interface AVDB115OfflineTask : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) NSInteger statusCode;
@property (nonatomic, assign) double percent;
@property (nonatomic, copy) NSString *infoHash;
@property (nonatomic, copy) NSString *fileID;
@property (nonatomic, copy) NSString *dirID;
@property (nonatomic, copy) NSString *url;
@property (nonatomic, readonly) BOOL isDone;
@property (nonatomic, readonly) BOOL isFailed;
@property (nonatomic, readonly) BOOL isRunning;
@end

@interface AVDB115FileItem : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *pickCode;
@property (nonatomic, copy) NSString *fileID;
@property (nonatomic, copy) NSString *cid;
@property (nonatomic, assign) BOOL isDir;
@property (nonatomic, assign) int64_t size;
@property (nonatomic, readonly) BOOL isVideo;
@end

@interface AVDB115PlayStream : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *url;
@property (nonatomic, assign) NSInteger bandwidth;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *headers;
@property (nonatomic, assign) BOOL isOriginal;
@property (nonatomic, strong) NSDate *resolvedAt;
@end

@interface AVDB115Client : NSObject
@property (class, readonly) AVDB115Client *shared;
@property (class, readonly) NSString *safariUA;
+ (NSDictionary<NSString *, NSString *> *)playHeadersWithCookie:(NSString *)cookie;

- (void)addOfflineTask:(NSString *)link
                cookie:(NSString *)cookie
             folderCID:(NSString *)folderCID
            completion:(void (^)(AVDB115PushResult * _Nullable result, NSError * _Nullable error))completion;

- (void)waitOfflineReady:(NSString *)keyword
                  cookie:(NSString *)cookie
                 timeout:(NSTimeInterval)timeout
              completion:(void (^)(AVDB115OfflineTask * _Nullable task, NSError * _Nullable error))completion;

- (void)searchFiles:(NSString *)keyword
             cookie:(NSString *)cookie
              limit:(NSInteger)limit
         completion:(void (^)(NSArray<AVDB115FileItem *> * _Nullable files, NSError * _Nullable error))completion;

- (void)findMatchedVideos:(NSString *)keyword
                   cookie:(NSString *)cookie
                    limit:(NSInteger)limit
               completion:(void (^)(NSArray<AVDB115FileItem *> * _Nullable files, NSError * _Nullable error))completion;

- (void)findMatchedVideo:(NSString *)keyword
                  cookie:(NSString *)cookie
               folderCID:(nullable NSString *)folderCID
            requireMatch:(BOOL)requireMatch
              completion:(void (^)(AVDB115FileItem * _Nullable file, NSError * _Nullable error))completion;

- (void)streamsForVideo:(NSString *)pickCode
                 cookie:(NSString *)cookie
             completion:(void (^)(NSArray<AVDB115PlayStream *> * _Nullable streams, NSError * _Nullable error))completion;

- (void)originalStream:(NSString *)pickCode
                cookie:(NSString *)cookie
            completion:(void (^)(AVDB115PlayStream * _Nullable stream, NSError * _Nullable error))completion;

/// Exposed for host-side / unit tests of response parsing.
+ (AVDB115PushResult *)parsePushResponseData:(NSData *)data;
+ (NSArray<AVDB115PlayStream *> *)parseMasterPlaylist:(NSString *)text;
+ (BOOL)name:(NSString *)filename matchesKeyword:(NSString *)keyword;
@end

NS_ASSUME_NONNULL_END
