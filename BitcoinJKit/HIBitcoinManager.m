//
//  HIBitcoinManager.m
//  BitcoinKit
//
//  Created by Bazyli Zygan on 26.07.2013.
//  Copyright (c) 2013 Hive Developers. All rights reserved.
//

#import "HIBitcoinManager.h"

#import "HIBitcoinErrorCodes.h"
#import "HIBitcoinInternalErrorCodes.h"
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
    uint64_t _lastEstimatedBalance;
    NSTimer *_balanceChecker;
}

- (void)onBalanceChanged;
- (void)onSynchronizationChanged:(int)percent;
- (void)onTransactionChanged:(NSString *)txid;
- (void)onTransactionSucceeded:(NSString *)txid;
- (void)onTransactionFailed;
- (void)handleJavaException:(jthrowable)exception useExceptionHandler:(BOOL)useHandler error:(NSError **)returnedError;

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

jarray JCharArrayFromNSData(JNIEnv *env, NSData *data)
{
    jsize length = (jsize)(data.length / sizeof(jchar));
    jcharArray charArray = (*env)->NewCharArray(env, length);
    (*env)->SetCharArrayRegion(env, charArray, 0, length, data.bytes);
    return charArray;
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

JNIEXPORT void JNICALL onException(JNIEnv *env, jobject thisobject, jthrowable jexception)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [[HIBitcoinManager defaultManager] handleJavaException:jexception useExceptionHandler:YES error:NULL];
    [pool release];
}


static JNINativeMethod methods[] = {
    {"onBalanceChanged",        "()V",                                     (void *)&onBalanceChanged},
    {"onTransactionChanged",    "(Ljava/lang/String;)V",                   (void *)&onTransactionChanged},
    {"onTransactionSuccess",    "(Ljava/lang/String;)V",                   (void *)&onTransactionSucceeded},
    {"onTransactionFailed",     "()V",                                     (void *)&onTransactionFailed},
    {"onSynchronizationUpdate", "(I)V",                                    (void *)&onSynchronizationUpdate},
    {"onException",             "(Ljava/lang/Throwable;)V",                (void *)&onException}
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

    [self handleJavaExceptions:NULL];

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

    [self handleJavaExceptions:NULL];

    return result;
}

- (int)callIntegerMethodWithName:(char *)name signature:(char *)signature, ...
{
    jmethodID method = [self jMethodWithName:name signature:signature];

    va_list args;
    va_start(args, signature);
    jint result = (*_jniEnv)->CallIntMethodV(_jniEnv, _managerObject, method, args);
    va_end(args);

    [self handleJavaExceptions:NULL];

    return result;
}

- (long)callLongMethodWithName:(char *)name signature:(char *)signature, ...
{
    jmethodID method = [self jMethodWithName:name signature:signature];

    va_list args;
    va_start(args, signature);
    jlong result = (*_jniEnv)->CallLongMethodV(_jniEnv, _managerObject, method, args);
    va_end(args);

    [self handleJavaExceptions:NULL];

    return result;
}

- (jobject)callObjectMethodWithName:(char *)name error:(NSError **)error signature:(char *)signature, ...
{
    jmethodID method = [self jMethodWithName:name signature:signature];

    va_list args;
    va_start(args, signature);
    jobject result = (*_jniEnv)->CallObjectMethodV(_jniEnv, _managerObject, method, args);
    va_end(args);

    [self handleJavaExceptions:error];

    return result;
}

- (void)callVoidMethodWithName:(char *)name error:(NSError **)error signature:(char *)signature, ...
{
    jmethodID method = [self jMethodWithName:name signature:signature];

    va_list args;
    va_start(args, signature);
    (*_jniEnv)->CallVoidMethodV(_jniEnv, _managerObject, method, args);
    va_end(args);

    [self handleJavaExceptions:error];
}

- (void)handleJavaExceptions:(NSError **)error
{
    if ((*_jniEnv)->ExceptionCheck(_jniEnv))
    {
        // get the exception object
        jthrowable exception = (*_jniEnv)->ExceptionOccurred(_jniEnv);

        [self handleJavaException:exception useExceptionHandler:NO error:error];
    }
    else if (error)
    {
        *error = nil;
    }
}

- (void)handleJavaException:(jthrowable)exception useExceptionHandler:(BOOL)useHandler error:(NSError **)returnedError
{
    BOOL callerWantsToHandleErrors = returnedError != nil;

    if (callerWantsToHandleErrors)
    {
        *returnedError = nil;
    }
    else
    {
        // log exception to console
        (*_jniEnv)->ExceptionDescribe(_jniEnv);
    }

    // exception has to be cleared if it exists
    (*_jniEnv)->ExceptionClear(_jniEnv);

    // try to get exception details from Java
    // note: we need to do this on the main thread - if this is called from a background thread,
    // the toString() call returns nil and throws a new exception (java.lang.StackOverflowException)
    dispatch_block_t processException = ^{
        NSError *error = [NSError errorWithDomain:@"BitcoinKit"
                                             code:[self errorCodeForJavaException:exception]
                                         userInfo:[self createUserInfoForJavaException:exception]];

        if (callerWantsToHandleErrors && error.code != kHIBitcoinManagerUnexpectedError)
        {
            *returnedError = error;
        }
        else
        {
            NSException *exception = [NSException exceptionWithName:@"Java exception"
                                                             reason:error.userInfo[NSLocalizedFailureReasonErrorKey]
                                                           userInfo:nil];
            if (useHandler && self.exceptionHandler)
            {
                self.exceptionHandler(exception);
            }
            else
            {
                @throw exception;
            }
        }
    };

    if (dispatch_get_current_queue() != dispatch_get_main_queue())
    {
        // run the above code synchronously on the main thread,
        // otherwise Java GC can clean up the exception object and we get a memory access error
        dispatch_sync(dispatch_get_main_queue(), processException);
    }
    else
    {
        // if this is the main thread, we can't use dispatch_sync or the whole thing will lock up
        processException();
    }
}

- (NSInteger)errorCodeForJavaException:(jthrowable)exception
{
    NSString *exceptionClass = [self getJavaExceptionClassName:exception];
    if ([exceptionClass isEqual:@"com.google.bitcoin.store.UnreadableWalletException"])
    {
        return kHIBitcoinManagerUnreadableWallet;
    }
    else if ([exceptionClass isEqual:@"com.google.bitcoin.store.BlockStoreException"])
    {
        return kHIBitcoinManagerBlockStoreError;
    }
    else if ([exceptionClass isEqual:@"java.lang.IllegalArgumentException"])
    {
        return kHIIllegalArgumentException;
    }
    else if ([exceptionClass isEqual:@"com.hive.bitcoinkit.NoWalletException"])
    {
        return kHIBitcoinManagerNoWallet;
    }
    else if ([exceptionClass isEqual:@"com.hive.bitcoinkit.ExistingWalletException"])
    {
        return kHIBitcoinManagerWalletExists;
    }
    else
    {
        return kHIBitcoinManagerUnexpectedError;
    }
}

- (NSString *)getJavaExceptionClassName:(jthrowable)exception
{
    jclass exceptionClass = (*_jniEnv)->GetObjectClass(_jniEnv, exception);
    jmethodID getClassMethod = (*_jniEnv)->GetMethodID(_jniEnv, exceptionClass, "getClass", "()Ljava/lang/Class;");
    jobject classObject = (*_jniEnv)->CallObjectMethod(_jniEnv, exception, getClassMethod);
    jobject class = (*_jniEnv)->GetObjectClass(_jniEnv, classObject);
    jmethodID getNameMethod = (*_jniEnv)->GetMethodID(_jniEnv, class, "getName", "()Ljava/lang/String;");
    jstring name = (*_jniEnv)->CallObjectMethod(_jniEnv, exceptionClass, getNameMethod);
    return NSStringFromJString(_jniEnv, name);
}

- (NSDictionary *)createUserInfoForJavaException:(jthrowable)exception
{
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    userInfo[NSLocalizedFailureReasonErrorKey] = [self getJavaExceptionMessage:exception] ?: @"Java VM raised an exception";

    NSString *stackTrace = [self getJavaExceptionStackTrace:exception];
    if (stackTrace)
    {
        userInfo[@"stackTrace"] = stackTrace;
    }
    return userInfo;
}

- (NSString *)getJavaExceptionMessage:(jthrowable)exception
{
    jclass exceptionClass = (*_jniEnv)->GetObjectClass(_jniEnv, exception);

    if (exceptionClass)
    {
        jmethodID toStringMethod = (*_jniEnv)->GetMethodID(_jniEnv, exceptionClass, "toString", "()Ljava/lang/String;");

        if (toStringMethod)
        {
            jstring description = (*_jniEnv)->CallObjectMethod(_jniEnv, exception, toStringMethod);

            if ((*_jniEnv)->ExceptionCheck(_jniEnv))
            {
                (*_jniEnv)->ExceptionDescribe(_jniEnv);
                (*_jniEnv)->ExceptionClear(_jniEnv);
            }

            if (description)
            {
                return NSStringFromJString(_jniEnv, description);
            }
        }
    }

    return nil;
}

- (NSString *)getJavaExceptionStackTrace:(jthrowable)exception
{
    jmethodID stackTraceMethod = (*_jniEnv)->GetMethodID(_jniEnv, _managerClass, "getExceptionStackTrace",
                                                         "(Ljava/lang/Throwable;)Ljava/lang/String;");

    if (stackTraceMethod)
    {
        jstring stackTrace = (*_jniEnv)->CallObjectMethod(_jniEnv, _managerObject, stackTraceMethod, exception);

        if ((*_jniEnv)->ExceptionCheck(_jniEnv))
        {
            (*_jniEnv)->ExceptionDescribe(_jniEnv);
            (*_jniEnv)->ExceptionClear(_jniEnv);
        }

        if (stackTrace)
        {
            return NSStringFromJString(_jniEnv, stackTrace);
        }
    }

    return nil;
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
        _dateFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss z";
        _connections = 0;
        _sending = NO;
        _syncProgress = 0;
        _testingNetwork = NO;
        _enableMining = NO;
        _isRunning = NO;

        NSArray *applicationSupport = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                                             inDomains:NSUserDomainMask];
        self.dataURL = [[applicationSupport lastObject] URLByAppendingPathComponent:BitcoinJKitBundleIdentifier];

        int numOptions = 1;
#ifdef DEBUG
        const char *debugPort = getenv("HIVE_JAVA_DEBUG_PORT");
        BOOL doDebug = debugPort && debugPort[0];
        if (doDebug) {
            numOptions++;
        }
#endif
        JavaVMOption options[numOptions];
        NSBundle *myBundle = [NSBundle bundleWithIdentifier:BitcoinJKitBundleIdentifier];
        NSString *bootJarPath = [myBundle pathForResource:@"boot" ofType:@"jar"];
        options[0].optionString = (char *) [[NSString stringWithFormat:@"-Djava.class.path=%@", bootJarPath] UTF8String];

#ifdef DEBUG
        NSString *debugOptionString =
            [NSString stringWithFormat:@"-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=%s", debugPort];
        if (doDebug) {
            options[numOptions - 1].optionString = [debugOptionString UTF8String];
        }
#endif

        _vmArgs.version = JNI_VERSION_1_2;
        _vmArgs.nOptions = numOptions;
        _vmArgs.ignoreUnrecognized = JNI_TRUE;
        _vmArgs.options = options;

        JavaVM *vm;
        JNI_CreateJavaVM(&vm, (void *) &_jniEnv, &_vmArgs);

#ifdef DEBUG
        // Optionally wait here to give the Java debugger a chance to attach before anything happens.
        const char *debugDelay = getenv("HIVE_JAVA_DEBUG_DELAY");
        if (doDebug && debugDelay && debugDelay[0]) {
            long seconds = strtol(debugDelay, NULL, 10);
            NSLog(@"Waiting %ld seconds for Java debugger to connect...", seconds);
            sleep((int)seconds);
        }
#endif

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

    [_dateFormatter release];
    [sendCompletionBlock release];
    self.dataURL = nil;
    self.exceptionHandler = nil;

    [super dealloc];
}

- (BOOL)start:(NSError **)error
{
    [[NSFileManager defaultManager] createDirectoryAtURL:self.dataURL
                             withIntermediateDirectories:YES
                                              attributes:0
                                                   error:NULL];
    
    if (_testingNetwork)
    {
        [self callVoidMethodWithName:"setTestingNetwork" error:NULL signature:"(Z)V", true];
    }
    
    // Now set the folder
    [self callVoidMethodWithName:"setDataDirectory" error:NULL signature:"(Ljava/lang/String;)V",
     JStringFromNSString(_jniEnv, self.dataURL.path)];

    // We're ready! Let's start
    [self callVoidMethodWithName:"start" error:error signature:"()V"];
    if (!*error)
    {
        [self didStart];
    }
    return !*error;
}

- (void)createWallet:(NSError **)error
{
    *error = nil;
    [self callVoidMethodWithName:"createWallet" error:error signature:"()V"];
    if (!*error)
    {
        [self didStart];
    }
}

- (void)createWalletWithPassword:(NSData *)password
                           error:(NSError **)error
{
    jarray charArray = JCharArrayFromNSData(_jniEnv, password);

    *error = nil;
    [self callVoidMethodWithName:"createWallet"
                           error:error
                       signature:"([C)V", charArray];

    [self zeroCharArray:charArray size:password.length / sizeof(jchar)];

    if (!*error)
    {
        [self didStart];
    }
}

- (void)zeroCharArray:(jarray)charArray size:(jsize)size {
    const char *zero[size];
    memset(zero, 0, size);
    (*_jniEnv)->SetCharArrayRegion(_jniEnv, charArray, 0, size, zero);
}

- (void)didStart
{
    [self willChangeValueForKey:@"isRunning"];
    _isRunning = YES;
    [self didChangeValueForKey:@"isRunning"];

    [[NSNotificationCenter defaultCenter] postNotificationName:kHIBitcoinManagerStartedNotification object:self];

    [self willChangeValueForKey:@"walletAddress"];
    [self didChangeValueForKey:@"walletAddress"];
}

- (NSString *)walletAddress
{
    jstring address = [self callObjectMethodWithName:"getWalletAddress" error:NULL signature:"()Ljava/lang/String;"];
    return NSStringFromJString(_jniEnv, address);
}

- (void)stop
{
    [_balanceChecker invalidate];
    _balanceChecker = nil;

    if (_managerObject)
    {
        [self callVoidMethodWithName:"stop" error:NULL signature:"()V"];
    }

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
    NSError *error = nil;
    jstring transactionJString = [self callObjectMethodWithName:"getTransaction"
                                                          error:&error
                                                       signature:"(Ljava/lang/String;)Ljava/lang/String;",
                                  JStringFromNSString(_jniEnv, hash)];

    if (transactionJString && !error)
    {
        NSDictionary *transactionData = [self objectFromJSONString:NSStringFromJString(_jniEnv, transactionJString)];
        return [self modifiedTransactionForTransaction:transactionData];
    }
    
    return nil;
}

- (NSDictionary *)transactionAtIndex:(NSUInteger)index
{
    jstring transactionJString = [self callObjectMethodWithName:"getTransaction"
                                                          error:NULL
                                                      signature:"(I)Ljava/lang/String;", index];

    if (transactionJString)
    {
        NSDictionary *transactionData = [self objectFromJSONString:NSStringFromJString(_jniEnv, transactionJString)];
        return [self modifiedTransactionForTransaction:transactionData];
    }
    
    return nil;
}

- (NSArray *)allTransactions
{
    jstring transactionsJString = [self callObjectMethodWithName:"getAllTransactions"
                                                           error:NULL
                                                       signature:"()Ljava/lang/String;"];

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
    jstring transactionsJString = [self callObjectMethodWithName:"getTransaction"
                                                           error:NULL
                                                       signature:"(II)Ljava/lang/String;",
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

- (NSString *)walletDebuggingInfo
{
    jstring info = [self callObjectMethodWithName:"getWalletDebuggingInfo" error:NULL signature:"()Ljava/lang/String;"];
    return NSStringFromJString(_jniEnv, info);
}

- (BOOL)isAddressValid:(NSString *)address
{
    return [self callBooleanMethodWithName:"isAddressValid" signature:"(Ljava/lang/String;)Z",
            JStringFromNSString(_jniEnv, address)];
}

- (uint64_t)calculateTransactionFeeForSendingCoins:(uint64_t)coins
{
    jstring fee =
        [self callObjectMethodWithName:"feeForSendingCoins"
                                 error:NULL
                             signature:"(Ljava/lang/String;)Ljava/lang/String;",
                                       JStringFromNSString(_jniEnv, [NSString stringWithFormat:@"%lld", coins])];
    return [NSStringFromJString(_jniEnv, fee) longLongValue];
}

- (void)sendCoins:(uint64_t)coins
      toRecipient:(NSString *)recipient
          comment:(NSString *)comment
         password:(NSData *)password
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

    jstring jAmount = JStringFromNSString(_jniEnv, [NSString stringWithFormat:@"%lld", coins]);
    jstring jRecipient = JStringFromNSString(_jniEnv, recipient);
    if (password)
    {
        jarray jPassword = JCharArrayFromNSData(_jniEnv, password);
        [self callVoidMethodWithName:"sendCoins"
                               error:NULL
                           signature:"(Ljava/lang/String;Ljava/lang/String;[C)V", jAmount, jRecipient, jPassword];
    }
    else
    {
        [self callVoidMethodWithName:"sendCoins"
                               error:NULL
                           signature:"(Ljava/lang/String;Ljava/lang/String;)V", jAmount, jRecipient];
    }
}

- (BOOL)isWalletEncrypted {
    return [self callBooleanMethodWithName:"isWalletEncrypted" signature:"()Z"];
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
    return [self callLongMethodWithName:"getBalance" signature:"()J"];
}

- (uint64_t)estimatedBalance
{
    return [self callLongMethodWithName:"getEstimatedBalance" signature:"()J"];
}

- (void)checkBalance:(NSTimer *)timer
{
    if (self.balance != _lastBalance)
    {
        [self onBalanceChanged];
    }

    if (self.estimatedBalance != _lastEstimatedBalance)
    {
        [self onEstimatedBalanceChanged];
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
        _lastBalance = self.balance;
        [self didChangeValueForKey:@"balance"];
    });
}

- (void)onEstimatedBalanceChanged
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self willChangeValueForKey:@"estimatedBalance"];
        _lastEstimatedBalance = self.estimatedBalance;
        [self didChangeValueForKey:@"estimatedBalance"];
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
        [[NSNotificationCenter defaultCenter] postNotificationName:kHIBitcoinManagerTransactionChangedNotification
                                                            object:txid];
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
