//
//  HIBitcoinManager.m
//  BitcoinKit
//
//  Created by Bazyli Zygan on 26.07.2013.
//  Copyright (c) 2013 Hive Developers. All rights reserved.
//

#import "HIBitcoinManager.h"
#import <JavaVM/jni.h>

@interface HIBitcoinManager ()
{
    JNIEnv *_jniEnv;
    JavaVMInitArgs _vmArgs;
    jobject _managerObject;
    jclass _managerClass;
    NSDateFormatter *_dateFormatter;
    BOOL _sending;
    void(^sendCompletionBlock)(NSString *hash);
    uint64_t _lastBalance;
    NSTimer *_balanceChecker;
}

- (void)onBalanceChanged;
- (void)onSynchronizationChanged:(int)percent;
- (void)onTransactionChanged:(NSString *)txid;
- (void)onTransactionSucceeded:(NSString *)txid;
- (void)onTransactionFailed;

@end


#pragma mark - Helper functions for conversion

NSString * NSStringFromJString(JNIEnv *env, jstring javaString)
{
    const char *chars = (*env)->GetStringUTFChars(env, javaString, NULL);
    NSString *objcString = [NSString stringWithUTF8String:chars];
    (*env)->ReleaseStringUTFChars(env, javaString, chars);

    return objcString;
}

jstring JStringFromNSString(JNIEnv *env, NSString *string)
{
    return (*env)->NewStringUTF(env, [string UTF8String]);
}


#pragma mark - JNI callback functions

JNIEXPORT void JNICALL onBalanceChanged(JNIEnv *env, jobject thisobject)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [[HIBitcoinManager defaultManager] onBalanceChanged];
    [pool release];
}

JNIEXPORT void JNICALL onSynchronizationUpdate(JNIEnv *env, jobject thisobject, jint percent)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [[HIBitcoinManager defaultManager] onSynchronizationChanged:(int)percent];
    [pool release];
}

JNIEXPORT void JNICALL onTransactionChanged(JNIEnv *env, jobject thisobject, jstring txid)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    if (txid)
    {
        [[HIBitcoinManager defaultManager] onTransactionChanged:NSStringFromJString(env, txid)];
    }
    
    [pool release];
}

JNIEXPORT void JNICALL onTransactionSucceeded(JNIEnv *env, jobject thisobject, jstring txid)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    if (txid)
    {
        [[HIBitcoinManager defaultManager] onTransactionSucceeded:NSStringFromJString(env, txid)];
    }
    
    [pool release];
}

JNIEXPORT void JNICALL onTransactionFailed(JNIEnv *env, jobject thisobject)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [[HIBitcoinManager defaultManager] onTransactionFailed];
    [pool release];
}


static JNINativeMethod methods[] = {
    {"onBalanceChanged",        "()V",                                     (void *)&onBalanceChanged},
    {"onTransactionChanged",    "(Ljava/lang/String;)V",                   (void *)&onTransactionChanged},
    {"onTransactionSuccess",    "(Ljava/lang/String;)V",                   (void *)&onTransactionSucceeded},
    {"onTransactionFailed",     "()V",                                     (void *)&onTransactionFailed},
    {"onSynchronizationUpdate", "(I)V",                                    (void *)&onSynchronizationUpdate}
};


NSString * const kHIBitcoinManagerTransactionChangedNotification = @"kJHIBitcoinManagerTransactionChangedNotification";
NSString * const kHIBitcoinManagerStartedNotification = @"kJHIBitcoinManagerStartedNotification";
NSString * const kHIBitcoinManagerStoppedNotification = @"kJHIBitcoinManagerStoppedNotification";

static NSString * const BitcoinJKitBundleIdentifier = @"com.hive.BitcoinJKit";


@implementation HIBitcoinManager

+ (HIBitcoinManager *)defaultManager
{
    static HIBitcoinManager *defaultManager = nil;
    static dispatch_once_t oncePredicate;

    if (!defaultManager)
    {
        dispatch_once(&oncePredicate, ^{
            defaultManager = [[self alloc] init];
        });
    }

    return defaultManager;
}


#pragma mark - helper methods for JNI calls and conversion

- (jclass)jClassForClass:(NSString *)class
{
    jclass cls = (*_jniEnv)->FindClass(_jniEnv, [class UTF8String]);
    
    if ((*_jniEnv)->ExceptionCheck(_jniEnv))
    {
        (*_jniEnv)->ExceptionDescribe(_jniEnv);
        (*_jniEnv)->ExceptionClear(_jniEnv);
        
        @throw [NSException exceptionWithName:@"Java exception"
                                       reason:@"Java VM raised an exception"
                                     userInfo:@{@"class": class}];
    }

    return cls;
}

- (jmethodID)jMethodWithName:(char *)name signature:(char *)signature
{
    jmethodID method = (*_jniEnv)->GetMethodID(_jniEnv, _managerClass, name, signature);

    if (method == NULL)
    {
        @throw [NSException exceptionWithName:@"Java exception"
                                       reason:[NSString stringWithFormat:@"Method not found: %s (%s)", name, signature]
                                     userInfo:nil];
    }

    return method;
}

- (BOOL)callBooleanMethodWithName:(char *)name signature:(char *)signature, ...
{
    jmethodID method = [self jMethodWithName:name signature:signature];

    va_list args;
    va_start(args, signature);
    jboolean result = (*_jniEnv)->CallBooleanMethodV(_jniEnv, _managerObject, method, args);
    va_end(args);

    [self handleJavaExceptions];

    return result;
}

- (NSInteger)callIntegerMethodWithName:(char *)name signature:(char *)signature, ...
{
    jmethodID method = [self jMethodWithName:name signature:signature];

    va_list args;
    va_start(args, signature);
    jint result = (*_jniEnv)->CallIntMethodV(_jniEnv, _managerObject, method, args);
    va_end(args);

    [self handleJavaExceptions];

    return result;
}

- (jobject)callObjectMethodWithName:(char *)name signature:(char *)signature, ...
{
    jmethodID method = [self jMethodWithName:name signature:signature];

    va_list args;
    va_start(args, signature);
    jobject result = (*_jniEnv)->CallObjectMethodV(_jniEnv, _managerObject, method, args);
    va_end(args);

    [self handleJavaExceptions];

    return result;
}

- (void)callVoidMethodWithName:(char *)name signature:(char *)signature, ...
{
    jmethodID method = [self jMethodWithName:name signature:signature];

    va_list args;
    va_start(args, signature);
    (*_jniEnv)->CallVoidMethodV(_jniEnv, _managerObject, method, args);
    va_end(args);

    [self handleJavaExceptions];
}

- (void)handleJavaExceptions
{
    if ((*_jniEnv)->ExceptionCheck(_jniEnv))
    {
        (*_jniEnv)->ExceptionDescribe(_jniEnv);
        (*_jniEnv)->ExceptionClear(_jniEnv);
    }
}

- (id)objectFromJSONString:(NSString *)JSONString
{
    NSData *data = [JSONString dataUsingEncoding:NSUTF8StringEncoding];
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
}


#pragma mark - Initialization

- (id)init
{
    self = [super init];

    if (self)
    {
        _dateFormatter = [[NSDateFormatter alloc] init];
        _dateFormatter.locale = [[[NSLocale alloc] initWithLocaleIdentifier:@"en_GB"] autorelease];
        _dateFormatter.dateFormat = @"EEE MMM dd HH:mm:ss zzz yyyy";

        _connections = 0;
        _sending = NO;
        _syncProgress = 0;
        _testingNetwork = NO;
        _enableMining = NO;
        _isRunning = NO;

        NSArray *applicationSupport = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                                             inDomains:NSUserDomainMask];
        self.dataURL = [[applicationSupport lastObject] URLByAppendingPathComponent:BitcoinJKitBundleIdentifier];

        JavaVMOption options[_vmArgs.nOptions];
        NSBundle *myBundle = [NSBundle bundleWithIdentifier:BitcoinJKitBundleIdentifier];
        NSString *bootJarPath = [myBundle pathForResource:@"boot" ofType:@"jar"];
        options[0].optionString = (char *) [[NSString stringWithFormat:@"-Djava.class.path=%@", bootJarPath] UTF8String];

        _vmArgs.version = JNI_VERSION_1_2;
        _vmArgs.nOptions = 1;
        _vmArgs.ignoreUnrecognized = JNI_TRUE;
        _vmArgs.options = options;

        JavaVM *vm;
        JNI_CreateJavaVM(&vm, (void *) &_jniEnv, &_vmArgs);

        // We need to create the manager object
        _managerClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
        (*_jniEnv)->RegisterNatives(_jniEnv, _managerClass, methods, sizeof(methods)/sizeof(methods[0]));

        jmethodID constructorMethod = [self jMethodWithName:"<init>" signature:"()V"];
        _managerObject = (*_jniEnv)->NewObject(_jniEnv, _managerClass, constructorMethod);

        _balanceChecker = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                           target:self
                                                         selector:@selector(checkBalance:)
                                                         userInfo:nil
                                                          repeats:YES];
    }

    return self;
}

- (void)dealloc
{
    [self stop];
    [sendCompletionBlock release];
    [super dealloc];
}

- (void)start
{
    [[NSFileManager defaultManager] createDirectoryAtURL:self.dataURL
                             withIntermediateDirectories:YES
                                              attributes:0
                                                   error:NULL];
    
    if (_testingNetwork)
    {
        [self callVoidMethodWithName:"setTestingNetwork" signature:"(Z)V", true];
    }
    
    // Now set the folder
    [self callVoidMethodWithName:"setDataDirectory" signature:"(Ljava/lang/String;)V",
     JStringFromNSString(_jniEnv, self.dataURL.path)];

    // We're ready! Let's start
    [self callVoidMethodWithName:"start" signature:"()V"];

    [self willChangeValueForKey:@"isRunning"];
    _isRunning = YES;
    [self didChangeValueForKey:@"isRunning"];

    [[NSNotificationCenter defaultCenter] postNotificationName:kHIBitcoinManagerStartedNotification object:self];

    [self willChangeValueForKey:@"walletAddress"];
    [self didChangeValueForKey:@"walletAddress"];
}

- (NSString *)walletAddress
{
    jstring address = [self callObjectMethodWithName:"getWalletAddress" signature:"()Ljava/lang/String;"];
    return NSStringFromJString(_jniEnv, address);
}

- (void)stop
{
    [_balanceChecker invalidate];
    _balanceChecker = nil;

    [self callVoidMethodWithName:"stop" signature:"()V"];

    [self willChangeValueForKey:@"isRunning"];
    _isRunning = NO;
    [self didChangeValueForKey:@"isRunning"];

    [[NSNotificationCenter defaultCenter] postNotificationName:kHIBitcoinManagerStoppedNotification object:self];
}

- (NSDictionary *)modifiedTransactionForTransaction:(NSDictionary *)transaction
{
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithDictionary:transaction];
    NSDate *date = [_dateFormatter dateFromString:transaction[@"time"]];

    if (date)
    {
        d[@"time"] = date;
    }
    else
    {
        d[@"time"] = [NSDate date];
    }

    return d;
}

- (NSDictionary *)transactionForHash:(NSString *)hash
{
    jstring transactionJString = [self callObjectMethodWithName:"getTransaction"
                                                       signature:"(Ljava/lang/String;)Ljava/lang/String;",
                                  JStringFromNSString(_jniEnv, hash)];

    if (transactionJString)
    {
        NSDictionary *transactionData = [self objectFromJSONString:NSStringFromJString(_jniEnv, transactionJString)];
        return [self modifiedTransactionForTransaction:transactionData];
    }
    
    return nil;
}

- (NSDictionary *)transactionAtIndex:(NSUInteger)index
{
    jstring transactionJString = [self callObjectMethodWithName:"getTransaction" signature:"(I)Ljava/lang/String;",
                                  index];

    if (transactionJString)
    {
        NSDictionary *transactionData = [self objectFromJSONString:NSStringFromJString(_jniEnv, transactionJString)];
        return [self modifiedTransactionForTransaction:transactionData];
    }
    
    return nil;
}

- (NSArray *)allTransactions
{
    jstring transactionsJString = [self callObjectMethodWithName:"getAllTransactions" signature:"()Ljava/lang/String;"];

    if (transactionsJString)
    {
        NSArray *transactionJSONs = [self objectFromJSONString:NSStringFromJString(_jniEnv, transactionsJString)];
        NSMutableArray *transactions = [NSMutableArray arrayWithCapacity:transactionJSONs.count];

        for (NSDictionary *JSON in transactionJSONs)
        {
            [transactions addObject:[self modifiedTransactionForTransaction:JSON]];
        }

        return transactions;
    }

    return nil;
}

- (NSArray *)transactionsWithRange:(NSRange)range
{
    jstring transactionsJString = [self callObjectMethodWithName:"getTransaction" signature:"(II)Ljava/lang/String;",
                                   range.location, range.length];

    if (transactionsJString)
    {
        NSArray *transactionJSONs = [self objectFromJSONString:NSStringFromJString(_jniEnv, transactionsJString)];
        NSMutableArray *transactions = [NSMutableArray arrayWithCapacity:transactionJSONs.count];

        for (NSDictionary *JSON in transactionJSONs)
        {
            [transactions addObject:[self modifiedTransactionForTransaction:JSON]];
        }
        
        return transactions;
    }

    return nil;
}

- (BOOL)isAddressValid:(NSString *)address
{
    return [self callBooleanMethodWithName:"isAddressValid" signature:"(Ljava/lang/String;)Z",
            JStringFromNSString(_jniEnv, address)];
}

- (void)sendCoins:(uint64_t)coins
      toReceipent:(NSString *)receipent
          comment:(NSString *)comment
       completion:(void(^)(NSString *hash))completion
{
    if (_sending)
    {
        if (completion)
        {
            completion(nil);
        }

        return;
    }
    
    _sending = YES;

    [sendCompletionBlock release];
    sendCompletionBlock = [completion copy];
    
    [self callVoidMethodWithName:"sendCoins" signature:"(Ljava/lang/String;Ljava/lang/String;)V",
     JStringFromNSString(_jniEnv, [NSString stringWithFormat:@"%lld", coins]),
     JStringFromNSString(_jniEnv, receipent)];
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

- (uint64_t)balance
{
    jstring balanceJString = [self callObjectMethodWithName:"getBalanceString" signature:"()Ljava/lang/String;"];

    if (balanceJString)
    {
        NSString *balanceString = NSStringFromJString(_jniEnv, balanceJString);
        _lastBalance = [balanceString longLongValue];
        return [balanceString longLongValue];
    }
    
    return 0;
}

- (void)checkBalance:(NSTimer *)timer
{
    uint64_t lastBalance = _lastBalance;

    if (lastBalance != self.balance)
    {
        [self onBalanceChanged];
    }
}

- (NSUInteger)transactionCount
{
    return [self callIntegerMethodWithName:"getTransactionCount" signature:"()I"];
}


#pragma mark - Callbacks

- (void)onBalanceChanged
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self willChangeValueForKey:@"balance"];
        [self didChangeValueForKey:@"balance"];
    });
}

- (void)onSynchronizationChanged:(int)percent
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self willChangeValueForKey:@"syncProgress"];
        _syncProgress = (NSUInteger)percent;
        [self didChangeValueForKey:@"syncProgress"];
    });
}

- (void)onTransactionChanged:(NSString *)txid
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self willChangeValueForKey:@"balance"];
        [[NSNotificationCenter defaultCenter] postNotificationName:kHIBitcoinManagerTransactionChangedNotification
                                                            object:txid];
        [self didChangeValueForKey:@"balance"];
    });
}

- (void)onTransactionSucceeded:(NSString *)txid
{
    dispatch_async(dispatch_get_main_queue(), ^{
        _sending = NO;

        if (sendCompletionBlock)
        {
            sendCompletionBlock(txid);
        }

        [sendCompletionBlock release];
        sendCompletionBlock = nil;        
    });
}

- (void)onTransactionFailed
{
    dispatch_async(dispatch_get_main_queue(), ^{
        _sending = NO;

        if (sendCompletionBlock)
        {
            sendCompletionBlock(nil);
        }

        [sendCompletionBlock release];
        sendCompletionBlock = nil;
    });
}

@end
