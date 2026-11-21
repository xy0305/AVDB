#import "AVDB115Client.h"
#import "AVDB115Settings.h"
#import "AVDB115Crypto.h"

static NSString *AVDB115FormEncode(NSString *s) {
    NSMutableCharacterSet *allowed = [NSMutableCharacterSet alphanumericCharacterSet];
    [allowed addCharactersInString:@"-._~"];
    return [s stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: s;
}

static NSError *AVDB115Err(NSInteger code, NSString *msg) {
    return [NSError errorWithDomain:@"AVDB115Client" code:code userInfo:@{NSLocalizedDescriptionKey: msg ?: @"115 错误"}];
}

@implementation AVDB115PushResult
@end

@implementation AVDB115OfflineTask
- (BOOL)isDone { return self.statusCode == 2; }
- (BOOL)isFailed { return self.statusCode == -1; }
- (BOOL)isRunning { return self.statusCode == 0 || self.statusCode == 1; }
@end

@implementation AVDB115FileItem
- (BOOL)isVideo {
    NSString *n = self.name.lowercaseString;
    for (NSString *ext in @[@"mp4", @"mkv", @"avi", @"mov", @"wmv", @"flv", @"ts", @"m2ts", @"webm", @"m4v", @"iso"]) {
        if ([n hasSuffix:[@"." stringByAppendingString:ext]]) return YES;
    }
    return NO;
}
@end

@implementation AVDB115PlayStream
@end

@interface AVDB115Client ()
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation AVDB115Client

+ (AVDB115Client *)shared {
    static AVDB115Client *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[AVDB115Client alloc] init]; });
    return instance;
}

+ (NSString *)safariUA {
    return @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Safari/605.1.15";
}

+ (NSDictionary<NSString *, NSString *> *)playHeadersWithCookie:(NSString *)cookie {
    return @{
        @"User-Agent": self.safariUA,
        @"Accept": @"*/*",
        @"Origin": @"https://115.com",
        @"Referer": @"https://115.com/",
        @"Cookie": [AVDB115Settings normalizeCookie:cookie] ?: @"",
    };
}

- (instancetype)init {
    if (self = [super init]) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        config.timeoutIntervalForRequest = 25;
        config.timeoutIntervalForResource = 40;
        config.HTTPShouldSetCookies = NO;
        config.HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicyNever;
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}


+ (NSDictionary<NSString *, NSString *> *)stringFieldsFromHTTPResponse:(NSHTTPURLResponse *)http {
    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    [http.allHeaderFields enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if (key && obj) fields[[key description]] = [obj description];
    }];
    return fields;
}

- (void)applyCommonHeaders:(NSMutableURLRequest *)req cookie:(NSString *)cookie {
    NSDictionary *h = [AVDB115Client playHeadersWithCookie:cookie];
    [req setValue:h[@"User-Agent"] forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"application/json, text/javascript, */*; q=0.01" forHTTPHeaderField:@"Accept"];
    [req setValue:@"XMLHttpRequest" forHTTPHeaderField:@"X-Requested-With"];
    [req setValue:h[@"Origin"] forHTTPHeaderField:@"Origin"];
    [req setValue:h[@"Referer"] forHTTPHeaderField:@"Referer"];
    [req setValue:h[@"Cookie"] forHTTPHeaderField:@"Cookie"];
}

- (void)dataForRequest:(NSURLRequest *)req completion:(void (^)(NSData *data, NSHTTPURLResponse *http, NSError *error))completion {
    [[self.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(data, http, error);
        });
    }] resume];
}

- (void)jsonForRequest:(NSURLRequest *)req retries:(NSInteger)retries completion:(void (^)(NSDictionary *obj, NSError *error))completion {
    [self dataForRequest:req completion:^(NSData *data, NSHTTPURLResponse *http, NSError *error) {
        if (error) {
            if (retries > 0) {
                [self jsonForRequest:req retries:retries - 1 completion:completion];
                return;
            }
            completion(nil, error);
            return;
        }
        if (http && http.statusCode >= 400) {
            if (retries > 0) {
                [self jsonForRequest:req retries:retries - 1 completion:completion];
                return;
            }
            completion(nil, AVDB115Err(http.statusCode, [NSString stringWithFormat:@"115 接口 HTTP %ld", (long)http.statusCode]));
            return;
        }
        NSString *text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        if (text && [text.lowercaseString containsString:@"<html"]) {
            completion(nil, AVDB115Err(401, @"115 Cookie 无效或已过期，请重新填写 UID/CID/SEID"));
            return;
        }
        id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (![obj isKindOfClass:[NSDictionary class]]) {
            completion(nil, AVDB115Err(2, @"接口返回不是 JSON"));
            return;
        }
        completion(obj, nil);
    }];
}

#pragma mark - Push

- (void)fetchSign:(NSString *)cookie completion:(void (^)(NSString *sign, NSString *time, NSError *error))completion {
    long long ts = (long long)([[NSDate date] timeIntervalSince1970] * 1000);
    NSString *url = [NSString stringWithFormat:@"https://115.com/?ct=offline&ac=space&_=%lld", ts];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    req.HTTPMethod = @"GET";
    [self applyCommonHeaders:req cookie:cookie];
    [self dataForRequest:req completion:^(NSData *data, NSHTTPURLResponse *http, NSError *error) {
        (void)http;
        if (error) { completion(nil, nil, error); return; }
        NSString *text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        if (!text || [text.lowercaseString containsString:@"<html"]) {
            completion(nil, nil, AVDB115Err(401, @"115 Cookie 无效或已过期，请重新填写 UID/CID/SEID"));
            return;
        }
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *sign = [obj isKindOfClass:[NSDictionary class]] ? obj[@"sign"] : nil;
        id timeVal = [obj isKindOfClass:[NSDictionary class]] ? obj[@"time"] : nil;
        NSString *time = [timeVal isKindOfClass:[NSString class]] ? timeVal : ([timeVal respondsToSelector:@selector(stringValue)] ? [timeVal stringValue] : [NSString stringWithFormat:@"%lld", ts]);
        if (![sign isKindOfClass:[NSString class]] || sign.length == 0) {
            completion(nil, nil, AVDB115Err(3, @"获取 115 签名失败"));
            return;
        }
        completion(sign, time, nil);
    }];
}

- (void)addOfflineTask:(NSString *)link cookie:(NSString *)cookie folderCID:(NSString *)folderCID completion:(void (^)(AVDB115PushResult *, NSError *))completion {
    NSString *ck = [AVDB115Settings normalizeCookie:cookie];
    NSString *folder = [folderCID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *url = [link stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (url.length == 0) { completion(nil, AVDB115Err(4, @"磁力链接为空")); return; }
    if (![ck containsString:@"UID="] || ![ck containsString:@"CID="] || ![ck containsString:@"SEID="]) {
        completion(nil, AVDB115Err(401, @"115 Cookie 无效或已过期，请重新填写 UID/CID/SEID"));
        return;
    }
    if (folder.length == 0) { completion(nil, AVDB115Err(5, @"请先填写 115 离线目录 CID")); return; }

    NSString *uid = [AVDB115Settings extractUIDFromCookie:ck] ?: @"";
    [self fetchSign:ck completion:^(NSString *sign, NSString *time, NSError *error) {
        (void)error; // sign is optional; AVDB still posts without it if fetch fails
        NSMutableArray *parts = [NSMutableArray array];
        [parts addObject:[NSString stringWithFormat:@"url=%@", AVDB115FormEncode(url)]];
        [parts addObject:[NSString stringWithFormat:@"wp_path_id=%@", AVDB115FormEncode(folder)]];
        if (uid.length) [parts addObject:[NSString stringWithFormat:@"uid=%@", AVDB115FormEncode(uid)]];
        if (sign.length) {
            [parts addObject:[NSString stringWithFormat:@"sign=%@", AVDB115FormEncode(sign)]];
            [parts addObject:[NSString stringWithFormat:@"time=%@", AVDB115FormEncode(time ?: @"")]];
        }
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://115.com/web/lixian/?ct=lixian&ac=add_task_url"]];
        req.HTTPMethod = @"POST";
        req.HTTPBody = [[parts componentsJoinedByString:@"&"] dataUsingEncoding:NSUTF8StringEncoding];
        [req setValue:@"application/x-www-form-urlencoded; charset=UTF-8" forHTTPHeaderField:@"Content-Type"];
        [self applyCommonHeaders:req cookie:ck];
        [self dataForRequest:req completion:^(NSData *data, NSHTTPURLResponse *http, NSError *netErr) {
            if (netErr) { completion(nil, netErr); return; }
            if (http && http.statusCode >= 400) {
                completion(nil, AVDB115Err(http.statusCode, [NSString stringWithFormat:@"115 接口 HTTP %ld", (long)http.statusCode]));
                return;
            }
            completion([AVDB115Client parsePushResponseData:data], nil);
        }];
    }];
}

+ (AVDB115PushResult *)parsePushResponseData:(NSData *)data {
    AVDB115PushResult *result = [AVDB115PushResult new];
    NSString *text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    if (text.length == 0) {
        result.status = AVDB115PushStatusFailed;
        result.message = @"接口无返回";
        return result;
    }
    if ([text.lowercaseString containsString:@"<html"] || [text containsString:@"登录"]) {
        result.status = AVDB115PushStatusFailed;
        result.message = @"Cookie 无效或已过期";
        return result;
    }
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![obj isKindOfClass:[NSDictionary class]]) {
        result.status = AVDB115PushStatusFailed;
        result.message = @"接口返回不是 JSON";
        return result;
    }
    id state = obj[@"state"];
    BOOL ok = [state isEqual:@YES] || [state isEqual:@1] || [state isEqual:@"1"];
    if (ok) {
        result.status = AVDB115PushStatusSuccess;
        result.message = @"已推送到 115";
        return result;
    }
    NSString *msg = obj[@"error_msg"] ?: obj[@"error"] ?: obj[@"msg"] ?: @"";
    if (![msg isKindOfClass:[NSString class]]) msg = [msg description] ?: @"";
    NSInteger errcode = 0;
    id code = obj[@"errcode"] ?: obj[@"errno"];
    if ([code respondsToSelector:@selector(integerValue)]) errcode = [code integerValue];
    if (errcode == 10008 || [msg containsString:@"已存在"] || [msg containsString:@"重复"]) {
        result.status = AVDB115PushStatusExists;
        result.message = @"115 任务已存在";
        return result;
    }
    result.status = AVDB115PushStatusFailed;
    result.message = msg.length ? msg : @"添加失败";
    return result;
}

#pragma mark - Tasks / search

- (void)listOfflineTasks:(NSString *)cookie page:(NSInteger)page completion:(void (^)(NSArray<AVDB115OfflineTask *> *, NSError *))completion {
    NSString *u = [NSString stringWithFormat:@"https://115.com/web/lixian/?ct=lixian&ac=task_lists&page=%ld", (long)page];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:u]];
    req.HTTPMethod = @"GET";
    [self applyCommonHeaders:req cookie:cookie];
    [self jsonForRequest:req retries:1 completion:^(NSDictionary *obj, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSArray *raw = obj[@"tasks"];
        if (![raw isKindOfClass:[NSArray class]]) {
            id data = obj[@"data"];
            raw = [data isKindOfClass:[NSDictionary class]] ? data[@"tasks"] : nil;
        }
        if (![raw isKindOfClass:[NSArray class]]) raw = @[];
        NSMutableArray *tasks = [NSMutableArray array];
        for (id item in raw) {
            if (![item isKindOfClass:[NSDictionary class]]) continue;
            AVDB115OfflineTask *t = [AVDB115OfflineTask new];
            t.name = [item[@"name"] isKindOfClass:[NSString class]] ? item[@"name"] : @"";
            t.statusCode = [self intValue:item[@"status"]];
            t.percent = [self doubleValue:item[@"percentDone"] ?: item[@"percent"]];
            t.infoHash = item[@"info_hash"] ?: item[@"hash"] ?: @"";
            if (![t.infoHash isKindOfClass:[NSString class]]) t.infoHash = [t.infoHash description];
            t.fileID = [self stringValue:item[@"file_id"] ?: item[@"delete_file_id"]];
            t.dirID = [self stringValue:item[@"wp_path_id"] ?: item[@"file_id"]];
            t.url = [item[@"url"] isKindOfClass:[NSString class]] ? item[@"url"] : @"";
            [tasks addObject:t];
        }
        completion(tasks, nil);
    }];
}

- (void)waitOfflineReady:(NSString *)keyword cookie:(NSString *)cookie timeout:(NSTimeInterval)timeout completion:(void (^)(AVDB115OfflineTask *, NSError *))completion {
    NSString *ck = [AVDB115Settings normalizeCookie:cookie];
    NSString *needle = keyword.lowercaseString ?: @"";
    NSDate *start = [NSDate date];
    __block AVDB115OfflineTask *last = nil;
    __weak typeof(self) weakSelf = self;
    __block void (^poll)(void);
    poll = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if ([[NSDate date] timeIntervalSinceDate:start] >= timeout) {
            if (last.isDone) { completion(last, nil); return; }
            [self findMatchedVideo:keyword cookie:ck folderCID:nil requireMatch:YES completion:^(AVDB115FileItem *file, NSError *error) {
                if (file) {
                    AVDB115OfflineTask *t = [AVDB115OfflineTask new];
                    t.name = file.name; t.statusCode = 2; t.percent = 100;
                    t.infoHash = @""; t.fileID = file.fileID; t.dirID = file.cid; t.url = @"";
                    completion(t, nil);
                } else {
                    completion(nil, error ?: AVDB115Err(6, @"等待 115 离线完成超时"));
                }
            }];
            return;
        }
        [self listOfflineTasks:ck page:1 completion:^(NSArray<AVDB115OfflineTask *> *tasks, NSError *error) {
            (void)error;
            AVDB115OfflineTask *hit = nil;
            for (AVDB115OfflineTask *task in tasks ?: @[]) {
                if ([task.name.lowercaseString containsString:needle]
                    || [task.url.lowercaseString containsString:needle]
                    || (task.infoHash.length && [needle containsString:task.infoHash.lowercaseString])) {
                    hit = task;
                    break;
                }
            }
            if (hit) {
                last = hit;
                if (hit.isDone) { completion(hit, nil); return; }
                if (hit.isFailed) {
                    completion(nil, AVDB115Err(7, [NSString stringWithFormat:@"115 离线失败：%@", hit.name]));
                    return;
                }
            } else {
                [self findMatchedVideo:keyword cookie:ck folderCID:nil requireMatch:YES completion:^(AVDB115FileItem *file, NSError *error) {
                    (void)error;
                    if (file) {
                        AVDB115OfflineTask *t = [AVDB115OfflineTask new];
                        t.name = file.name; t.statusCode = 2; t.percent = 100;
                        t.infoHash = @""; t.fileID = file.fileID; t.dirID = file.cid; t.url = @"";
                        completion(t, nil);
                        return;
                    }
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), poll);
                }];
                return;
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), poll);
        }];
    };
    poll();
}

- (void)listFilesInCID:(NSString *)cid cookie:(NSString *)cookie limit:(NSInteger)limit completion:(void (^)(NSArray<AVDB115FileItem *> *, NSError *))completion {
    NSString *q = [NSString stringWithFormat:@"aid=1&cid=%@&o=user_ptime&asc=0&offset=0&show_dir=1&limit=%ld&natsort=1&record_open_time=1&format=json", AVDB115FormEncode(cid), (long)limit];
    NSArray *urls = @[
        [@"https://aps.115.com/natsort/files.php?" stringByAppendingString:q],
        [@"https://proapi.115.com/android/2.0/ufile/files?" stringByAppendingString:q],
        [@"https://webapi.115.com/files?" stringByAppendingString:q],
    ];
    [self tryURLs:urls cookie:cookie requireNonEmpty:NO completion:completion];
}

- (void)searchFiles:(NSString *)keyword cookie:(NSString *)cookie limit:(NSInteger)limit completion:(void (^)(NSArray<AVDB115FileItem *> *, NSError *))completion {
    NSString *kw = [keyword stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *encoded = AVDB115FormEncode(kw.length ? kw : @".mp4");
    NSArray *urls = @[
        [NSString stringWithFormat:@"https://proapi.115.com/android/2.0/ufile/search?search_value=%@&limit=%ld&offset=0&type=4&format=json", encoded, (long)limit],
        [NSString stringWithFormat:@"https://aps.115.com/natsort/files.php?search_value=%@&type=4&limit=%ld&offset=0&format=json", encoded, (long)limit],
        [NSString stringWithFormat:@"https://webapi.115.com/files/search?search_value=%@&limit=%ld&offset=0&type=4&format=json", encoded, (long)limit],
        [NSString stringWithFormat:@"https://webapi.115.com/files/search?search_value=%@&limit=%ld&offset=0&format=json", encoded, (long)limit],
    ];
    [self tryURLs:urls cookie:cookie requireNonEmpty:YES completion:completion];
}

- (void)tryURLs:(NSArray<NSString *> *)urls cookie:(NSString *)cookie requireNonEmpty:(BOOL)requireNonEmpty completion:(void (^)(NSArray<AVDB115FileItem *> *, NSError *))completion {
    __block NSError *lastError = AVDB115Err(8, @"离线目录里没找到与当前番号匹配的视频");
    __block NSUInteger idx = 0;
    __weak typeof(self) weakSelf = self;
    __block void (^next)(void);
    next = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (idx >= urls.count) { completion(nil, lastError); return; }
        NSString *u = urls[idx++];
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:u]];
        req.HTTPMethod = @"GET";
        [self applyCommonHeaders:req cookie:cookie];
        [self jsonForRequest:req retries:1 completion:^(NSDictionary *obj, NSError *error) {
            if (error) { lastError = error; next(); return; }
            NSArray *files = [self extractFileList:obj];
            BOOL ok = [self boolState:obj[@"state"]] || files.count > 0;
            if (requireNonEmpty) {
                if (files.count > 0) { completion(files, nil); return; }
                if ([self boolState:obj[@"state"]]) { completion(@[], nil); return; }
                next();
                return;
            }
            if (ok) { completion(files, nil); return; }
            next();
        }];
    };
    next();
}

- (void)findMatchedVideos:(NSString *)keyword cookie:(NSString *)cookie limit:(NSInteger)limit completion:(void (^)(NSArray<AVDB115FileItem *> *, NSError *))completion {
    NSString *needle = [self normalizedKey:keyword];
    if (needle.length == 0) { completion(nil, AVDB115Err(8, @"离线目录里没找到与当前番号匹配的视频")); return; }
    NSArray *variants = [self searchKeywordsFrom:keyword];
    NSMutableArray *result = [NSMutableArray array];
    NSMutableSet *known = [NSMutableSet set];
    __block NSError *lastError = AVDB115Err(8, @"离线目录里没找到与当前番号匹配的视频");
    __block NSUInteger idx = 0;
    __weak typeof(self) weakSelf = self;
    __block void (^next)(void);
    next = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (idx >= variants.count) {
            if (result.count == 0) { completion(nil, lastError); return; }
            [result sortUsingComparator:^NSComparisonResult(AVDB115FileItem *a, AVDB115FileItem *b) {
                NSInteger la = [self episodeNumber:a.name];
                NSInteger lb = [self episodeNumber:b.name];
                if (la != lb) return la < lb ? NSOrderedAscending : NSOrderedDescending;
                return [a.name localizedStandardCompare:b.name];
            }];
            completion(result, nil);
            return;
        }
        NSString *variant = variants[idx++];
        [self searchFiles:variant cookie:cookie limit:limit completion:^(NSArray<AVDB115FileItem *> *files, NSError *error) {
            if (error) lastError = error;
            for (AVDB115FileItem *file in files ?: @[]) {
                if (file.isDir || !file.isVideo || file.pickCode.length == 0) continue;
                if (![AVDB115Client name:file.name matchesKeyword:keyword]) continue;
                NSString *key = file.fileID.length ? file.fileID : file.pickCode;
                if ([known containsObject:key]) continue;
                [known addObject:key];
                [result addObject:file];
            }
            next();
        }];
    };
    next();
}

- (void)findMatchedVideo:(NSString *)keyword cookie:(NSString *)cookie folderCID:(NSString *)folderCID requireMatch:(BOOL)requireMatch completion:(void (^)(AVDB115FileItem *, NSError *))completion {
    NSString *needle = [self normalizedKey:keyword];
    if (needle.length == 0) { completion(nil, AVDB115Err(8, @"离线目录里没找到与当前番号匹配的视频")); return; }
    NSArray *variants = [self searchKeywordsFrom:keyword];
    __block NSError *lastSearchError = AVDB115Err(8, @"离线目录里没找到与当前番号匹配的视频");
    __block NSUInteger idx = 0;
    __weak typeof(self) weakSelf = self;
    __block void (^next)(void);
    next = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (idx >= variants.count) {
            if (folderCID.length) {
                [self listFilesInCID:folderCID cookie:cookie limit:500 completion:^(NSArray<AVDB115FileItem *> *files, NSError *error) {
                    (void)error;
                    AVDB115FileItem *hit = [self pickVideoFrom:files keyword:keyword requireMatch:requireMatch];
                    if (hit) { completion(hit, nil); return; }
                    completion(nil, lastSearchError);
                }];
                return;
            }
            completion(nil, lastSearchError);
            return;
        }
        NSString *kw = variants[idx++];
        [self searchFiles:kw cookie:cookie limit:30 completion:^(NSArray<AVDB115FileItem *> *files, NSError *error) {
            if (error) lastSearchError = error;
            AVDB115FileItem *hit = [self pickVideoFrom:files keyword:keyword requireMatch:YES];
            if (hit) { completion(hit, nil); return; }
            next();
        }];
    };
    next();
}

#pragma mark - Play URLs

- (void)streamsForVideo:(NSString *)pickCode cookie:(NSString *)cookie completion:(void (^)(NSArray<AVDB115PlayStream *> *, NSError *))completion {
    NSURL *m3u8URL = [NSURL URLWithString:[NSString stringWithFormat:@"https://115.com/api/video/m3u8/%@.m3u8", AVDB115FormEncode(pickCode)]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:m3u8URL];
    req.HTTPMethod = @"GET";
    [self applyCommonHeaders:req cookie:cookie];
    [req setValue:@"*/*" forHTTPHeaderField:@"Accept"];
    [self dataForRequest:req completion:^(NSData *data, NSHTTPURLResponse *http, NSError *error) {
        if (error || !http || http.statusCode != 200) {
            completion(nil, error ?: AVDB115Err(9, @"无法获取 115 原画播放地址"));
            return;
        }
        NSMutableDictionary *sourceHeaders = [[AVDB115Client playHeadersWithCookie:cookie] mutableCopy];
        NSArray *responseCookies = [NSHTTPCookie cookiesWithResponseHeaderFields:[AVDB115Client stringFieldsFromHTTPResponse:http] forURL:m3u8URL];
        if (responseCookies.count) {
            NSMutableArray *pairs = [NSMutableArray array];
            for (NSHTTPCookie *c in responseCookies) {
                [pairs addObject:[NSString stringWithFormat:@"%@=%@", c.name, c.value]];
            }
            NSString *old = sourceHeaders[@"Cookie"] ?: @"";
            sourceHeaders[@"Cookie"] = [[old stringByAppendingString:@"; "] stringByAppendingString:[pairs componentsJoinedByString:@"; "]];
        }
        NSString *text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        if (text && [text containsString:@"#EXTM3U"]) {
            NSArray *parsed = [AVDB115Client parseMasterPlaylist:text];
            if (parsed.count) {
                for (AVDB115PlayStream *stream in parsed) stream.headers = sourceHeaders;
                completion(parsed, nil);
                return;
            }
            if (![text containsString:@"#EXT-X-STREAM-INF"]) {
                AVDB115PlayStream *s = [AVDB115PlayStream new];
                s.name = @"HLS"; s.url = m3u8URL.absoluteString; s.bandwidth = 0;
                s.headers = sourceHeaders; s.resolvedAt = [NSDate date];
                completion(@[s], nil);
                return;
            }
        }
        completion(nil, AVDB115Err(9, @"无法获取 115 原画播放地址"));
    }];
}

- (void)originalStream:(NSString *)pickCode cookie:(NSString *)cookie completion:(void (^)(AVDB115PlayStream *, NSError *))completion {
    if (pickCode.length == 0) { completion(nil, AVDB115Err(9, @"无法获取 115 原画播放地址")); return; }
    NSError *err = nil;
    NSData *key = [AVDB115Crypto randomBytes:16 error:&err];
    if (!key) { completion(nil, err); return; }
    NSData *payload = [NSJSONSerialization dataWithJSONObject:@{@"pickcode": pickCode} options:0 error:&err];
    if (!payload) { completion(nil, err); return; }
    NSString *encoded = [AVDB115Crypto encodeJSONData:payload key:key error:&err];
    if (!encoded) { completion(nil, err); return; }
    long t = (long)[[NSDate date] timeIntervalSince1970];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://proapi.115.com/app/chrome/downurl?t=%ld", t]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [self applyCommonHeaders:request cookie:cookie];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = [[NSString stringWithFormat:@"data=%@", AVDB115FormEncode(encoded)] dataUsingEncoding:NSUTF8StringEncoding];
    [self dataForRequest:request completion:^(NSData *data, NSHTTPURLResponse *http, NSError *error) {
        if (error || !http || http.statusCode != 200) {
            completion(nil, error ?: AVDB115Err(9, @"无法获取 115 原画播放地址"));
            return;
        }
        id envelope = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (![envelope isKindOfClass:[NSDictionary class]] || ![envelope[@"state"] isEqual:@YES]
            || ![envelope[@"data"] isKindOfClass:[NSString class]]) {
            completion(nil, AVDB115Err(9, @"无法获取 115 原画播放地址"));
            return;
        }
        NSError *decErr = nil;
        NSData *decoded = [AVDB115Crypto decodeText:envelope[@"data"] key:key error:&decErr];
        id files = decoded ? [NSJSONSerialization JSONObjectWithData:decoded options:0 error:nil] : nil;
        if (![files isKindOfClass:[NSDictionary class]]) {
            completion(nil, decErr ?: AVDB115Err(9, @"无法获取 115 原画播放地址"));
            return;
        }
        NSMutableArray *matches = [NSMutableArray array];
        for (id value in [files allValues]) {
            if ([value isKindOfClass:[NSDictionary class]] && [value[@"pick_code"] isEqualToString:pickCode]) {
                [matches addObject:value];
            }
        }
        if (matches.count != 1) { completion(nil, AVDB115Err(9, @"无法获取 115 原画播放地址")); return; }
        id nested = matches[0][@"url"];
        NSString *text = [nested isKindOfClass:[NSDictionary class]] ? nested[@"url"] : nil;
        NSURL *playURL = [text isKindOfClass:[NSString class]] ? [NSURL URLWithString:text] : nil;
        NSString *scheme = playURL.scheme.lowercaseString;
        if (!playURL || !([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"])
            || playURL.host.length == 0 || playURL.user.length || playURL.password.length) {
            completion(nil, AVDB115Err(9, @"无法获取 115 原画播放地址"));
            return;
        }
        NSMutableDictionary *headers = [[AVDB115Client playHeadersWithCookie:cookie] mutableCopy];
        NSMutableDictionary *pairs = [NSMutableDictionary dictionary];
        for (NSString *item in [[AVDB115Settings normalizeCookie:cookie] componentsSeparatedByString:@";"]) {
            NSString *trim = [item stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            NSRange eq = [trim rangeOfString:@"="];
            if (eq.location != NSNotFound) {
                pairs[[trim substringToIndex:eq.location]] = [trim substringFromIndex:eq.location + 1];
            }
        }
        for (NSHTTPCookie *c in [NSHTTPCookie cookiesWithResponseHeaderFields:[AVDB115Client stringFieldsFromHTTPResponse:http] forURL:request.URL]) {
            pairs[c.name] = c.value;
        }
        NSArray *keys = [pairs.allKeys sortedArrayUsingSelector:@selector(compare:)];
        NSMutableArray *joined = [NSMutableArray array];
        for (NSString *k in keys) [joined addObject:[NSString stringWithFormat:@"%@=%@", k, pairs[k]]];
        headers[@"Cookie"] = [joined componentsJoinedByString:@"; "];
        AVDB115PlayStream *stream = [AVDB115PlayStream new];
        stream.name = @"原文件 / 原画";
        stream.url = playURL.absoluteString;
        stream.bandwidth = 0;
        stream.headers = headers;
        stream.isOriginal = YES;
        stream.resolvedAt = [NSDate date];
        completion(stream, nil);
    }];
}

#pragma mark - Parsing helpers

- (NSInteger)intValue:(id)v {
    if ([v isKindOfClass:[NSNumber class]] || [v isKindOfClass:[NSString class]]) return [v integerValue];
    return 0;
}
- (double)doubleValue:(id)v {
    if ([v isKindOfClass:[NSNumber class]] || [v isKindOfClass:[NSString class]]) return [v doubleValue];
    return 0;
}
- (NSString *)stringValue:(id)v {
    if ([v isKindOfClass:[NSString class]]) return v;
    if ([v isKindOfClass:[NSNumber class]]) return [v stringValue];
    return @"";
}
- (BOOL)boolState:(id)state {
    return [state isEqual:@YES] || [state isEqual:@1] || [state isEqual:@"1"] || [state isEqual:@"true"];
}

- (NSArray<AVDB115FileItem *> *)extractFileList:(NSDictionary *)obj {
    NSArray *raw = nil;
    NSArray * (^asList)(id) = ^NSArray *(id value) {
        if ([value isKindOfClass:[NSArray class]]) return value;
        return nil;
    };
    NSArray * (^fromDict)(NSDictionary *) = ^NSArray *(NSDictionary *dict) {
        for (NSString *key in @[@"data", @"list", @"files", @"items", @"videos"]) {
            NSArray *arr = asList(dict[key]);
            if (arr) return arr;
        }
        for (id v in dict.allValues) {
            NSArray *arr = asList(v);
            if (arr) return arr;
        }
        return @[dict];
    };
    if ([obj[@"data"] isKindOfClass:[NSArray class]]) raw = obj[@"data"];
    else if ([obj[@"data"] isKindOfClass:[NSDictionary class]]) raw = fromDict(obj[@"data"]);
    if (!raw && [obj[@"list"] isKindOfClass:[NSArray class]]) raw = obj[@"list"];
    if (!raw && [obj[@"files"] isKindOfClass:[NSArray class]]) raw = obj[@"files"];
    if (!raw) raw = fromDict(obj);
    NSMutableArray *items = [NSMutableArray array];
    for (id item in raw) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        AVDB115FileItem *f = [AVDB115FileItem new];
        f.name = item[@"n"] ?: item[@"fn"] ?: item[@"name"] ?: item[@"file_name"] ?: item[@"filename"] ?: @"";
        if (![f.name isKindOfClass:[NSString class]]) f.name = @"";
        f.pickCode = item[@"pc"] ?: item[@"pick_code"] ?: item[@"pickcode"] ?: item[@"pickCode"] ?: @"";
        if (![f.pickCode isKindOfClass:[NSString class]]) f.pickCode = @"";
        f.fileID = [self stringValue:item[@"fid"] ?: item[@"file_id"] ?: item[@"id"]];
        NSString *cid = [self stringValue:item[@"cid"] ?: item[@"pid"]];
        f.cid = cid.length ? cid : f.fileID;
        BOOL noHash = (item[@"pc"] == nil && item[@"pick_code"] == nil && item[@"pickcode"] == nil && item[@"sha"] == nil && item[@"sha1"] == nil);
        f.isDir = (noHash && cid.length && f.pickCode.length == 0) || [self intValue:item[@"fc"]] == 0;
        f.size = (int64_t)[self doubleValue:item[@"s"] ?: item[@"fs"] ?: item[@"size"]];
        [items addObject:f];
    }
    return items;
}

- (AVDB115FileItem *)pickVideoFrom:(NSArray<AVDB115FileItem *> *)files keyword:(NSString *)keyword requireMatch:(BOOL)requireMatch {
    NSMutableArray *videos = [NSMutableArray array];
    for (AVDB115FileItem *f in files ?: @[]) {
        if (!f.isDir && f.isVideo && f.pickCode.length) [videos addObject:f];
    }
    if (videos.count == 0) {
        for (AVDB115FileItem *f in files ?: @[]) {
            if (!f.isDir && f.pickCode.length && f.size > 10000000) [videos addObject:f];
        }
    }
    NSArray *scored = videos;
    if (keyword.length) {
        NSMutableArray *hits = [NSMutableArray array];
        for (AVDB115FileItem *f in videos) {
            if ([AVDB115Client name:f.name matchesKeyword:keyword]) [hits addObject:f];
        }
        if (hits.count == 0 && requireMatch) return nil;
        scored = hits.count || requireMatch ? hits : videos;
    } else if (requireMatch) {
        return nil;
    }
    AVDB115FileItem *best = nil;
    NSInteger bestScore = NSIntegerMin;
    for (AVDB115FileItem *f in scored) {
        NSInteger s = [self scoreFile:f];
        if (!best || s > bestScore) { best = f; bestScore = s; }
    }
    return best;
}

- (NSInteger)scoreFile:(AVDB115FileItem *)file {
    NSInteger s = 0;
    NSString *n = file.name.lowercaseString;
    for (NSString *bad in @[@"trailer", @"sample", @"preview", @"behind", @"bts"]) {
        if ([n containsString:bad]) s -= 50;
    }
    if (file.size >= 2000000000) s += 30;
    else if (file.size >= 1000000000) s += 20;
    else if (file.size >= 500000000) s += 10;
    else if (file.size > 0 && file.size < 100000000) s -= 20;
    if (n.length > 30) s += 5;
    s += (NSInteger)MIN(file.size / 50000000, 40);
    return s;
}

- (NSArray<NSString *> *)searchKeywordsFrom:(NSString *)raw {
    NSString *trimmed = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) return @[];
    NSString *upper = trimmed.uppercaseString;
    NSRegularExpression *fc2 = [NSRegularExpression regularExpressionWithPattern:@"FC2(?:[- ]?PPV)?[- ]?(\\d{5,8})" options:NSRegularExpressionCaseInsensitive error:nil];
    NSTextCheckingResult *m = [fc2 firstMatchInString:upper options:0 range:NSMakeRange(0, upper.length)];
    if (m && m.numberOfRanges >= 2) {
        NSString *digits = [upper substringWithRange:[m rangeAtIndex:1]];
        return @[[NSString stringWithFormat:@"FC2-%@", digits], [NSString stringWithFormat:@"FC2%@", digits]];
    }
    NSMutableArray *variants = [NSMutableArray array];
    NSArray *parts = [trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@". "]];
    if (parts.count >= 2) {
        NSString *studio = parts.firstObject;
        NSRegularExpression *letters = [NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z]{3,}$" options:0 error:nil];
        if ([letters firstMatchInString:studio options:0 range:NSMakeRange(0, studio.length)]) {
            NSMutableArray *nums = [NSMutableArray array];
            for (NSString *p in parts) {
                BOOL allNum = p.length && [p rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound;
                if (allNum && (p.length == 2 || p.length == 4)) [nums addObject:p];
            }
            if (nums.count >= 3) {
                [variants addObject:[NSString stringWithFormat:@"%@.%@.%@.%@", studio, nums[0], nums[1], nums[2]]];
            }
            [variants addObject:studio];
        }
    }
    [variants addObject:trimmed];
    if (![upper isEqualToString:trimmed]) [variants addObject:upper];
    NSString *spaced = [trimmed stringByReplacingOccurrencesOfString:@"." withString:@" "];
    if (![spaced isEqualToString:trimmed]) [variants addObject:spaced];
    NSMutableArray *unique = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSString *v in variants) {
        if (v.length && ![seen containsObject:v]) { [seen addObject:v]; [unique addObject:v]; }
    }
    return unique;
}

- (NSString *)normalizedKey:(NSString *)raw {
    if (raw.length == 0) return @"";
    NSString *s = raw.lowercaseString;
    for (NSString *ch in @[@"-", @"_", @" ", @"."]) {
        s = [s stringByReplacingOccurrencesOfString:ch withString:@""];
    }
    s = [s stringByReplacingOccurrencesOfString:@"fc2ppv" withString:@"fc2"];
    return s;
}

- (NSInteger)episodeNumber:(NSString *)name {
    NSRegularExpression *r = [NSRegularExpression regularExpressionWithPattern:@"(?:^|[^a-z0-9])(?:e|ep|cd|part)[-_ ]?0*(\\d{1,3})(?:[^a-z0-9]|$)" options:NSRegularExpressionCaseInsensitive error:nil];
    NSTextCheckingResult *m = [r firstMatchInString:name options:0 range:NSMakeRange(0, name.length)];
    if (m && m.numberOfRanges >= 2) return [[name substringWithRange:[m rangeAtIndex:1]] integerValue];
    return 1;
}

+ (BOOL)name:(NSString *)filename matchesKeyword:(NSString *)keyword {
    AVDB115Client *c = [AVDB115Client shared];
    NSString *name = [c normalizedKey:filename];
    NSString *key = [c normalizedKey:keyword];
    if (key.length == 0 || name.length == 0) return NO;
    if ([name containsString:key]) return YES;
    if (![keyword containsString:@"."] && ![keyword containsString:@" "]) return NO;
    NSArray *tokens = [c matchTokens:keyword];
    NSString *studio = nil;
    for (NSString *t in tokens) {
        unichar ch = [t characterAtIndex:0];
        if ([[NSCharacterSet letterCharacterSet] characterIsMember:ch] && t.length >= 3) { studio = t; break; }
    }
    NSString *date = [c westernDateToken:tokens];
    if (studio && [name containsString:studio]) {
        if (date && [name containsString:date]) return YES;
        NSInteger hits = 0;
        for (NSString *t in tokens) {
            if ([t isEqualToString:studio] || t.length < 4) continue;
            if ([name containsString:t]) hits++;
        }
        return hits >= 2;
    }
    return NO;
}

- (NSArray<NSString *> *)matchTokens:(NSString *)raw {
    NSRegularExpression *ext = [NSRegularExpression regularExpressionWithPattern:@"\\.(mp4|mkv|avi|mov|wmv|flv|ts|m2ts|webm|m4v)$" options:NSRegularExpressionCaseInsensitive error:nil];
    NSString *s = [ext stringByReplacingMatchesInString:raw.lowercaseString options:0 range:NSMakeRange(0, raw.length) withTemplate:@""];
    NSMutableArray *tokens = [NSMutableArray array];
    NSMutableString *cur = [NSMutableString string];
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar ch = [s characterAtIndex:i];
        if ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:ch]) {
            [cur appendFormat:@"%C", ch];
        } else if (cur.length) {
            if (cur.length >= 2) [tokens addObject:[cur copy]];
            [cur setString:@""];
        }
    }
    if (cur.length >= 2) [tokens addObject:[cur copy]];
    return tokens;
}

- (NSString *)westernDateToken:(NSArray<NSString *> *)tokens {
    NSMutableArray *nums = [NSMutableArray array];
    for (NSString *t in tokens) {
        BOOL allNum = t.length && [t rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound;
        if (allNum && (t.length == 2 || t.length == 4)) {
            [nums addObject:(t.length == 4 ? [t substringFromIndex:2] : t)];
            if (nums.count >= 3) return [NSString stringWithFormat:@"%@%@%@", nums[0], nums[1], nums[2]];
        }
    }
    for (NSString *t in tokens) {
        BOOL allNum = t.length == 6 && [t rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound;
        if (allNum) return t;
    }
    return nil;
}

+ (NSArray<AVDB115PlayStream *> *)parseMasterPlaylist:(NSString *)text {
    NSMutableArray *streams = [NSMutableArray array];
    NSArray *lines = [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    for (NSUInteger i = 0; i < lines.count; i++) {
        NSString *line = [lines[i] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (![line containsString:@"#EXT-X-STREAM-INF"]) continue;
        NSString *name = [self capture:line pattern:@"NAME=\"([^\"]+)\""];
        NSInteger height = [[self capture:line pattern:@"RESOLUTION=\\d+x(\\d+)"] integerValue];
        NSInteger bw = [[self capture:line pattern:@"BANDWIDTH=(\\d+)"] integerValue];
        NSString *label = [self qualityLabel:name height:height bandwidth:bw];
        if (i + 1 < lines.count) {
            NSString *u = [lines[i + 1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if ([u hasPrefix:@"https: //"]) u = [u stringByReplacingOccurrencesOfString:@"https: //" withString:@"https://"];
            if (![u hasPrefix:@"http"]) {
                NSURL *abs = [NSURL URLWithString:u relativeToURL:[NSURL URLWithString:@"https://115.com/"]];
                if (abs) u = abs.absoluteString;
            }
            if ([u hasPrefix:@"http"]) {
                AVDB115PlayStream *s = [AVDB115PlayStream new];
                s.name = label;
                s.url = u;
                s.bandwidth = bw + [self qualityPriority:name height:height] * 10000000;
                s.headers = @{};
                s.resolvedAt = [NSDate date];
                [streams addObject:s];
            }
        }
    }
    [streams sortUsingComparator:^NSComparisonResult(AVDB115PlayStream *a, AVDB115PlayStream *b) {
        if (a.bandwidth == b.bandwidth) return NSOrderedSame;
        return a.bandwidth > b.bandwidth ? NSOrderedAscending : NSOrderedDescending;
    }];
    return streams;
}

+ (NSString *)capture:(NSString *)line pattern:(NSString *)pattern {
    NSRegularExpression *r = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSTextCheckingResult *m = [r firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
    if (!m || m.numberOfRanges < 2 || [m rangeAtIndex:1].location == NSNotFound) return nil;
    return [line substringWithRange:[m rangeAtIndex:1]];
}

+ (NSString *)qualityLabel:(NSString *)name height:(NSInteger)height bandwidth:(NSInteger)bandwidth {
    NSString *n = name.uppercaseString ?: @"";
    if ([n isEqualToString:@"BD"]) return @"4K";
    if ([n isEqualToString:@"UD"]) return @"1080P";
    if ([n isEqualToString:@"HD"]) return @"720P";
    if ([n isEqualToString:@"SD"]) return @"480P";
    if ([n isEqualToString:@"LD"]) return @"360P";
    if (height >= 2160) return @"4K";
    if (height >= 1080) return @"1080P";
    if (height >= 720) return @"720P";
    if (height >= 480) return @"480P";
    if (height >= 360) return @"360P";
    if (bandwidth > 0) return [NSString stringWithFormat:@"%ldk", (long)(bandwidth / 1000)];
    return @"HLS（分辨率未知）";
}

+ (NSInteger)qualityPriority:(NSString *)name height:(NSInteger)height {
    NSString *n = name.uppercaseString ?: @"";
    if ([n isEqualToString:@"BD"]) return 4;
    if ([n isEqualToString:@"UD"]) return 3;
    if ([n isEqualToString:@"HD"]) return 2;
    if ([n isEqualToString:@"SD"]) return 1;
    if ([n isEqualToString:@"LD"]) return 0;
    if (height >= 2160) return 4;
    if (height >= 1080) return 3;
    if (height >= 720) return 2;
    if (height >= 480) return 1;
    return 0;
}

@end
