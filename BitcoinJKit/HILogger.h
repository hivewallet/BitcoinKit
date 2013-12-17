//
//  HILogger.h
//  BitcoinKit
//
//  Created by Jakub Suder on 17.12.2013.
//  Copyright (c) 2013 Hive Developers. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(int, HILoggerLevel) {
    HILoggerLevelVerbose = 1,
    HILoggerLevelDebug = 2,
    HILoggerLevelInfo = 3,
    HILoggerLevelWarn = 4,
    HILoggerLevelError = 5,
};

#define HILogError(...)   [[HILogger sharedLogger] logWithLevel:HILoggerLevelError message:__VA_ARGS__]
#define HILogWarn(...)    [[HILogger sharedLogger] logWithLevel:HILoggerLevelWarn message:__VA_ARGS__]
#define HILogInfo(...)    [[HILogger sharedLogger] logWithLevel:HILoggerLevelInfo message:__VA_ARGS__]
#define HILogDebug(...)   [[HILogger sharedLogger] logWithLevel:HILoggerLevelDebug message:__VA_ARGS__]
#define HILogVerbose(...) [[HILogger sharedLogger] logWithLevel:HILoggerLevelVerbose message:__VA_ARGS__]

@interface HILogger : NSObject

@property (strong) void (^logHandler)(HILoggerLevel level, NSString *message);

+ (instancetype)sharedLogger;
- (void)logWithLevel:(HILoggerLevel)level message:(NSString *)message, ...;

@end
