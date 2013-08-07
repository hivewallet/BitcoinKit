//
//  HIBitcoinManager.m
//  BitcoinKit
//
//  Created by Bazyli Zygan on 26.07.2013.
//  Copyright (c) 2013 Hive Developers. All rights reserved.
//

#import "HIBitcoinManager.h"
//#import "HIJavaBridge.h"
#import <JavaVM/jni.h>
//#import "jni.h"

//#if (defined __MINGW32__) || (defined _MSC_VER)
//#  define EXPORT __declspec(dllexport)
//#else
//#  define EXPORT __attribute__ ((visibility("default"))) \
//__attribute__ ((used))
//#endif
//
//#if (! defined __x86_64__) && ((defined __MINGW32__) || (defined _MSC_VER))
//#  define SYMBOL(x) binary_boot_jar_##x
//#else
//#  define SYMBOL(x) _binary_boot_jar_##x
//#endif
//
//extern const uint8_t SYMBOL(start)[];
//extern const uint8_t SYMBOL(end)[];
//
//EXPORT const uint8_t*
//bootJar(unsigned* size)
//{
//    *size = (unsigned int)(SYMBOL(end) - SYMBOL(start));
//    return SYMBOL(start);
//}

@interface HIBitcoinManager ()
{
    JavaVM *_vm;
    JNIEnv *_jniEnv;
    JavaVMInitArgs _vmArgs;
    jobject _managerObject;
    NSDateFormatter *_dateFormatter;
    BOOL _sending;
    void(^sendCompletionBlock)(NSString *hash);
    uint64_t _lastBalance;
    NSTimer *_balanceChecker;
}

- (jclass)jClassForClass:(NSString *)class;
- (void)onBalanceChanged;
- (void)onSynchronizationChanged:(int)percent;
- (void)onTransactionChanged:(NSString *)txid;
- (void)onTransactionSucceeded:(NSString *)txid;
- (void)onTransactionFailed;
- (void)checkBalance:(NSTimer *)timer;
@end


JNIEXPORT void JNICALL onBalanceChanged
(JNIEnv *env, jobject thisobject)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [[HIBitcoinManager defaultManager] onBalanceChanged];
    [pool release];
}

JNIEXPORT void JNICALL onSynchronizationUpdate
(JNIEnv *env, jobject thisobject, jint percent)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [[HIBitcoinManager defaultManager] onSynchronizationChanged:(int)percent];
    [pool release];
}

JNIEXPORT void JNICALL onTransactionChanged
(JNIEnv *env, jobject thisobject, jstring txid)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    if (txid)
    {
        const char *txc = (*env)->GetStringUTFChars(env, txid, NULL);
        
        NSString *bStr = [NSString stringWithUTF8String:txc];
        (*env)->ReleaseStringUTFChars(env, txid, txc);
        [[HIBitcoinManager defaultManager] onTransactionChanged:bStr];

    }
    
    [pool release];
}

JNIEXPORT void JNICALL onTransactionSucceeded
(JNIEnv *env, jobject thisobject, jstring txid)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    if (txid)
    {
        const char *txc = (*env)->GetStringUTFChars(env, txid, NULL);
        
        NSString *bStr = [NSString stringWithUTF8String:txc];
        (*env)->ReleaseStringUTFChars(env, txid, txc);
        [[HIBitcoinManager defaultManager] onTransactionSucceeded:bStr];
        
    }
    
    [pool release];
}

JNIEXPORT void JNICALL onTransactionFailed
(JNIEnv *env, jobject thisobject)
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

- (jclass)jClassForClass:(NSString *)class
{
    jclass cls = (*_jniEnv)->FindClass(_jniEnv, [class UTF8String]);
    
    if ((*_jniEnv)->ExceptionCheck(_jniEnv))
    {
        (*_jniEnv)->ExceptionDescribe(_jniEnv);
        (*_jniEnv)->ExceptionClear(_jniEnv);
        
        @throw [NSException exceptionWithName:@"Java exception" reason:@"Java VM raised an exception" userInfo:@{@"class": class}];
    }
    return cls;
}

- (id)init
{
    self = [super init];
    if (self)
    {
        NSURL *appSupportURL = [[[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] lastObject] URLByAppendingPathComponent:@"com.Hive.BitcoinJKit"];
        
        _dateFormatter = [[NSDateFormatter alloc] init];
        _dateFormatter.locale = [[[NSLocale alloc] initWithLocaleIdentifier:@"en_GB"] autorelease];
        _dateFormatter.dateFormat = @"EEE MMM dd HH:mm:ss zzz yyyy";
        _connections = 0;
        _balance = 0;
        _sending = NO;
        _syncProgress = 0;
        _testingNetwork = NO;
        _enableMining = NO;
        _isRunning = NO;
        _dataURL = [appSupportURL copy];
        
        _vmArgs.version = JNI_VERSION_1_2;
        _vmArgs.nOptions = 1;
        _vmArgs.ignoreUnrecognized = JNI_TRUE;
        
        JavaVMOption options[_vmArgs.nOptions];
        _vmArgs.options = options;
        
//        options[0].optionString = (char*) "-Xbootclasspath:[bootJar]";
        NSBundle *myBundle = [NSBundle bundleWithIdentifier:@"com.hive.BitcoinJKit"];
        options[0].optionString = (char *)[[NSString stringWithFormat:@"-Djava.class.path=%@", [myBundle pathForResource:@"boot" ofType:@"jar"]] UTF8String];
        
        JavaVM* vm;
        void *env;
        JNI_CreateJavaVM(&vm, &env, &_vmArgs);
        _jniEnv = (JNIEnv *)(env);
        
        
        // We need to create the manager object
        jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
        (*_jniEnv)->RegisterNatives(_jniEnv, mgrClass, methods, sizeof(methods)/sizeof(methods[0]));
        
        jmethodID constructorM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "<init>", "()V");
        if (constructorM)
        {
            _managerObject = (*_jniEnv)->NewObject(_jniEnv, mgrClass, constructorM);
        }
        
        _balanceChecker = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkBalance:) userInfo:nil repeats:YES];
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
    [[NSFileManager defaultManager] createDirectoryAtURL:_dataURL withIntermediateDirectories:YES attributes:0 error:NULL];
    
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
    
    if (_testingNetwork)
    {
        // Find testing network method in the class
        jmethodID testingM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "setTestingNetwork", "(Z)V");
        
        if (testingM == NULL)
            return;
        
        (*_jniEnv)->CallVoidMethod(_jniEnv, _managerObject, testingM, true);
        if ((*_jniEnv)->ExceptionCheck(_jniEnv))
        {
            (*_jniEnv)->ExceptionDescribe(_jniEnv);
            (*_jniEnv)->ExceptionClear(_jniEnv);
        }
        
    }
    
    // Now set the folder
    jmethodID folderM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "setDataDirectory", "(Ljava/lang/String;)V");
    if (folderM == NULL)
        return;
    
    (*_jniEnv)->CallVoidMethod(_jniEnv, _managerObject, folderM, (*_jniEnv)->NewStringUTF(_jniEnv, _dataURL.path.UTF8String));
    if ((*_jniEnv)->ExceptionCheck(_jniEnv))
    {
        (*_jniEnv)->ExceptionDescribe(_jniEnv);
        (*_jniEnv)->ExceptionClear(_jniEnv);
    }

    
    // We're ready! Let's start
    jmethodID startM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "start", "()V");
    
    if (startM == NULL)
        return;
    
    (*_jniEnv)->CallVoidMethod(_jniEnv, _managerObject, startM);
    if ((*_jniEnv)->ExceptionCheck(_jniEnv))
    {
        (*_jniEnv)->ExceptionDescribe(_jniEnv);
        (*_jniEnv)->ExceptionClear(_jniEnv);
    }
    [self willChangeValueForKey:@"isRunning"];
    _isRunning = YES;
    [self didChangeValueForKey:@"isRunning"];
    [[NSNotificationCenter defaultCenter] postNotificationName:kHIBitcoinManagerStartedNotification object:self];
    [self willChangeValueForKey:@"walletAddress"];
    [self didChangeValueForKey:@"walletAddress"];
}

- (NSString *)walletAddress
{
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];    
    jmethodID walletM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "getWalletAddres", "()Ljava/lang/String;");
    
    if (walletM)
    {
        jstring wa = (*_jniEnv)->CallObjectMethod(_jniEnv, _managerObject, walletM);
        
        const char *waStr = (*_jniEnv)->GetStringUTFChars(_jniEnv, wa, NULL);
        
        NSString *str = [NSString stringWithUTF8String:waStr];
        (*_jniEnv)->ReleaseStringUTFChars(_jniEnv, wa, waStr);
        
        return str;
    }
    
    
    return nil;
}

- (void)stop
{
    [_balanceChecker invalidate];
    _balanceChecker = nil;
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];    
    // We're ready! Let's start
    jmethodID stopM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "stop", "()V");
    
    if (stopM == NULL)
        return;
    
    (*_jniEnv)->CallVoidMethod(_jniEnv, _managerObject, stopM);
    if ((*_jniEnv)->ExceptionCheck(_jniEnv))
    {
        (*_jniEnv)->ExceptionDescribe(_jniEnv);
        (*_jniEnv)->ExceptionClear(_jniEnv);
    }
    
    [self willChangeValueForKey:@"isRunning"];
    _isRunning = NO;
    [self didChangeValueForKey:@"isRunning"];
    [[NSNotificationCenter defaultCenter] postNotificationName:kHIBitcoinManagerStoppedNotification object:self];
}

- (NSDictionary *)modifiedTransactionForTransaction:(NSDictionary *)transaction
{
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithDictionary:transaction];
    d[@"time"] = [_dateFormatter dateFromString:transaction[@"time"]];

    return d;
}

- (NSDictionary *)transactionForHash:(NSString *)hash
{
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
    // We're ready! Let's start
    jmethodID tM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "getTransaction", "(Ljava/lang/String;)Ljava/lang/String;");
    
    if (tM == NULL)
        return nil;
    

    jstring transString = (*_jniEnv)->CallObjectMethod(_jniEnv, _managerObject, tM, (*_jniEnv)->NewStringUTF(_jniEnv, hash.UTF8String));
    
    if (transString)
    {
        const char *transChars = (*_jniEnv)->GetStringUTFChars(_jniEnv, transString, NULL);
        
        NSString *bStr = [NSString stringWithUTF8String:transChars];
        (*_jniEnv)->ReleaseStringUTFChars(_jniEnv, transString, transChars);
        
        return [self modifiedTransactionForTransaction:[NSJSONSerialization JSONObjectWithData:[bStr dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL]];
        
    }
    
    return nil;
}

- (NSDictionary *)transactionAtIndex:(NSUInteger)index
{
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
    // We're ready! Let's start
    jmethodID tM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "getTransaction", "(I)Ljava/lang/String;");
    
    if (tM == NULL)
        return nil;
    
    
    jstring transString = (*_jniEnv)->CallObjectMethod(_jniEnv, _managerObject, tM, index);
    
    if (transString)
    {
        const char *transChars = (*_jniEnv)->GetStringUTFChars(_jniEnv, transString, NULL);
        
        NSString *bStr = [NSString stringWithUTF8String:transChars];
        (*_jniEnv)->ReleaseStringUTFChars(_jniEnv, transString, transChars);
        
        return [self modifiedTransactionForTransaction:[NSJSONSerialization JSONObjectWithData:[bStr dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL]];
        
    }
    
    return nil;
}

- (NSArray *)allTransactions
{
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
    // We're ready! Let's start
    jmethodID tM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "getAllTransactions", "()Ljava/lang/String;");
    
    if (tM == NULL)
        return nil;
    
    jstring transString = (*_jniEnv)->CallObjectMethod(_jniEnv, _managerObject, tM);
    
    if (transString)
    {
        const char *transChars = (*_jniEnv)->GetStringUTFChars(_jniEnv, transString, NULL);
        
        NSString *bStr = [NSString stringWithUTF8String:transChars];
        (*_jniEnv)->ReleaseStringUTFChars(_jniEnv, transString, transChars);
        
        NSArray *ts = [NSJSONSerialization JSONObjectWithData:[bStr dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
        NSMutableArray *mts = [NSMutableArray array];
        
        for (NSDictionary *t in ts)
        {
            [mts addObject:[self modifiedTransactionForTransaction:t]];
        }
        
        return mts;
        
        
    }
    
    return nil;
}

- (NSArray *)transactionsWithRange:(NSRange)range
{
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
    // We're ready! Let's start
    jmethodID tM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "getTransaction", "(II)Ljava/lang/String;");
    
    if (tM == NULL)
        return nil;
    
    
    jstring transString = (*_jniEnv)->CallObjectMethod(_jniEnv, _managerObject, tM, range.location, range.length);
    
    if (transString)
    {
        const char *transChars = (*_jniEnv)->GetStringUTFChars(_jniEnv, transString, NULL);
        
        NSString *bStr = [NSString stringWithUTF8String:transChars];
        (*_jniEnv)->ReleaseStringUTFChars(_jniEnv, transString, transChars);
        
        NSArray *ts = [NSJSONSerialization JSONObjectWithData:[bStr dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
        NSMutableArray *mts = [NSMutableArray array];
        
        for (NSDictionary *t in ts)
        {
            [mts addObject:[self modifiedTransactionForTransaction:t]];
        }
        
        return mts;

        
        
    }
    
    return nil;
}

- (BOOL)isAddressValid:(NSString *)address
{
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
    // We're ready! Let's start
    jmethodID aV = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "isAddressValid", "(Ljava/lang/String;)Z");
    
    if (aV == NULL)
        return NO;
    
    jboolean valid = (*_jniEnv)->CallBooleanMethod(_jniEnv, _managerObject, aV, (*_jniEnv)->NewStringUTF(_jniEnv, address.UTF8String));
    return valid;
}

- (void)sendCoins:(uint64_t)coins toReceipent:(NSString *)receipent comment:(NSString *)comment completion:(void(^)(NSString *hash))completion
{
    if (_sending)
    {
        if (completion)
            completion(nil);
        return;
    }
    
    _sending = YES;
    [sendCompletionBlock release];
    sendCompletionBlock = [completion copy];
    
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
    // We're ready! Let's start
    jmethodID sendM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "sendCoins", "(Ljava/lang/String;Ljava/lang/String;)V");
    
    if (sendM == NULL)
    {
        if (sendCompletionBlock)
            sendCompletionBlock(nil);
        
        [sendCompletionBlock release];
        sendCompletionBlock = nil;        
    }
    
    (*_jniEnv)->CallVoidMethod(_jniEnv, _managerObject, sendM, (*_jniEnv)->NewStringUTF(_jniEnv, [[NSString stringWithFormat:@"%lld", coins] UTF8String]),
                                (*_jniEnv)->NewStringUTF(_jniEnv, receipent.UTF8String));
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
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
    // We're ready! Let's start
    jmethodID balanceM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "getBalanceString", "()Ljava/lang/String;");
    
    if (balanceM == NULL)
        return 0;
    
    jstring balanceString = (*_jniEnv)->CallObjectMethod(_jniEnv, _managerObject, balanceM);
    
    if (balanceString)
    {
        const char *balanceChars = (*_jniEnv)->GetStringUTFChars(_jniEnv, balanceString, NULL);
        
        NSString *bStr = [NSString stringWithUTF8String:balanceChars];
        (*_jniEnv)->ReleaseStringUTFChars(_jniEnv, balanceString, balanceChars);
        
        _lastBalance = [bStr longLongValue];
        return [bStr longLongValue];
    }
    
    return 0;
}

- (void)checkBalance:(NSTimer *)timer
{
    uint64_t lastBalance = _lastBalance;
    if (lastBalance != [self balance])
    {
        [self onBalanceChanged];
    }
}

- (NSUInteger)transactionCount
{
    jclass mgrClass = [self jClassForClass:@"com/hive/bitcoinkit/BitcoinManager"];
    // We're ready! Let's start
    jmethodID tCM = (*_jniEnv)->GetMethodID(_jniEnv, mgrClass, "getTransactionCount", "()I");
    
    if (tCM == NULL)
        return 0;
    
    jint c = (*_jniEnv)->CallIntMethod(_jniEnv, _managerObject, tCM);
    
    return (NSUInteger)c;
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
        [[NSNotificationCenter defaultCenter] postNotificationName:kHIBitcoinManagerTransactionChangedNotification object:txid];
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
