//
//  HIBitcoinManager.h
//  BitcoinKit
//
//  Created by Bazyli Zygan on 11.07.2013.
//  Copyright (c) 2013 Hive Developers. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString * const kHIBitcoinManagerTransactionChangedNotification;            //<<< Transaction list update notification. Sent object is a NSString representation of the updated hash
extern NSString * const kHIBitcoinManagerStartedNotification;                       //<<< Manager start notification. Informs that manager is now ready to use
extern NSString * const kHIBitcoinManagerStoppedNotification;                       //<<< Manager stop notification. Informs that manager is now stopped and can't be used anymore

/** HIBitcoinManager is a class responsible for managing all Bitcoin actions app should do 
 *
 *  Word of warning. One should not create this object. All access should be done
 *  via defaultManager class method that returns application-wide singleton to it.
 *  
 *  All properties are KVC enabled so one can register as an observer to them to monitor the changes.
 */
@interface HIBitcoinManager : NSObject

@property (nonatomic, copy) NSString *appSupportDirectoryIdentifier;                                         //<<< Specifies the support directory identifier. Warning! All changes to it has to be performed BEFORE start.
@property (nonatomic, copy) NSString *appName;                                         //<<< Specifies an App Name. The name will be used for data file/folder creation. Warning! All changes to it has to be performed BEFORE start.
@property (nonatomic, copy) NSURL *dataURL;                                         //<<< Specifies an URL path to a directory where HIBitcoinManager should store its data. Warning! All changes to it has to be performed BEFORE start.
@property (nonatomic, assign) BOOL testingNetwork;                                  //<<< Specifies if a manager is running on the testing network. Warning! All changes to it has to be performed BEFORE start.
@property (nonatomic, assign) BOOL enableMining;                                    //<<< Specifies if a manager should try to mine bticoins. Warning! All changes to it has to be performed BEFORE start.
@property (nonatomic, readonly) NSUInteger connections;                             //<<< Currently active connections to bitcoin network
@property (nonatomic, readonly) BOOL isRunning;                                     //<<< Flag indicating if NPBitcoinManager is currently running and connecting with the network
@property (nonatomic, readonly) uint64_t balance;                                   //<<< Actual balance of the wallet
@property (nonatomic, readonly) NSUInteger syncProgress;                            //<<< Integer value indicating the progress of network sync. Values are from 0 to 10000.
@property (nonatomic, readonly, getter = walletAddress) NSString *walletAddress;    //<<< Returns wallets main address. Creates one if none exists yet
@property (nonatomic, readonly, getter = isWalletEncrypted) BOOL isWalletEncrypted; //<<< Returns YES if wallet is encrypted. NO - otherwise
@property (nonatomic, readonly, getter = isWalletLocked) BOOL isWalletLocked;       //<<< Returns YES if wallet is currently locked. NO - otherwise
@property (nonatomic, readonly, getter = transactionCount) NSUInteger transactionCount; //<<< Returns global transaction cound for current wallet
@property (nonatomic, copy) NSString *proxyAddress;                                 //<<< Proxy server in address:port format. Default is nil (no proxy). Warning! All changes to it has to be performed BEFORE start.
@property (nonatomic, assign) BOOL disableListening;                                //<<< Flag disabling listening on public IP address. To be used i.e. with tor proxy not to reveal real IP address. Warning! All changes to it has to be performed BEFORE start.

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

/** Returns transaction definition based on transaction hash
 *
 * @param hash NSString representation of transaction hash
 *
 * @returns NSDictionary definition of found transansaction. nil if not found
 */
- (NSDictionary *)transactionForHash:(NSString *)hash;

/** Returns transaction definition based on transaction hash
 *
 * WARNING: Because transaction are kept in maps in bitcoind the only way
 * to find an element at requested index is to iterate through all of elements
 * in front. DO NOT USE too often or your app will get absurdely slow
 *
 * @param index Index of the searched transaction
 *
 * @returns NSDictionary definition of found transansaction. nil if not found
 */
- (NSDictionary *)transactionAtIndex:(NSUInteger)index;

/** Returns an array of definitions of all transactions 
 *
 * @returns Array of all transactions to this wallet
 */
- (NSArray *)allTransactions;

/** Returns array of transactions from given range
 *
 * @param range Range of requested transactions
 *
 * @returns An array of transactions from requested range
 */
- (NSArray *)transactionsWithRange:(NSRange)range;

/** Checks if given address is valid address
 *
 * @param address Address string to be checked
 *
 * @returns YES if address is valid. NO - otherwise
 */
- (BOOL)isAddressValid:(NSString *)address;

/** Sends amount of coins to receipent
 *
 * @param coins Amount of coins to be sent in satoshis
 * @param receipent Receipent address hash
 * @param comment optional comment string that will be bound to the transaction
 * @param complection Completion block where notification about created transaction hash will be sent
 *
 */
- (void)sendCoins:(uint64_t)coins toReceipent:(NSString *)receipent comment:(NSString *)comment completion:(void(^)(NSString *hash))completion;

/** Encrypts wallet with given passphrase
 *
 * @param passwd NSString value of the passphrase to encrypt wallet with
 *
 * @returns YES if encryption was successful, NO - otherwise
 */
- (BOOL)encryptWalletWith:(NSString *)passwd;

/** Changes the encryption passphrase for the wallet
 *
 * @param oldpasswd Old passphrase that wallet is currently encrypted with
 * @param newpasswd New passphrase that wallet should be encrypted with
 *
 * @returns YES if recryption was successful, NO - otherwise
 */
- (BOOL)changeWalletEncryptionKeyFrom:(NSString *)oldpasswd to:(NSString *)newpasswd;

/** Unlocks wallet
 *
 * @param passwd Passphrase that wallet is locked with
 *
 * @returns YES if unlock was successful, NO - otherwise
 */
- (BOOL)unlockWalletWith:(NSString *)passwd;

/** Locks wallet */
- (void)lockWallet;

/** Exports wallet to given file URL
 *
 * @param exportURL NSURL to local file where wallet should be dumped to
 *
 * @returns YES if dump was successful. NO - otherwise
 */
- (BOOL)exportWalletTo:(NSURL *)exportURL;

/** Import wallet from given file URL
 *
 * @param importURL NSURL to local file from which to import wallet data
 *
 * @returns YES if import was successful. NO - otherwise
 */
- (BOOL)importWalletFrom:(NSURL *)importURL;
@end
 
