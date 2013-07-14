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

NSString * const kHIBitcoinManagerTransactionChangedNotification = @"kHIBitcoinManagerTransactionChangedNotification";

@interface HIBitcoinManager ()


@property (nonatomic, readonly) NSTimer *checkTimer;
@property (nonatomic, readonly) BOOL    isStarting;

- (void)checkTick:(NSTimer *)timer;
- (void)wallet:(CWallet *)wallet changedTransaction:(uint256)hash change:(ChangeType)status;
- (NSDictionary *)transactionFromWalletTx:(const CWalletTx)wtx;

@end

static void NotifyTransactionChanged(HIBitcoinManager *manager, CWallet *wallet, const uint256 &hash, ChangeType status)
{
    [manager wallet:wallet changedTransaction:hash change:status];
}


@implementation HIBitcoinManager

@synthesize dataURL = _dataURL;
@synthesize connections = _connections;
@synthesize isRunning = _isRunning;
@synthesize isStarting = _isStarting;
@synthesize checkTimer = _checkTimer;
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
        NSURL *appSupportURL = [[[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] lastObject] URLByAppendingPathComponent:@"com.Hive.BitcoinKit"];

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
    if (_isRunning || _isStarting)
        return;
    
    fHaveGUI = true;
    [[NSFileManager defaultManager] createDirectoryAtURL:_dataURL withIntermediateDirectories:YES attributes:0 error:NULL];
    NSString *pathparam = [NSString stringWithFormat:@"-datadir=%@", _dataURL.path];
    const char *argv[4];
    int argc = 2;
    
    argv[0] = NULL;
    argv[1] = pathparam.UTF8String;
    
    if (_testingNetwork)
    {
        argv[argc++] = "-testnet";
    }
    
    if (_enableMining)
    {
        argv[argc++] = "-gen";
    }
    // Now mimic argument settings
    ParseParameters(argc, argv);
    
    _isStarting = YES;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        if(AppInit2(_threadGroup))
        {
            pwalletMain->NotifyTransactionChanged.connect(boost::bind(NotifyTransactionChanged, self, _1, _2, _3));
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
    
    pwalletMain->NotifyTransactionChanged.disconnect(boost::bind(NotifyTransactionChanged, self, _1, _2, _3));
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

- (NSDictionary *)transactionFromWalletTx:(const CWalletTx)wtx
{
    int64 nCredit = wtx.GetCredit();
    int64 nDebit = wtx.GetDebit();
    int64 nNet = nCredit - nDebit;
    int64 nFee = (wtx.IsFromMe() ? GetValueOut(wtx) - nDebit : 0);
    
    NSMutableDictionary *transaction = [NSMutableDictionary dictionary];
    
    [transaction setObject:[NSNumber numberWithLongLong:(nNet-nFee)] forKey:@"amount"];
    if (wtx.IsFromMe())
        [transaction setObject:[NSNumber numberWithLongLong:nFee] forKey:@"fee"];
    
    [transaction setObject:[NSNumber numberWithInt:wtx.GetDepthInMainChain()] forKey:@"confirmations"];
    
    if (wtx.IsCoinBase())
        [transaction setObject:[NSNumber numberWithBool:YES] forKey:@"generated"];
    
    if (wtx.GetDepthInMainChain() > 0)
    {
        [transaction setObject:[NSString stringWithUTF8String:wtx.hashBlock.GetHex().c_str()] forKey:@"blockhash"];
        [transaction setObject:[NSNumber numberWithLongLong:wtx.nIndex] forKey:@"blockindex"];
        [transaction setObject:[NSDate dateWithTimeIntervalSince1970:(boost::int64_t)(mapBlockIndex[wtx.hashBlock]->nTime)] forKey:@"blocktime"];
    }
    [transaction setObject:[NSString stringWithUTF8String:wtx.GetHash().GetHex().c_str()] forKey:@"txid"];
    [transaction setObject:[NSDate dateWithTimeIntervalSince1970:(boost::int64_t)(wtx.GetTxTime())] forKey:@"time"];
    [transaction setObject:[NSDate dateWithTimeIntervalSince1970:(boost::int64_t)(wtx.nTimeReceived)] forKey:@"timereceived"];
    
    BOOST_FOREACH(const PAIRTYPE(string,string)& item, wtx.mapValue)
    [transaction setObject:[NSString stringWithUTF8String:item.second.c_str()] forKey:[NSString stringWithUTF8String:item.first.c_str()]];

    int64 nFee2;
    string strSentAccount;
    list<pair<CTxDestination, int64> > listReceived;
    list<pair<CTxDestination, int64> > listSent;
    
    wtx.GetAmounts(listReceived, listSent, nFee2, strSentAccount);
    
    NSMutableArray *details = [NSMutableArray array];
    // Sent
    if ((!listSent.empty() || nFee2 != 0))
    {
        
        BOOST_FOREACH(const PAIRTYPE(CTxDestination, int64)& s, listSent)
        {
            [details addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithUTF8String:CBitcoinAddress(s.first).ToString().c_str()],
                                @"address", @"send", @"category", nil]];
        }
    }
    
    // Received
    if (listReceived.size() > 0)
    {
        BOOST_FOREACH(const PAIRTYPE(CTxDestination, int64)& r, listReceived)
        {
            NSString *category = nil;
            if (wtx.IsCoinBase())
            {
                if (wtx.GetDepthInMainChain() < 1)
                    category = @"orphan";
                else if (wtx.GetBlocksToMaturity() > 0)
                    category = @"immature";
                else
                    category = @"generate";
            }
            else
                category = @"receive";
            
            [details addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithUTF8String:CBitcoinAddress(r.first).ToString().c_str()],
                                @"address", category, @"category", nil]];
        }
    }

    [transaction setObject:details forKey:@"details"];
    return transaction;
}

- (NSDictionary *)transactionForHash:(NSString *)hash
{
    uint256 hashvalue;
    hashvalue.SetHex(hash.UTF8String);
    
    if (!pwalletMain->mapWallet.count(hashvalue))
        return nil;
    
    const CWalletTx& wtx = pwalletMain->mapWallet[hashvalue];
    return [self transactionFromWalletTx:wtx];
}

- (NSUInteger)transactionCount
{
    return (NSUInteger)pwalletMain->mapWallet.size();
}

- (NSArray *)allTransactions
{
    return [self transactionsWithRange:NSMakeRange(0, self.transactionCount)];
}

- (NSDictionary *)transactionAtIndex:(NSUInteger)index
{
    NSArray *arr = [self transactionsWithRange:NSMakeRange(index, 1)];
    if (arr.count == 1)
        return [arr objectAtIndex:0];
    else
        return nil;
}

- (NSArray *)transactionsWithRange:(NSRange)range
{
    if (range.length == 0 || range.location + range.length > self.transactionCount)
        return nil;
    
    NSMutableArray *arr = [NSMutableArray array];
    int pos = 0;
    // Note: maintaining indices in the database of (account,time) --> txid and (account, time) --> acentry
    // would make this much faster for applications that do this a lot.
    for (map<uint256, CWalletTx>::iterator it = pwalletMain->mapWallet.begin(); it != pwalletMain->mapWallet.end(); ++it)
    {

        if (pos >= range.location)
        {
            CWalletTx wtx = ((*it).second);
            [arr addObject:[self transactionFromWalletTx:wtx]];
        }
        pos++;
        if (pos > range.location + range.length)
            break;
    }
    
    return arr;
}

- (BOOL)isAddressValid:(NSString *)address
{
    CBitcoinAddress addr(address.UTF8String);
    return addr.IsValid();
}

- (BOOL)sendCoins:(uint64_t)coins toReceipent:(NSString *)receipent comment:(NSString *)comment
{
    if (coins == 0 || coins > self.balance)
        return NO;
    
    CBitcoinAddress address(receipent.UTF8String);
  
    if (!address.IsValid())
        return NO;
        
    CWalletTx wtx;
    if (comment.length > 0)
        wtx.mapValue["comment"] = string(comment.UTF8String);
    
    if (pwalletMain->IsLocked())
        return NO;
    
    string strError = pwalletMain->SendMoneyToDestination(address.Get(), coins, wtx);

    if (strError != "")
        return NO;
  
    [[NSNotificationCenter defaultCenter] postNotificationName:kHIBitcoinManagerTransactionChangedNotification object:[NSString stringWithUTF8String:wtx.GetHash().GetHex().c_str()]];

    return YES;
}

#pragma mark - Private methods

- (void)wallet:(CWallet *)wallet changedTransaction:(uint256)hash change:(ChangeType)status
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kHIBitcoinManagerTransactionChangedNotification object:[NSString stringWithUTF8String:hash.GetHex().c_str()]];
    });
}

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
