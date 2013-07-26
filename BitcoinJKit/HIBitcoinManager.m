//
//  HIBitcoinManager.m
//  BitcoinKit
//
//  Created by Bazyli Zygan on 26.07.2013.
//  Copyright (c) 2013 Hive Developers. All rights reserved.
//

#import "HIBitcoinManager.h"
#import "HIJavaBridge.h"

NSString * const kHIBitcoinManagerTransactionChangedNotification = @"kJHIBitcoinManagerTransactionChangedNotification";
NSString * const kHIBitcoinManagerStartedNotification = @"kJHIBitcoinManagerStartedNotification";
NSString * const kHIBitcoinManagerStoppedNotification = @"kJHIBitcoinManagerStoppedNotification";


@interface HIBitcoinManager ()

@end

@implementation HIBitcoinManager

@synthesize dataURL = _dataURL;
@synthesize connections = _connections;
@synthesize isRunning = _isRunning;
@synthesize balance = _balance;
@synthesize syncProgress = _syncProgress;
@synthesize testingNetwork = _testingNetwork;
@synthesize enableMining = _enableMining;
@synthesize walletAddress;

+ (HIBitcoinManager *)defaultManager
{
    static HIBitcoinManager *_defaultManager = nil;
    static dispatch_once_t oncePredicate;
    if (!_defaultManager)
        dispatch_once(&oncePredicate, ^{
            _defaultManager = [[self alloc] init];
        });
    
    return _defaultManager;
}

- (id)init
{
    self = [super init];
    if (self)
    {
        NSURL *appSupportURL = [[[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] lastObject] URLByAppendingPathComponent:@"com.Hive.BitcoinJKit"];
        
        _connections = 0;
        _balance = 0;
        _syncProgress = 0;
        _testingNetwork = NO;
        _enableMining = NO;
        _isRunning = NO;
        _dataURL = [appSupportURL copy];
    }
    
    return self;
}

- (void)start
{
    
}

- (void)stop
{
    
}

- (NSDictionary *)transactionForHash:(NSString *)hash
{
    return nil;
}

- (NSDictionary *)transactionAtIndex:(NSUInteger)index
{
    return nil;
}

- (NSArray *)allTransactions
{
    return nil;
}

- (NSArray *)transactionsWithRange:(NSRange)range
{
    return nil;
}

- (BOOL)isAddressValid:(NSString *)address
{
    return NO;
}

- (NSString *)sendCoins:(uint64_t)coins toReceipent:(NSString *)receipent comment:(NSString *)comment
{
    return nil;
}

- (BOOL)encryptWalletWith:(NSString *)passwd
{
    return NO;
}

- (BOOL)changeWalletEncryptionKeyFrom:(NSString *)oldpasswd to:(NSString *)newpasswd
{
    return NO;
}

- (BOOL)unlockWalletWith:(NSString *)passwd
{
    return NO;
}

- (void)lockWallet
{
    
}

- (BOOL)exportWalletTo:(NSURL *)exportURL
{
    return NO;
}

- (BOOL)importWalletFrom:(NSURL *)importURL
{
    return NO;
}
@end
