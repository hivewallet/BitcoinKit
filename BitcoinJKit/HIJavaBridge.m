//
//  HIJavaBridge.m
//  BitcoinKit
//
//  Created by Bazyli Zygan on 26.07.2013.
//  Copyright (c) 2013 Hive Developers. All rights reserved.
//

#import "HIJavaBridge.h"
#import "jni.h"

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
        JNI_CreateJavaVM(&vm, (void **)&(_jniEnv), &_vmArgs);
    }
    
    return self;
}

- (void)dealloc
{
    (*_vm)->DestroyJavaVM(_vm);
    [super dealloc];
}
@end
