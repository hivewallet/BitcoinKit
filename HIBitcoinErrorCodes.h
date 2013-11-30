//
//  HIBitcoinErrorCodes.h
//  Hive
//
//  Created by Nikolaj Schumacher on 30.11.2013.
//  Copyright (c) 2013 Hive Developers. All rights reserved.
//

/* Unknown error: This should have been handled internally or mapped to an error code. */
extern NSInteger const kHIBitcoinManagerUnexpectedError;

/* The wallet file exists but could not be read. */
extern NSInteger const kHIBitcoinManagerUnreadableWallet;

/* Storing a block failed (e.g. because the file is locked or the volume is full). */
extern NSInteger const kHIBitcoinManagerBlockStoreError;
