#pragma once
#import <UIKit/UIKit.h>
#import "AVDB115Client.h"

NS_ASSUME_NONNULL_BEGIN

@interface AVDB115PlayerViewController : UIViewController
- (instancetype)initWithKeyword:(NSString *)keyword magnet:(nullable NSString *)magnet;
- (instancetype)initWithFile:(AVDB115FileItem *)file;
@end

NS_ASSUME_NONNULL_END
