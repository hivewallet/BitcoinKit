//
//  HIJavaBridge.m
//  BitcoinKit
//
//  Created by Bazyli Zygan on 26.07.2013.
//  Copyright (c) 2013 Hive Developers. All rights reserved.
//

#import "HIJavaBridge.h"
#import "jni.h"

#if (defined __MINGW32__) || (defined _MSC_VER)
#  define EXPORT __declspec(dllexport)
#else
#  define EXPORT __attribute__ ((visibility("default"))) \
__attribute__ ((used))
#endif

#if (! defined __x86_64__) && ((defined __MINGW32__) || (defined _MSC_VER))
#  define SYMBOL(x) binary_boot_jar_##x
#else
#  define SYMBOL(x) _binary_boot_jar_##x
#endif

extern const uint8_t SYMBOL(start)[];
extern const uint8_t SYMBOL(end)[];

EXPORT const uint8_t*
bootJar(unsigned* size)
{
    *size = (unsigned int)(SYMBOL(end) - SYMBOL(start));
    return SYMBOL(start);
}
@interface HIJavaBridge ()
{
    JavaVM *_vm;
    JNIEnv *_jniEnv;
    JavaVMInitArgs _vmArgs;
}

@end

@implementation HIJavaBridge

+ (HIJavaBridge *)sharedBridge
{
    static HIJavaBridge *_sharedBridge = nil;
    static dispatch_once_t oncePredicate;
    if (!_sharedBridge)
        dispatch_once(&oncePredicate, ^{
            _sharedBridge = [[self alloc] init];
        });
    
    return _sharedBridge;
}

- (id)init
{
    self = [super init];
    if (self)
    {
        _vmArgs.version = JNI_VERSION_1_2;
        _vmArgs.nOptions = 1;
        _vmArgs.ignoreUnrecognized = JNI_TRUE;
        
        JavaVMOption options[_vmArgs.nOptions];
        _vmArgs.options = options;
        
        options[0].optionString = (char*) "-Xbootclasspath:[bootJar]";
        
        JavaVM* vm;
        void *env;
        JNI_CreateJavaVM(&vm, &env, &_vmArgs);
        _jniEnv = (JNIEnv *)(env);
    }
    
    return self;
}

- (JNIEnv *)jniEnvironment
{
    return _jniEnv;
}

- (jclass)jClassForClass:(NSString *)class
{
    jclass cls = (*_jniEnv)->FindClass(_jniEnv, [class UTF8String]);
    
    if ((*_jniEnv)->ExceptionCheck(_jniEnv))
        @throw [NSException exceptionWithName:@"Java exception" reason:@"Java VM raised an exception" userInfo:@{@"class": class}];
    
    return cls;
}

- (jobject)createObjectOfClass:(NSString *)class params:(NSArray *)params
{
    jclass cls = [self jClassForClass:class];
    
    
}

//- (id)callMethod:(NSString *)methodName target:(jobject)object params:(NSArray *)params
//{
//    (*_jniEnv)->CallObjectMethod
//}

- (void)dealloc
{
    (*_vm)->DestroyJavaVM(_vm);
    [super dealloc];
}
@end
