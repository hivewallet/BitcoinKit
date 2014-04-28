//
//  HIBitcoinErrorCodes.h
//  Hive
//
//  Created by Nikolaj Schumacher on 30.11.2013.
//  Copyright (c) 2013 Hive Developers. All rights reserved.
//

/* The wallet file exists but could not be read. */
extern NSInteger const kHIBitcoinManagerUnreadableWallet;

/* Acessing a block store file failed because it's locked by another process. */
extern NSInteger const kHIBitcoinManagerBlockStoreLockError;

/* There is no wallet and it needs to be created. */
extern NSInteger const kHIBitcoinManagerNoWallet;

/* A wallet could not be created because it already exists. */
extern NSInteger const kHIBitcoinManagerWalletExists;

/* An operation could not be completed because a wrong password was specified. */
extern NSInteger const kHIBitcoinManagerWrongPassword;

/* Accessing block store file failed (e.g. file is corrupted). */
extern NSInteger const kHIBitcoinManagerBlockStoreReadError;

/* The user tried to send dust. */
extern NSInteger const kHIBitcoinManagerSendingDustError;

/* The user tried to send more than the wallet balance. */
extern NSInteger const kHIBitcoinManagerInsufficientMoneyError;
