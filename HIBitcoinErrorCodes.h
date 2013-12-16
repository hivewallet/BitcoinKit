//
//  HIBitcoinErrorCodes.h
//  Hive
//
//  Created by Nikolaj Schumacher on 30.11.2013.
//  Copyright (c) 2013 Hive Developers. All rights reserved.
//

/* The wallet file exists but could not be read. */
extern NSInteger const kHIBitcoinManagerUnreadableWallet;

/* Storing a block failed (e.g. because the file is locked or the volume is full). */
extern NSInteger const kHIBitcoinManagerBlockStoreError;

/* There is no wallet and it needs to be created. */
extern NSInteger const kHIBitcoinManagerNoWallet;

/* A wallet could not be created because it already exists. */
extern NSInteger const kHIBitcoinManagerWalletExists;

/* An operation could not be completed because a wrong password was specified. */
extern NSInteger const kHIBitcoinManagerWalletExists;
