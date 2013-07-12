//
//  HIBitcoinManager.m
//  BitcoinKit
//
//  Created by Bazyli Zygan on 11.07.2013.
//  Copyright (c) 2013 Hive Developers. All rights reserved.
//

#import "HIBitcoinManager.h"
#undef verify
#include "init.h"
#include "util.h"
#include "net.h"
#include "checkpoints.h"

static boost::thread_group _threadGroup;

@interface HIBitcoinManager ()


@property (nonatomic, readonly) NSTimer *checkTimer;
@property (nonatomic, readonly) BOOL    isStarting;

- (void)checkTick:(NSTimer *)timer;
@end

@implementation HIBitcoinManager

@synthesize dataURL = _dataURL;
@synthesize connections = _connections;
@synthesize isRunning = _isRunning;
@synthesize isStarting = _isStarting;
@synthesize checkTimer = _checkTimer;
@synthesize balance = _balance;
@synthesize syncProgress = _syncProgress;
@synthesize testingNetwork = _testingNetwork;
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
        NSURL *appSupportURL = [[[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] lastObject] URLByAppendingPathComponent:@"com.Hive.BitcoinKit"];

        _connections = 0;
        _balance = 0;
        _syncProgress = 0;
        _isRunning = NO;
         _dataURL = [appSupportURL copy];
    }
    
    return self;
}

- (void)start
{
    if (_isRunning || _isStarting)
        return;
    
    fHaveGUI = true;
    [[NSFileManager defaultManager] createDirectoryAtURL:_dataURL withIntermediateDirectories:YES attributes:0 error:NULL];
    NSString *pathparam = [NSString stringWithFormat:@"-datadir=%@", _dataURL.path];    
    if (!_testingNetwork)
    {
        const char *argv[2];
        argv[0] = NULL;
        argv[1] = pathparam.UTF8String;
        // Now mimic argument settings
        ParseParameters(2, argv);
    }
    else
    {
        const char *argv[3];
        argv[0] = NULL;
        argv[1] = pathparam.UTF8String;
        argv[2] = "-testnet";
        // Now mimic argument settings
        ParseParameters(3, argv);
    }
    _isStarting = YES;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        if(AppInit2(_threadGroup))
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                _isStarting = NO;
                [self willChangeValueForKey:@"isRunning"];
                _checkTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkTick:) userInfo:nil repeats:YES];
                _isRunning = YES;
                [self didChangeValueForKey:@"isRunning"];
            });
        }
    });
}

- (void)stop
{
    if (!_isRunning)
        return;
    
    [_checkTimer invalidate];
    _threadGroup.interrupt_all();
    _threadGroup.join_all();
    Shutdown();
    [self willChangeValueForKey:@"isRunning"];
    _isRunning = NO;
    [self didChangeValueForKey:@"isRunning"];
    if (_connections > 0)
    {
        [self willChangeValueForKey:@"connections"];
        _connections = 0;
        [self didChangeValueForKey:@"connections"];
    }
    if (_balance > 0)
    {
        [self willChangeValueForKey:@"balance"];
        _balance = 0;
        [self didChangeValueForKey:@"balance"];
    }
    if (_syncProgress > 0)
    {
        [self willChangeValueForKey:@"syncProgress"];
        _syncProgress = 0;
        [self didChangeValueForKey:@"syncProgress"];
    }
    
}

- (NSString *)walletAddress
{
    CWalletDB walletdb(pwalletMain->strWalletFile);
    
    CAccount account;
    walletdb.ReadAccount(string(""), account);
    
    bool bKeyUsed = false;
    
    // Check if the current key has been used
    if (account.vchPubKey.IsValid())
    {
        CScript scriptPubKey;
        scriptPubKey.SetDestination(account.vchPubKey.GetID());
        for (map<uint256, CWalletTx>::iterator it = pwalletMain->mapWallet.begin();
             it != pwalletMain->mapWallet.end() && account.vchPubKey.IsValid();
             ++it)
        {
            const CWalletTx& wtx = (*it).second;
            BOOST_FOREACH(const CTxOut& txout, wtx.vout)
            if (txout.scriptPubKey == scriptPubKey)
                bKeyUsed = true;
        }
    }
    
    // Generate a new key
    if (!account.vchPubKey.IsValid() || bKeyUsed)
    {
        if (!pwalletMain->GetKeyFromPool(account.vchPubKey, false))
            return nil;
        
        pwalletMain->SetAddressBookName(account.vchPubKey.GetID(), string(""));
        walletdb.WriteAccount(string(""), account);
    }
    
    return [NSString stringWithUTF8String:CBitcoinAddress(account.vchPubKey.GetID()).ToString().c_str()];
}

#pragma mark - Private methods

- (void)checkTick:(NSTimer *)timer
{
    if (_connections != (NSUInteger)vNodes.size())
    {
        [self willChangeValueForKey:@"connections"];
        _connections = (NSUInteger)vNodes.size();
        [self didChangeValueForKey:@"connections"];
    }
    
    if (_balance != pwalletMain->GetBalance())
    {
        [self willChangeValueForKey:@"balance"];
        _balance = pwalletMain->GetBalance();
        [self didChangeValueForKey:@"balance"];
    }
    
    NSUInteger sp = (Checkpoints::GuessVerificationProgress(pindexBest) * 10000.0 + 0.5);
    if (sp > 10000)
        sp = 10000;
    
    if (_syncProgress != sp)
    {
        [self willChangeValueForKey:@"syncProgress"];
        _syncProgress = sp;
        [self didChangeValueForKey:@"syncProgress"];
    }
}

- (void)dealloc
{
    [self stop];
    [super dealloc];
}



@end
