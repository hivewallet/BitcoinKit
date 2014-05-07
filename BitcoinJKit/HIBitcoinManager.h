//
//  HIBitcoinManager.h
//  BitcoinKit
//
//  Created by Bazyli Zygan on 11.07.2013.
//  Copyright (c) 2013 Hive Developers. All rights reserved.
//

#import <Foundation/Foundation.h>

// Transaction list update notification. Sent object is a NSString representation of the updated hash
extern NSString * const kHIBitcoinManagerTransactionChangedNotification;

// Manager start notification. Informs that manager is now ready to use
extern NSString * const kHIBitcoinManagerStartedNotification;

// Manager stop notification. Informs that manager is now stopped and can't be used anymore
extern NSString * const kHIBitcoinManagerStoppedNotification;


/** HIBitcoinManager is a class responsible for managing all Bitcoin actions app should do 
 *
 *  Word of warning. One should not create this object. All access should be done
 *  via defaultManager class method that returns application-wide singleton to it.
 *  
 *  All properties are KVC enabled so one can register as an observer to them to monitor the changes.
 */
@interface HIBitcoinManager : NSObject

// Specifies an URL path to a directory where HIBitcoinManager should store its data.
// Warning! All changes to this property have to be made BEFORE start.
@property (nonatomic, copy) NSURL *dataURL;

// Specifies a path to a checkpoints file used to speed up blockchain sync (optional)
// Warning! All changes to this property have to be made BEFORE start.
//
// To create a checkpoints file, use the BuildCheckpoints class from bitcoinj, e.g.:
//   java -cp target/bitcoinj-tools-0.11-SNAPSHOT.jar com.google.bitcoin.tools.BuildCheckpoints
// Note: BuildCheckpoints only generates checkpoints for the main network (i.e. not for the testnet).
@property (nonatomic, copy) NSString *checkpointsFilePath;

// Specifies if a manager is running on the testing network.
// Warning! All changes to this property have to be made BEFORE start.
@property (nonatomic, assign) BOOL testingNetwork;

// Flag indicating if HIBitcoinManager is currently running and connecting with the network
@property (nonatomic, readonly) BOOL isRunning;

// Flag indicating if HIBitcoinManager is currently syncing with the Bitcoin network
@property (nonatomic, readonly) BOOL isSyncing;

// Actual balance of the wallet
@property (nonatomic, readonly) uint64_t availableBalance;

// Balance calculated assuming all pending transactions are included into the best chain by miners
@property (nonatomic, readonly) uint64_t estimatedBalance;

// Float value indicating the progress of network sync. Values are from 0 to 100.
@property (nonatomic, readonly) float syncProgress;

// Various details about the wallet dumped into a single string, useful for debugging
@property (nonatomic, readonly) NSString *walletDebuggingInfo;

// Returns wallets main address. Creates one if none exists yet
@property (nonatomic, readonly, getter = walletAddress) NSString *walletAddress;

// Returns YES if wallet is encrypted. NO - otherwise
@property (nonatomic, readonly, getter = isWalletEncrypted) BOOL isWalletEncrypted;

// Returns YES if wallet is currently locked. NO - otherwise
@property (nonatomic, readonly, getter = isWalletLocked) BOOL isWalletLocked;

// Returns global transaction cound for current wallet
@property (nonatomic, readonly, getter = transactionCount) NSUInteger transactionCount;

// Returns number of connected peers
@property (nonatomic, readonly) NSUInteger peerCount;

// Tells if the manager is connected to at least one peer
@property (nonatomic, readonly) BOOL isConnected;

// Returns date when the wallet password was last changed, or when the wallet was created (might be null for old files)
@property (nonatomic, readonly) NSDate *lastWalletChangeDate;

// Block that will be called when an exception is thrown on a background thread in JVM (e.g. while processing an
// incoming transaction or other blockchain update). If not set, the exception will just be thrown and will crash your
// app unless you install a global uncaught exception handler.
// Note: exceptions that are thrown while processing calls made from the Cocoa side will ignore this handler and will
// simply be thrown directly in the same thread.
@property (nonatomic, copy) void(^exceptionHandler)(NSException *exception);


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
 *
 * @param error A pointer to an error object (or NULL to throw an exception on errors)
 *
 * @returns NO if an error prevented proper initialization.
 */
- (BOOL)start:(NSError **)error;

/**
 * Creates a new unprotected wallet.
 *
 * Only call this if start returned kHIBitcoinManagerNoWallet.
 * It will fail if a wallet already exists.
 */
- (void)createWallet:(NSError **)error;

/**
 * Creates a new wallet protected with a password.
 *
 * Only call this if start returned kHIBitcoinManagerNoWallet.
 * It will fail if a wallet already exists.
 *
 * @param password The user password as an UTF-16-encoded string.
 */
- (void)createWalletWithPassword:(NSData *)password
                           error:(NSError **)error;

/** Changes the wallet's password.
 *
 * @param fromPassword The current wallet password as an UTF-16-encoded string.
 * @param toPassword The new wallet password as an UTF-16-encoded string.
 * @param error A pointer to an error object (or NULL to throw an exception on errors)
 */
- (void)changeWalletPassword:(NSData *)fromPassword
                  toPassword:(NSData *)toPassword
                       error:(NSError **)error;

/** Checks if the given password is correct.
 *
 * @param password The password to be checked.
 * @returns BOOL true if the password matches the one in the wallet
 */
- (BOOL)isPasswordCorrect:(NSData *)password;

/** Signs a given text message with the user's private key and returns the signature.
 *
 * @param message Message to be signed.
 * @param password The wallet password (if any).
 * @param error A pointer to an error object (or NULL to throw an exception on errors)
 */

- (NSString *)signMessage:(NSString *)message
             withPassword:(NSData *)password
                    error:(NSError **)error;

/** Stops the manager and stores all up-to-date information in data folder
 *
 * One should stop the manager only once. At the shutdown procedure.
 * This is due to bitcoind implementation that uses too many globals.
 */
- (void)stop;

/** Deletes the blockchain data file. */
- (void)deleteBlockchainDataFile:(NSError **)error;

/** Deletes the blockchain data file, restarts the network layer and starts rebuilding the wallet from the blockchain.
 *
 * @param error A pointer to an error object (or NULL to throw an exception on errors)
 */
- (void)resetBlockchain:(NSError **)error;

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

/** Calculates the transaction fee when sending coins.
 *
 * @param coins Amount of coins for the recipient to receive in satoshis
 * @param recipient Target address
 */
- (uint64_t)calculateTransactionFeeForSendingCoins:(uint64_t)coins toRecipient:(NSString *)recipient;

/** Sends amount of coins to recipient
 *
 * @param coins Amount of coins to be sent in satoshis
 * @param recipient Recipient's address hash
 * @param comment optional comment string that will be bound to the transaction
 * @param complection Completion block where notification about created transaction hash will be sent
 *
 */
- (void)sendCoins:(uint64_t)coins
      toRecipient:(NSString *)recipient
          comment:(NSString *)comment
         password:(NSData *)password
            error:(NSError **)error
       completion:(void(^)(NSString *hash))completion;

/** Loads a Payment Protocol compatible payment request from a local file.
 *
 * @param filename Path to the .bitcoinpaymentrequest file
 * @param outError Returned error if the payment request file can't be opened
 * @param callback Block that will be called when the request is loaded or an error occurs;
 *                 returns: error (if any), session id (to be returned later), request data dictionary
 * @return true if the request file was opened
 */
- (BOOL)openPaymentRequestFromFile:(NSString *)filename
                             error:(NSError **)outError
                          callback:(void(^)(NSError*, int, NSDictionary*))callback;

/** Loads a Payment Protocol compatible payment request from a remote URL.
 *
 * @param URL Location of the payment request resource
 * @param outError Returned error if the URL is empty or invalid
 * @param callback Block that will be called when the request is loaded or an error occurs;
 *                 returns: error (if any), session id (to be returned later), request data dictionary
 * @return true if the URL was valid and the request is being loaded
 */
- (BOOL)openPaymentRequestFromURL:(NSString *)URL
                            error:(NSError **)outError
                         callback:(void(^)(NSError*, int, NSDictionary*))callback;

/** Submits a payment using Payment Protocol.
 *
 * @param sessionId session id returned from one of the openPaymentRequest* methods
 * @param password wallet password, if any
 * @param callback Block that will be called when the payment is accepted or an error occurs;
 *                 returns: error (if any), ack response data dictionary
 */
- (void)sendPaymentRequest:(int)sessionId
                  password:(NSData *)password
                  callback:(void(^)(NSError*, NSDictionary*))callback;

/** Exports (backs up) the wallet to given file URL.
 *
 * @param exportURL NSURL to local file where the wallet file should be copied to
 * @param error reference to error variable where error info will be written if backup fails
 *
 */
- (void)exportWalletTo:(NSURL *)exportURL error:(NSError **)error;

@end
