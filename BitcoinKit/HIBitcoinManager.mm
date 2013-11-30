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

static std::string HIEncodeDumpString(const std::string &str) {
    std::stringstream ret;
    BOOST_FOREACH(unsigned char c, str) {
        if (c <= 32 || c >= 128 || c == '%') {
            ret << '%' << HexStr(&c, &c + 1);
        } else {
            ret << c;
        }
    }
    return ret.str();
}

static std::string HIDecodeDumpString(const std::string &str) {
    std::stringstream ret;
    for (unsigned int pos = 0; pos < str.length(); pos++) {
        unsigned char c = str[pos];
        if (c == '%' && pos+2 < str.length()) {
            c = (((str[pos+1]>>6)*9+((str[pos+1]-'0')&15)) << 4) |
            ((str[pos+2]>>6)*9+((str[pos+2]-'0')&15));
            pos += 2;
        }
        ret << c;
    }
    return ret.str();
}

NSString * const kHIBitcoinManagerTransactionChangedNotification = @"kHIBitcoinManagerTransactionChangedNotification";
NSString * const kHIBitcoinManagerStartedNotification = @"kHIBitcoinManagerStartedNotification";
NSString * const kHIBitcoinManagerStoppedNotification = @"kHIBitcoinManagerStoppedNotification";

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
@synthesize walletAddress = _walletAddress;
@synthesize proxyAddress = _proxyAddress;
@synthesize disableListening = _disableListening;

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

- (BOOL)start:(NSError **)error
{
    if (_isRunning || _isStarting)
        return YES;
    
    fHaveGUI = true;
    [[NSFileManager defaultManager] createDirectoryAtURL:_dataURL withIntermediateDirectories:YES attributes:0 error:NULL];
    NSString *pathparam = [NSString stringWithFormat:@"-datadir=%@", _dataURL.path];
    const char *argv[6];
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
    
    if (_disableListening)
    {
        argv[argc++] = "-nolisten";
    }
    
    if (_proxyAddress)
    {
        argv[argc++] = [[NSString stringWithFormat:@"-proxy=%@", _proxyAddress] UTF8String];
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
                [[NSNotificationCenter defaultCenter] postNotificationName:kHIBitcoinManagerStartedNotification object:self];                
            });
        }
    });

    return YES;
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
    [[NSNotificationCenter defaultCenter] postNotificationName:kHIBitcoinManagerStoppedNotification object:self];
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

#pragma mark - Wallet methods

- (BOOL)isWalletEncrypted
{
    return pwalletMain->IsCrypted();
}

- (BOOL)isWalletLocked
{
    return pwalletMain->IsLocked();
}

- (BOOL)encryptWalletWith:(NSString *)passwd
{
    if (self.isWalletEncrypted)
        return NO;

    SecureString strWalletPass;
    strWalletPass.reserve(100);
    strWalletPass = passwd.UTF8String;
    
    if (strWalletPass.length() < 1)
        return NO;
    
    if (!pwalletMain->EncryptWallet(strWalletPass))
        return NO;
    
    return YES;
}

- (BOOL)changeWalletEncryptionKeyFrom:(NSString *)oldpasswd to:(NSString *)newpasswd
{
    if (!self.isWalletEncrypted)
        return NO;
    
    // TODO: get rid of these .c_str() calls by implementing SecureString::operator=(std::string)
    // Alternately, find a way to make params[0] mlock()'d to begin with.
    SecureString strOldWalletPass;
    strOldWalletPass.reserve(100);
    strOldWalletPass = oldpasswd.UTF8String;
    
    SecureString strNewWalletPass;
    strNewWalletPass.reserve(100);
    strNewWalletPass = newpasswd.UTF8String;
    
    if (strOldWalletPass.length() < 1 || strNewWalletPass.length() < 1)
        return NO;
    
    return pwalletMain->ChangeWalletPassphrase(strOldWalletPass, strNewWalletPass);
}

- (BOOL)unlockWalletWith:(NSString *)passwd
{
    if (!self.isWalletEncrypted)
        return YES;
    
    SecureString strWalletPass;
    strWalletPass.reserve(100);
    strWalletPass = passwd.UTF8String;

    if (strWalletPass.length() < 1 || !pwalletMain->Unlock(strWalletPass))
        return NO;
    
    return YES;
}

- (void)lockWallet
{
    if (!self.isWalletEncrypted)
        return;
    
    pwalletMain->Lock();
}

- (BOOL)exportWalletTo:(NSURL *)exportURL
{
    if (self.isWalletLocked || ![exportURL isFileURL])
        return NO;
    

    NSMutableData *dumpData = [[NSMutableData alloc] init];
    NSDateFormatter *dF = [[NSDateFormatter alloc] init];
    dF.dateFormat = @"YYYY'-'mm'-'dd'T'HH':'MM':'SSZ";
    
    std::map<CKeyID, int64> mapKeyBirth;
    std::set<CKeyID> setKeyPool;
    pwalletMain->GetKeyBirthTimes(mapKeyBirth);
    pwalletMain->GetAllReserveKeys(setKeyPool);
    
    // sort time/key pairs
    std::vector<std::pair<int64, CKeyID> > vKeyBirth;
    for (std::map<CKeyID, int64>::const_iterator it = mapKeyBirth.begin(); it != mapKeyBirth.end(); it++) {
        vKeyBirth.push_back(std::make_pair(it->second, it->first));
    }
    mapKeyBirth.clear();
    std::sort(vKeyBirth.begin(), vKeyBirth.end());
    
    // produce output
    [dumpData appendData:[[NSString stringWithFormat:@"# Wallet dump created by Bitcoin %s (%s)\n", CLIENT_BUILD.c_str(), CLIENT_DATE.c_str()] dataUsingEncoding:NSUTF8StringEncoding]];
    [dumpData appendData:[[NSString stringWithFormat:@"# * Created on %@\n", [dF stringFromDate:[NSDate dateWithTimeIntervalSinceNow:0]]] dataUsingEncoding:NSUTF8StringEncoding]];
    [dumpData appendData:[[NSString stringWithFormat:@"# * Best block at time of backup was %i (%s),\n", nBestHeight, hashBestChain.ToString().c_str()] dataUsingEncoding:NSUTF8StringEncoding]];
    [dumpData appendData:[[NSString stringWithFormat:@"#   mined on %@\n\n", [dF stringFromDate:[NSDate dateWithTimeIntervalSince1970:pindexBest->nTime]]] dataUsingEncoding:NSUTF8StringEncoding]];

    for (std::vector<std::pair<int64, CKeyID> >::const_iterator it = vKeyBirth.begin(); it != vKeyBirth.end(); it++) {
        const CKeyID &keyid = it->second;
        NSString *dateString = [dF stringFromDate:[NSDate dateWithTimeIntervalSince1970:it->first]];
        std::string strAddr = CBitcoinAddress(keyid).ToString();
        CKey key;
        if (pwalletMain->GetKey(keyid, key)) {
            if (pwalletMain->mapAddressBook.count(keyid)) {
                [dumpData appendData:[[NSString stringWithFormat:@"%s %@ label=%s # addr=%s\n", CBitcoinSecret(key).ToString().c_str(), dateString, HIEncodeDumpString(pwalletMain->mapAddressBook[keyid]).c_str(), strAddr.c_str()] dataUsingEncoding:NSUTF8StringEncoding]];
            } else if (setKeyPool.count(keyid)) {
                [dumpData appendData:[[NSString stringWithFormat:@"%s %@ reserve=1 # addr=%s\n", CBitcoinSecret(key).ToString().c_str(), dateString, strAddr.c_str()] dataUsingEncoding:NSUTF8StringEncoding]];
            } else {
                [dumpData appendData:[[NSString stringWithFormat:@"%s %@ change=1 # addr=%s\n", CBitcoinSecret(key).ToString().c_str(), dateString, strAddr.c_str()] dataUsingEncoding:NSUTF8StringEncoding]];
            }
        }
    }
    [dumpData appendData:[@"\n# End of dump\n" dataUsingEncoding:NSUTF8StringEncoding]];
    BOOL writeStatus = [dumpData writeToURL:exportURL atomically:NO];
    [dumpData release];
    [dF release];
    return writeStatus;
}

- (BOOL)importWalletFrom:(NSURL *)importURL
{
    if (self.isWalletLocked || ![importURL isFileURL])
        return NO;
    
    NSData *walletData = [[NSData alloc] initWithContentsOfURL:importURL];
    if (!walletData || walletData.length < 20)
        return NO;
    
    int64 nTimeBegin = pindexBest->nTime;
    
    BOOL fGood = YES;
    NSString *walletString = [[NSString alloc] initWithData:walletData encoding:NSUTF8StringEncoding];
    NSArray *lines = [walletString componentsSeparatedByString:@"\n"];
    [walletString release];
    NSDateFormatter *dF = [[NSDateFormatter alloc] init];
    dF.dateFormat = @"YYYY'-'mm'-'dd'T'HH':'MM':'SSZ";
    
    int curLine = 0;
    while (curLine < lines.count)
    {
        NSString *line = [lines objectAtIndex:curLine++];
        
        if (line.length == 0 || [line characterAtIndex:0] == L'#')
            continue;
        
        NSArray *vstr = [line componentsSeparatedByString:@" "];
        if ([vstr count] < 2)
            continue;
        
        CBitcoinSecret vchSecret;
        if (!vchSecret.SetString(string([[vstr objectAtIndex:0] UTF8String])))
            continue;
        CKey key = vchSecret.GetKey();
        CPubKey pubkey = key.GetPubKey();
        CKeyID keyid = pubkey.GetID();
        if (pwalletMain->HaveKey(keyid)) {
//            printf("Skipping import of %s (key already present)\n", CBitcoinAddress(keyid).ToString().c_str());
            continue;
        }
        int64 nTime = [[dF dateFromString:[vstr objectAtIndex:1]] timeIntervalSince1970];
        std::string strLabel;
        bool fLabel = true;
        for (unsigned int nStr = 2; nStr < vstr.count; nStr++) {
            if ([[vstr objectAtIndex:nStr] characterAtIndex:0] == L'#')
                break;
            if ([(NSString *)[vstr objectAtIndex:nStr] compare:@"change=1"] == NSOrderedSame)
                fLabel = false;
            if ([(NSString *)[vstr objectAtIndex:nStr] compare:@"reserve=1"] == NSOrderedSame)
                fLabel = false;
            if ([[vstr objectAtIndex:nStr] hasPrefix:@"label="]) {
                strLabel = HIDecodeDumpString(string([[[vstr objectAtIndex:nStr] substringFromIndex:6] UTF8String]));
                fLabel = true;
            }
        }
//        NSLog(@"Importing %s...\n", CBitcoinAddress(keyid).ToString().c_str());
        if (!pwalletMain->AddKeyPubKey(key, pubkey)) {
            fGood = NO;
            continue;
        }
        pwalletMain->mapKeyMetadata[keyid].nCreateTime = nTime;
        if (fLabel)
            pwalletMain->SetAddressBookName(keyid,strLabel);
        nTimeBegin = std::min(nTimeBegin, nTime);
    }
    
    CBlockIndex *pindex = pindexBest;
    while (pindex && pindex->pprev && pindex->nTime > nTimeBegin - 7200)
        pindex = pindex->pprev;
    
//    NSLog(@"Rescanning last %i blocks\n", pindexBest->nHeight - pindex->nHeight + 1);
    pwalletMain->ScanForWalletTransactions(pindex);
    pwalletMain->ReacceptWalletTransactions();
    pwalletMain->MarkDirty();
    
    [dF release];
    
    return fGood;
}

#pragma mark - Transaction methods

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

- (void)sendCoins:(uint64_t)coins toRecipient:(NSString *)recipient comment:(NSString *)comment completion:(void(^)(NSString *hash))completion
{
    if (coins == 0 || coins > self.balance)
    {
        if (completion)
            completion(nil);
        return;
    }
    CBitcoinAddress address(recipient.UTF8String);
  
    if (!address.IsValid())
    {
        if (completion)
            completion(nil);
        return;
    }
    
    CWalletTx wtx;
    if (comment.length > 0)
        wtx.mapValue["comment"] = string(comment.UTF8String);
    
    if (pwalletMain->IsLocked())
    {
        if (completion)
            completion(nil);
        return;
    }

    
    string strError = pwalletMain->SendMoneyToDestination(address.Get(), coins, wtx);

    if (strError != "")
    {
        if (completion)
            completion(nil);
        return;
    }

  
    NSString *retHash = [NSString stringWithUTF8String:wtx.GetHash().GetHex().c_str()];
    [[NSNotificationCenter defaultCenter] postNotificationName:kHIBitcoinManagerTransactionChangedNotification object:retHash];

    if (completion)
        completion(retHash);

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
    [_walletAddress release];
    [_proxyAddress release];
    [self stop];
    [super dealloc];
}



@end
