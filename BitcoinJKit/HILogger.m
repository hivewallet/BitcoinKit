//
//  HILogger.m
//  BitcoinKit
//
//  Created by Jakub Suder on 17.12.2013.
//  Copyright (c) 2013 Hive Developers. All rights reserved.
//

#import "HILogger.h"

@implementation HILogger

+ (HILogger *)sharedLogger {
    static HILogger *sharedLogger = nil;
    static dispatch_once_t oncePredicate;

    if (!sharedLogger) {
        dispatch_once(&oncePredicate, ^{
            sharedLogger = [[self alloc] init];
            sharedLogger.logHandler = ^(HILoggerLevel level, NSString *message) {
                NSLog(@"%@", message);
            };
        });
    }

    return sharedLogger;
}

- (void)logWithLevel:(HILoggerLevel)level message:(NSString *)message, ... {
    va_list args;
    va_start(args, message);
    NSString *logText = [[NSString alloc] initWithFormat:message arguments:args];
    va_end(args);

    self.logHandler(level, logText);
}

@end
