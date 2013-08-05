//
//  HIJavaBridge.h
//  BitcoinKit
//
//  Created by Bazyli Zygan on 26.07.2013.
//  Copyright (c) 2013 Hive Developers. All rights reserved.
//

#import <Foundation/Foundation.h>
//#include "jni.h"
#import <JavaVM/jni.h>

@protocol HIJavaObject <NSObject>

- (jobject)jobject;

@end

@interface HIJavaBridge : NSObject

@property (nonatomic, readonly, getter = jniEnvironment) JNIEnv *jniEnvironment;

+ (HIJavaBridge *)sharedBridge;

- (jclass)jClassForClass:(NSString *)class;

- (jobject)createObjectOfClass:(NSString *)class params:(NSArray *)params;
@end
