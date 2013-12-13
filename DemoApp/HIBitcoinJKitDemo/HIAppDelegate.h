//
//  HIAppDelegate.h
//  HIBitcoinKitDemo
//
//  Created by Bazyli Zygan on 12.07.2013.
//  Copyright (c) 2013 Hive Developers. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface HIAppDelegate : NSObject <NSApplicationDelegate, NSTableViewDataSource>

@property (assign) IBOutlet NSWindow *window;
@property (weak) IBOutlet NSTextField *addressLabel;
@property (weak) IBOutlet NSTextField *balanceLabel;
@property (weak) IBOutlet NSTextField *connectionsLabel;
@property (weak) IBOutlet NSProgressIndicator *progressIndicator;
@property (weak) IBOutlet NSTextField *stateLabel;
@property (weak) IBOutlet NSTableView *transactionList;
@property (weak) IBOutlet NSButton *sendMoneyBtn;
@property (weak) IBOutlet NSButton *importBtn;
@property (weak) IBOutlet NSButton *exportBtn;

- (IBAction)sendMoneyClicked:(NSButton *)sender;
- (IBAction)exportWalletClicked:(NSButton *)sender;
- (IBAction)importWalletClicked:(NSButton *)sender;

@end
