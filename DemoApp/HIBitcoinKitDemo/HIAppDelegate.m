//
//  HIAppDelegate.m
//  HIBitcoinKitDemo
//
//  Created by Bazyli Zygan on 12.07.2013.
//  Copyright (c) 2013 Hive Developers. All rights reserved.
//

#ifdef USE_BITCOINJ
#import <BitcoinJKit/BitcoinJKit.h>
#else
#import <BitcoinKit/BitcoinKit.h>
#endif //USE_BITCOINJ
#import "HIAppDelegate.h"
#import "HISendWindowController.h"

@interface HIAppDelegate ()
{
    NSArray *_transactions;
    NSDateFormatter *_dF;
    HISendWindowController *_sendController;
}
- (void)transactionUpdated:(NSNotification *)not;
- (void)sendClosed:(id)sender;
@end

@implementation HIAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Configure columns in tableview
    _dF = [[NSDateFormatter alloc] init];
    [_dF setDateStyle:NSDateFormatterFullStyle];
    [_dF setTimeStyle:NSDateFormatterFullStyle];
    [_transactionList.tableColumns[0] setIdentifier:@"category"];
    [_transactionList.tableColumns[1] setIdentifier:@"amount"];
    [_transactionList.tableColumns[2] setIdentifier:@"address"];
    [_transactionList.tableColumns[3] setIdentifier:@"time"];
    
    [[HIBitcoinManager defaultManager] addObserver:self forKeyPath:@"connections" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:NULL];
    [[HIBitcoinManager defaultManager] addObserver:self forKeyPath:@"balance" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:NULL];
    [[HIBitcoinManager defaultManager] addObserver:self forKeyPath:@"syncProgress" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:NULL];
    [[HIBitcoinManager defaultManager] addObserver:self forKeyPath:@"isRunning" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:NULL];
    [_progressIndicator startAnimation:self];
    [HIBitcoinManager defaultManager].testingNetwork = YES;
//    [HIBitcoinManager defaultManager].enableMining = YES;
    [[HIBitcoinManager defaultManager] start];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(transactionUpdated:) name:kHIBitcoinManagerTransactionChangedNotification object:nil];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    if ([HIBitcoinManager defaultManager].isRunning)
        return NSTerminateNow;
    
    return NSTerminateCancel;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_progressIndicator stopAnimation:self];
    [[HIBitcoinManager defaultManager] stop];
    [[HIBitcoinManager defaultManager] removeObserver:self forKeyPath:@"connections"];
    [[HIBitcoinManager defaultManager] removeObserver:self forKeyPath:@"balance"];
    [[HIBitcoinManager defaultManager] removeObserver:self forKeyPath:@"syncProgress"];
    [[HIBitcoinManager defaultManager] removeObserver:self forKeyPath:@"isRunning"];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (object == [HIBitcoinManager defaultManager])
    {
        if ([keyPath compare:@"connections"] == NSOrderedSame)
        {
            _connectionsLabel.stringValue = [NSString stringWithFormat:@"%lu", [HIBitcoinManager defaultManager].connections];
        }
        else if ([keyPath compare:@"balance"] == NSOrderedSame)
        {
            _balanceLabel.stringValue = [NSString stringWithFormat:@"%.4f ฿", (CGFloat)[HIBitcoinManager defaultManager].balance / 100000000.0];
        }
        else if ([keyPath compare:@"isRunning"] == NSOrderedSame)
        {
            if ([HIBitcoinManager defaultManager].isRunning)
            {
                _stateLabel.stringValue = @"Synchronizing...";
                _addressLabel.stringValue = [HIBitcoinManager defaultManager].walletAddress;
                [_sendMoneyBtn setEnabled:YES];
                [_importBtn setEnabled:YES];
                [_exportBtn setEnabled:YES];
                
                // We have to refresh transaction list here
                _transactions = [[HIBitcoinManager defaultManager] allTransactions];
                [_transactionList reloadData];
            }
        }
        else if ([keyPath compare:@"syncProgress"] == NSOrderedSame)
        {
            if ([HIBitcoinManager defaultManager].syncProgress > 0)
            {
                [_progressIndicator setIndeterminate:NO];
                [_progressIndicator setDoubleValue:[HIBitcoinManager defaultManager].syncProgress];
            }
            else
            {
                [_progressIndicator setIndeterminate:YES];
            }
            
            if ([HIBitcoinManager defaultManager].syncProgress == 10000)
            {
                [_progressIndicator stopAnimation:self];
                _stateLabel.stringValue = @"Synchronized";
            }
            else
            {
                [_progressIndicator startAnimation:self];
                if ([HIBitcoinManager defaultManager].isRunning)
                    _stateLabel.stringValue = @"Synchronizing...";
                
            }
        }
    }
}

- (void)transactionUpdated:(NSNotification *)not
{
    // In here we simply reload all transactions.
    // Real apps can do it in more inteligent fashion
    _transactions = [[HIBitcoinManager defaultManager] allTransactions];
    [_transactionList reloadData];
}

#pragma mark - TableView methods

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return _transactions.count;
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
    NSDictionary *transaction = _transactions[rowIndex];
    

    if ([[aTableColumn identifier] compare:@"category"] == NSOrderedSame)
        return transaction[@"details"][0][@"category"];
    else if ([[aTableColumn identifier] compare:@"amount"] == NSOrderedSame)
        return [NSString stringWithFormat:@"%.4f ฿", [((NSNumber *)transaction[@"amount"]) longLongValue] / 100000000.0];
    else if ([[aTableColumn identifier] compare:@"address"] == NSOrderedSame)
        return transaction[@"details"][0][@"address"];
    else if ([[aTableColumn identifier] compare:@"time"] == NSOrderedSame)
        return [_dF stringFromDate:transaction[@"time"]];
    return nil;
}


- (IBAction)sendMoneyClicked:(NSButton *)sender
{
    _sendController= [[HISendWindowController alloc] initWithWindowNibName:@"HISendWindowController"];
    [NSApp beginSheet:_sendController.window modalForWindow:self.window modalDelegate:self didEndSelector:@selector(sendClosed:) contextInfo:NULL];
}

- (IBAction)exportWalletClicked:(NSButton *)sender
{
    NSSavePanel *sp = [NSSavePanel savePanel];
    sp.title = @"Select where to save your wallet dump";
    sp.prompt = @"Dump";
    sp.allowedFileTypes = @[@"dat"];
    if (NSFileHandlingPanelOKButton == [sp runModal])
    {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Wallet export"];
        if ([[HIBitcoinManager defaultManager] exportWalletTo:sp.URL])
        {
            [alert setInformativeText:@"Export has been successful"];
        }
        else
        {
            [alert setInformativeText:@"Export has failed"];                        
        }
        [alert addButtonWithTitle:@"Ok"];        
        [alert runModal];
    }

}

- (IBAction)importWalletClicked:(NSButton *)sender
{
    NSOpenPanel *op = [NSOpenPanel openPanel];
    op.title = @"Select dump file to import";
    op.prompt = @"Import";
    op.allowedFileTypes = @[@"dat"];
    if (NSFileHandlingPanelOKButton == [op runModal])
    {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Wallet import"];
        if ([[HIBitcoinManager defaultManager] importWalletFrom:op.URL])
        {
            [alert setInformativeText:@"Import has been successful"];
        }
        else
        {
            [alert setInformativeText:@"Import has failed"];
        }
        [alert addButtonWithTitle:@"Ok"];
        [alert runModal];
    }
}

- (void)sendClosed:(id)sender
{
    _sendController = nil;
}
@end
