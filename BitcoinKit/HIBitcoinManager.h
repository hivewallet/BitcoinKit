//
//  HIBitcoinManager.h
//  BitcoinKit
//
//  Created by Bazyli Zygan on 11.07.2013.
//  Copyright (c) 2013 Hive Developers. All rights reserved.
//

#import <Foundation/Foundation.h>

/** HIBitcoinManager is a class responsible for managing all Bitcoin actions app should do 
 *
 *  Word of warning. One should not create this object. All access should be done
 *  via defaultManager class method that returns application-wide singleton to it.
 *  
 *  All properties are KVC enabled so one can register as an observer to them to monitor the changes.
 */
@interface HIBitcoinManager : NSObject

@property (nonatomic, copy) NSURL *dataURL;                                         //<<< Specifies an URL path to a directory where HIBitcoinManager should store its data. Warning! All changes to it has to be performed BEFORE start.
@property (nonatomic, assign) BOOL testingNetwork;                                  //<<< Specifies if a manager is running on the testing network. Warning! All changes to it has to be performed BEFORE start.
@property (nonatomic, assign) BOOL enableMining;                                    //<<< Specifies if a manager should try to mine bticoins. Warning! All changes to it has to be performed BEFORE start.
@property (nonatomic, readonly) NSUInteger connections;                             //<<< Currently active connections to bitcoin network
@property (nonatomic, readonly) BOOL isRunning;                                     //<<< Flag indicating if NPBitcoinManager is currently running and connecting with the network
@property (nonatomic, readonly) uint64_t balance;                                   //<<< Actual balance of the wallet
@property (nonatomic, readonly) NSUInteger syncProgress;                            //<<< Integer value indicating the progress of network sync. Values are from 0 to 10000.
@property (nonatomic, readonly, getter = walletAddress) NSString *walletAddress;    //<<< Returns wallets main address. Creates one if none exists yet

/** Class method returning application singleton to the manager.
 *
 * Please note not to create HIBitcoinManager objects in any other way.
 * This is due to bitcoind implementation that uses global variables that
 * currently allows us to create only one instance of this object.
 * Which should be more than enough anyway.
 *
 * @returns Initialized and ready manager object.
 */
+ (HIBitcoinManager *)defaultManager;

/** Starts the manager initializing all data and starting network sync. 
 *
 * One should start the manager only once. After configuring the singleton.
 * Every time one will try to do that again - it will crash
 * This is due to bitcoind implementation that uses too many globals.
 */
- (void)start;

/** Stops the manager and stores all up-to-date information in data folder
 *
 * One should stop the manager only once. At the shutdown procedure.
 * This is due to bitcoind implementation that uses too many globals.
 */
- (void)stop;

@end
