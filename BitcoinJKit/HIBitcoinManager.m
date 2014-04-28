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
#import "HILogger.h"
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
    uint64_t _lastAvailableBalance;
    uint64_t _lastEstimatedBalance;
    NSTimer *_balanceChecker;
}

- (void)onAvailableBalanceChanged;
- (void)onEstimatedBalanceChanged;
- (void)onPeerCountChanged:(NSUInteger)peerCount;
- (void)onSynchronizationChanged:(float)percent;
- (void)onTransactionChanged:(NSString *)txid;
- (void)onTransactionSuccess:(NSString *)txid;
- (void)onTransactionFailed;
- (void)handleJavaException:(jthrowable)exception useExceptionHandler:(BOOL)useHandler error:(NSError **)returnedError;

@property (nonatomic, assign) BOOL isSyncing;

@end


#pragma mark - Helper functions for conversion

NSString * NSStringFromJString(JNIEnv *env, jstring javaString)
{
    if (javaString) {
        const char *chars = (*env)->GetStringUTFChars(env, javaString, NULL);
        NSString *objcString = [NSString stringWithUTF8String:chars];
        (*env)->ReleaseStringUTFChars(env, javaString, chars);

        return objcString;
    } else {
        return nil;
    }
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

char * CharsFromString(NSString *string) {
    return (char *) [string UTF8String];
}


#pragma mark - JNI callback functions

JNIEXPORT void JNICALL onBalanceChanged(JNIEnv *env, jobject thisobject)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [[HIBitcoinManager defaultManager] onAvailableBalanceChanged];
    [[HIBitcoinManager defaultManager] onEstimatedBalanceChanged];
    [pool release];
}

JNIEXPORT void JNICALL onPeerCountChanged(JNIEnv *env, jobject thisobject, jint peerCount)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [[HIBitcoinManager defaultManager] onPeerCountChanged:peerCount];
    [pool release];
}

JNIEXPORT void JNICALL onSynchronizationUpdate(JNIEnv *env, jobject thisobject, jfloat percent)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [[HIBitcoinManager defaultManager] onSynchronizationChanged:(float)percent];
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

JNIEXPORT void JNICALL onTransactionSuccess(JNIEnv *env, jobject thisobject, jstring txid)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    if (txid)
    {
        [[HIBitcoinManager defaultManager] onTransactionSuccess:NSStringFromJString(env, txid)];
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

JNIEXPORT void JNICALL receiveLogFromJVM(JNIEnv *env, jobject thisobject, jstring fileName, jstring methodName,
                                         int lineNumber, jint level, jstring msg)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    const char *fileNameString = (*env)->GetStringUTFChars(env, fileName, NULL);
    const char *methodNameString = (*env)->GetStringUTFChars(env, methodName, NULL);

    HILoggerLog(fileNameString, methodNameString, lineNumber, level, @"%@", NSStringFromJString(env, msg));

    (*env)->ReleaseStringUTFChars(env, fileName, fileNameString);
    (*env)->ReleaseStringUTFChars(env, methodName, methodNameString);
    [pool release];
}


static JNINativeMethod methods[] = {
    {"onBalanceChanged",        "()V",                                     (void *)&onBalanceChanged},
    {"onPeerCountChanged",      "(I)V",                                    (void *)&onPeerCountChanged},
    {"onTransactionChanged",    "(Ljava/lang/String;)V",                   (void *)&onTransactionChanged},
    {"onTransactionSuccess",    "(Ljava/lang/String;)V",                   (void *)&onTransactionSuccess},
    {"onTransactionFailed",     "()V",                                     (void *)&onTransactionFailed},
    {"onSynchronizationUpdate", "(F)V",                                    (void *)&onSynchronizationUpdate},
    {"onException",             "(Ljava/lang/Throwable;)V",                (void *)&onException}
};

NSString * const kHIBitcoinManagerTransactionChangedNotification = @"kJHIBitcoinManagerTransactionChangedNotification";
NSString * const kHIBitcoinManagerStartedNotification = @"kJHIBitcoinManagerStartedNotification";
NSString * const kHIBitcoinManagerStoppedNotification = @"kJHIBitcoinManagerStoppedNotification";

static NSString * const BitcoinJKitBundleIdentifier = @"com.hivewallet.BitcoinJKit";

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

    // exception has to be cleared if it exists
    (*_jniEnv)->ExceptionClear(_jniEnv);

    // try to get exception details from Java
    // note: we need to do this on the main thread - if this is called from a background thread,
    // the toString() call returns nil and throws a new exception (java.lang.StackOverflowException)
    dispatch_block_t processException = ^{
        NSError *error = [NSError errorWithDomain:@"BitcoinKit"
                                             code:[self errorCodeForJavaException:exception]
                                         userInfo:[self createUserInfoForJavaException:exception]];

        NSString *exceptionClass = [self getJavaExceptionClassName:exception];

        HILogWarn(@"Java exception caught (%@): %@\n%@",
                  exceptionClass,
                  error.userInfo[NSLocalizedFailureReasonErrorKey],
                  error.userInfo[@"stackTrace"] ?: @"");

        if (callerWantsToHandleErrors && error.code != kHIBitcoinManagerUnexpectedError)
        {
            *returnedError = error;
        }
        else
        {
            NSException *exception = [NSException exceptionWithName:@"Java exception"
                                                             reason:error.userInfo[NSLocalizedFailureReasonErrorKey]
                                                           userInfo:error.userInfo];
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
    NSString *exceptionMessage = [self getJavaExceptionMessage:exception];

    if ([exceptionClass isEqual:@"com.google.bitcoin.store.UnreadableWalletException"])
    {
        return kHIBitcoinManagerUnreadableWallet;
    }
    else if ([exceptionClass isEqual:@"com.google.bitcoin.store.BlockStoreException"])
    {
        if ([exceptionMessage rangeOfString:@"Store file is already locked"].location != NSNotFound)
        {
            return kHIBitcoinManagerBlockStoreLockError;
        }
        else
        {
            return kHIBitcoinManagerBlockStoreReadError;
        }
    }
    else if ([exceptionClass isEqual:@"com.google.bitcoin.core.InsufficientMoneyException"])
    {
        return kHIBitcoinManagerInsufficientMoneyError;
    }
    else if ([exceptionClass isEqual:@"java.lang.IllegalArgumentException"])
    {
        return kHIIllegalArgumentException;
    }
    else if ([exceptionClass isEqual:@"com.hivewallet.bitcoinkit.NoWalletException"])
    {
        return kHIBitcoinManagerNoWallet;
    }
    else if ([exceptionClass isEqual:@"com.hivewallet.bitcoinkit.ExistingWalletException"])
    {
        return kHIBitcoinManagerWalletExists;
    }
    else if ([exceptionClass isEqual:@"com.hivewallet.bitcoinkit.WrongPasswordException"])
    {
        return kHIBitcoinManagerWrongPassword;
    }
    else if ([exceptionClass isEqual:@"com.hivewallet.bitcoinkit.SendingDustException"])
    {
        return kHIBitcoinManagerSendingDustError;
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
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
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
    NSError *error = nil;
    NSData *data = [JSONString dataUsingEncoding:NSUTF8StringEncoding];
    id result = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];

    if (!error) {
        return result;
    } else {
        HILogWarn(@"Couldn't parse JSON string '%@' (%@)", JSONString, error);
        return nil;
    }
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

        NSString *extensionPaths = [self javaExtensionPaths];
        if (extensionPaths) {
            numOptions++;
        }

        JavaVMOption options[numOptions];

        options[0].optionString = CharsFromString([NSString stringWithFormat:@"-Djava.class.path=%@",
                                                     [self bootJarPath]]);

        if (extensionPaths) {
            options[1].optionString = CharsFromString([NSString stringWithFormat:@"-Djava.ext.dirs=%@",
                                                         extensionPaths]);
        }

#ifdef DEBUG
        if (doDebug) {
            NSString *debugOptionString = [NSString stringWithFormat:
                                           @"-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=%s",
                                           debugPort];

            options[numOptions - 1].optionString = CharsFromString(debugOptionString);
        }
#endif

        _vmArgs.version = JNI_VERSION_1_2;
        _vmArgs.nOptions = numOptions;
        _vmArgs.ignoreUnrecognized = JNI_TRUE;
        _vmArgs.options = options;

        JavaVM *vm;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated"
        JNI_CreateJavaVM(&vm, (void *) &_jniEnv, &_vmArgs);
#pragma clang diagnostic pop

#ifdef DEBUG
        // Optionally wait here to give the Java debugger a chance to attach before anything happens.
        const char *debugDelay = getenv("HIVE_JAVA_DEBUG_DELAY");
        if (doDebug && debugDelay && debugDelay[0]) {
            long seconds = strtol(debugDelay, NULL, 10);
            HILogDebug(@"Waiting %ld seconds for Java debugger to connect...", seconds);
            sleep((int)seconds);
        }
#endif

        // We need to create the manager object
        _managerClass = [self jClassForClass:@"com/hivewallet/bitcoinkit/BitcoinManager"];
        (*_jniEnv)->RegisterNatives(_jniEnv, _managerClass, methods, sizeof(methods)/sizeof(methods[0]));

        JNINativeMethod loggerMethod;
        loggerMethod.name = "receiveLogFromJVM";
        loggerMethod.signature = "(Ljava/lang/String;Ljava/lang/String;IILjava/lang/String;)V";
        loggerMethod.fnPtr = &receiveLogFromJVM;

        jclass loggerClass = [self jClassForClass:@"org/slf4j/impl/CocoaLogger"];
        (*_jniEnv)->RegisterNatives(_jniEnv, loggerClass, &loggerMethod, 1);

        jmethodID constructorMethod = [self jMethodWithName:"<init>" signature:"()V"];
        _managerObject = (*_jniEnv)->NewObject(_jniEnv, _managerClass, constructorMethod);

        _balanceChecker = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                           target:self
                                                         selector:@selector(verifyBalance:)
                                                         userInfo:nil
                                                          repeats:YES];

        // this is the same as default log level in default (JDK) logger, i.e. before adding CocoaLogger
        [self setLogLevel:HILoggerLevelInfo];
    }

    return self;
}

- (NSString *)bootJarPath {
    NSBundle *myBundle = [NSBundle bundleWithIdentifier:BitcoinJKitBundleIdentifier];
    return [myBundle pathForResource:@"boot" ofType:@"jar"];
}

- (NSString *)javaExtensionPaths {
    /*
        We want to remove /Library/Java/Extensions from java.ext.dirs, because otherwise some random libs from there
        will be loaded and might conflict with our classes.
        But we don't want to remove any system directories from there, because those might contain required JRE
        modules like crypto algorithm implementations, and e.g. password hashing with SHA256 might break...
        So to get a list of all system dirs from java.ext.dirs but without the user-accessible dirs, we need to run
        ExtensionPathsReader class first which will print the filtered paths.
    */

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/java";
    task.arguments = @[@"-cp", [self bootJarPath], @"ExtensionPathsReader"];
    task.standardOutput = [NSPipe pipe];
    task.standardError = [NSPipe pipe];

    [task launch];
    [task waitUntilExit];

    NSData *outputData = [[task.standardOutput fileHandleForReading] readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
    output = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (task.terminationStatus == 0) {
        return output;
    } else {
        NSData *errorData = [[task.standardError fileHandleForReading] readDataToEndOfFile];
        NSString *errorText = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];

        HILogWarn(@"Can't read Java extension directory list: output = '%@', error = '%@', return code = %d",
                  output, errorText, task.terminationStatus);

        return nil;
    }
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

    if (!error || !*error)
    {
        [self didStart];
        return YES;
    }

    return NO;
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

    [self zeroCharArray:charArray size:(jsize)(password.length / sizeof(jchar))];

    if (!*error)
    {
        [self didStart];
    }
}

- (void)changeWalletPassword:(NSData *)fromPassword
                  toPassword:(NSData *)toPassword
                       error:(NSError **)error
{
    jarray fromCharArray = fromPassword ? JCharArrayFromNSData(_jniEnv, fromPassword) : NULL;
    jarray toCharArray = JCharArrayFromNSData(_jniEnv, toPassword);

    [self callVoidMethodWithName:"changeWalletPassword"
                           error:error
                       signature:"([C[C)V", fromCharArray, toCharArray];

    if (fromCharArray)
    {
        [self zeroCharArray:fromCharArray size:(jsize)(fromPassword.length / sizeof(jchar))];
    }

    [self zeroCharArray:toCharArray size:(jsize)(toPassword.length / sizeof(jchar))];
}

- (NSString *)signMessage:(NSString *)message
             withPassword:(NSData *)password
                    error:(NSError **)error
{
    jarray passwordCharArray = password ? JCharArrayFromNSData(_jniEnv, password) : NULL;
    jstring messageJString = JStringFromNSString(_jniEnv, message);

    jstring signature = [self callObjectMethodWithName:"signMessage"
                                                 error:error
                                             signature:"(Ljava/lang/String;[C)Ljava/lang/String;",
                         messageJString, passwordCharArray];

    if (passwordCharArray)
    {
        [self zeroCharArray:passwordCharArray size:(jsize)(password.length / sizeof(jchar))];
    }

    if (signature) {
        return NSStringFromJString(_jniEnv, signature);
    } else {
        return NULL;
    }
}

- (BOOL)isPasswordCorrect:(NSData *)password
{
    jarray charArray = JCharArrayFromNSData(_jniEnv, password);

    BOOL result = [self callBooleanMethodWithName:"isPasswordCorrect" signature:"([C)Z", charArray];

    [self zeroCharArray:charArray size:(jsize)(password.length / sizeof(jchar))];

    return result;
}

- (void)zeroCharArray:(jarray)charArray size:(jsize)size {
    jchar zero[size];
    memset(zero, 0, size * sizeof(jchar));
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

- (NSString *)checkpointsFilePath
{
    jstring path = [self callObjectMethodWithName:"getCheckpointsFilePath" error:NULL signature:"()Ljava/lang/String;"];
    return NSStringFromJString(_jniEnv, path);
}

- (void)setCheckpointsFilePath:(NSString *)checkpointsFilePath
{
    [self callVoidMethodWithName:"setCheckpointsFilePath"
                           error:NULL
                       signature:"(Ljava/lang/String;)V",
     JStringFromNSString(_jniEnv, checkpointsFilePath)];
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

- (void)deleteBlockchainDataFile:(NSError **)error
{
    [self callVoidMethodWithName:"deleteBlockchainDataFile" error:error signature:"()V"];
}

- (void)resetBlockchain:(NSError **)error
{
    [self callVoidMethodWithName:"resetBlockchain" error:error signature:"()V"];
}

- (NSDictionary *)modifiedTransactionForTransaction:(NSDictionary *)transaction
{
    if (!transaction) {
        return nil;
    }

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
        if (!transactionJSONs) {
            return nil;
        }

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
        if (!transactionJSONs) {
            return nil;
        }

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

- (uint64_t)calculateTransactionFeeForSendingCoins:(uint64_t)coins toRecipient:(NSString *)recipient
{
    jstring fee =
        [self callObjectMethodWithName:"feeForSendingCoins"
                                 error:NULL
                             signature:"(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;",
                                       JStringFromNSString(_jniEnv, [NSString stringWithFormat:@"%lld", coins]),
                                       JStringFromNSString(_jniEnv, recipient)];

    return [NSStringFromJString(_jniEnv, fee) longLongValue];
}

- (void)sendCoins:(uint64_t)coins
      toRecipient:(NSString *)recipient
          comment:(NSString *)comment
         password:(NSData *)password
            error:(NSError **)error
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
    *error = nil;
    if (password)
    {
        jarray jPassword = JCharArrayFromNSData(_jniEnv, password);
        [self callVoidMethodWithName:"sendCoins"
                               error:error
                           signature:"(Ljava/lang/String;Ljava/lang/String;[C)V", jAmount, jRecipient, jPassword];
    }
    else
    {
        [self callVoidMethodWithName:"sendCoins"
                               error:error
                           signature:"(Ljava/lang/String;Ljava/lang/String;)V", jAmount, jRecipient];
    }

    if (*error)
    {
        [self endSending];
    }
}

- (BOOL)isWalletEncrypted {
    return [self callBooleanMethodWithName:"isWalletEncrypted" signature:"()Z"];
}

- (void)exportWalletTo:(NSURL *)exportURL error:(NSError **)error
{
    jstring path = JStringFromNSString(_jniEnv, exportURL.path);
    [self callVoidMethodWithName:"exportWallet" error:error signature:"(Ljava/lang/String;)V", path];
}

- (uint64_t)availableBalance
{
    return [self callLongMethodWithName:"getAvailableBalance" signature:"()J"];
}

- (uint64_t)estimatedBalance
{
    return [self callLongMethodWithName:"getEstimatedBalance" signature:"()J"];
}

- (void)verifyBalance:(NSTimer *)timer
{
    // This shouldn't be necessary, but let's check if we missed anything.
    if (self.availableBalance != _lastAvailableBalance)
    {
        HILogError(@"BitcoinKit missed a change notification. This is a bug.");
        [self onAvailableBalanceChanged];
    }

    if (self.estimatedBalance != _lastEstimatedBalance)
    {
        HILogError(@"BitcoinKit missed a change notification. This is a bug.");
        [self onEstimatedBalanceChanged];
    }
}

- (NSDate *)lastWalletChangeDate
{
    long timestamp = [self callLongMethodWithName:"getLastWalletChangeTimestamp" signature:"()J"];
    return (timestamp > 0) ? [NSDate dateWithTimeIntervalSince1970:(timestamp / 1000.0)] : nil;
}

- (NSUInteger)transactionCount
{
    return [self callIntegerMethodWithName:"getTransactionCount" signature:"()I"];
}

- (void)setLogLevel:(HILoggerLevel)level
{
    jclass loggerClass = [self jClassForClass:@"org/slf4j/impl/CocoaLogger"];
    jmethodID method = (*_jniEnv)->GetStaticMethodID(_jniEnv, loggerClass, "setGlobalLevel", "(I)V");

    if (!method)
    {
        @throw [NSException exceptionWithName:@"Java exception"
                                       reason:@"Method not found: setLevel"
                                     userInfo:nil];
    }

    (*_jniEnv)->CallStaticVoidMethod(_jniEnv, loggerClass, method, level);

    [self handleJavaExceptions:NULL];
}

- (void)setIsSyncing:(BOOL)isSyncing
{
    if (_isSyncing != isSyncing)
    {
        [self willChangeValueForKey:@"isSyncing"];
        _isSyncing = isSyncing;
        [self didChangeValueForKey:@"isSyncing"];
    }
}

- (BOOL)isConnected
{
    return (_peerCount > 0);
}


#pragma mark - Callbacks

- (void)onAvailableBalanceChanged
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self willChangeValueForKey:@"availableBalance"];
        _lastAvailableBalance = self.availableBalance;
        [self didChangeValueForKey:@"availableBalance"];
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

- (void)onPeerCountChanged:(NSUInteger)peerCount {
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL statusChange = (_peerCount > 0 && peerCount == 0) || (_peerCount == 0 && peerCount > 0);

        [self willChangeValueForKey:@"peerCount"];
        if (statusChange)
        {
            [self willChangeValueForKey:@"isConnected"];
        }

        _peerCount = peerCount;

        [self didChangeValueForKey:@"peerCount"];
        if (statusChange)
        {
            [self didChangeValueForKey:@"isConnected"];
        }
    });
}

- (void)onSynchronizationChanged:(float)percent
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self willChangeValueForKey:@"syncProgress"];
        _syncProgress = percent;
        [self didChangeValueForKey:@"syncProgress"];

        self.isSyncing = (percent < 100.0);
    });
}

- (void)onTransactionChanged:(NSString *)txid
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kHIBitcoinManagerTransactionChangedNotification
                                                            object:txid];
    });
}

- (void)onTransactionSuccess:(NSString *)txid
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sendCompletionBlock)
        {
            sendCompletionBlock(txid);
        }

        [self endSending];
    });
}

- (void)onTransactionFailed
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sendCompletionBlock)
        {
            sendCompletionBlock(nil);
        }

        [self endSending];
    });
}

- (void)endSending {
    _sending = NO;
    [sendCompletionBlock release];
    sendCompletionBlock = nil;
}

@end
