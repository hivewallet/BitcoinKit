//
//  HIAppDelegate.m
//  HIBitcoinKitDemo
//
//  Created by Bazyli Zygan on 12.07.2013.
//  Copyright (c) 2013 Hive Developers. All rights reserved.
//

#import <BitcoinJKit/BitcoinJKit.h>
#import "HIAppDelegate.h"
#import "HISendWindowController.h"

@interface HIAppDelegate ()
{
    NSArray *_transactions;
    NSDateFormatter *_dateFormatter;
    HIBitcoinManager *_manager;
    HISendWindowController *_sendController;
}

@end

@implementation HIAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Configure columns in tableview
    _dateFormatter = [[NSDateFormatter alloc] init];
    [_dateFormatter setDateStyle:NSDateFormatterFullStyle];
    [_dateFormatter setTimeStyle:NSDateFormatterFullStyle];

    [_transactionList.tableColumns[0] setIdentifier:@"category"];
    [_transactionList.tableColumns[1] setIdentifier:@"amount"];
    [_transactionList.tableColumns[2] setIdentifier:@"address"];
    [_transactionList.tableColumns[3] setIdentifier:@"time"];

    _manager = [HIBitcoinManager defaultManager];

    [_manager addObserver:self
               forKeyPath:@"connections"
                  options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                  context:NULL];
    [_manager addObserver:self
               forKeyPath:@"balance"
                  options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                  context:NULL];
    [_manager addObserver:self
               forKeyPath:@"syncProgress"
                  options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                  context:NULL];
    [_manager addObserver:self
               forKeyPath:@"isRunning"
                  options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                  context:NULL];

    [_progressIndicator startAnimation:self];
    _manager.testingNetwork = YES;
//    _manager.enableMining = YES;
    [_manager start:NULL];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(transactionUpdated:)
                                                 name:kHIBitcoinManagerTransactionChangedNotification
                                               object:nil];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    if (_manager.isRunning)
    {
        return NSTerminateNow;
    }

    return NSTerminateCancel;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_progressIndicator stopAnimation:self];

    [_manager stop];
    [_manager removeObserver:self forKeyPath:@"connections"];
    [_manager removeObserver:self forKeyPath:@"balance"];
    [_manager removeObserver:self forKeyPath:@"syncProgress"];
    [_manager removeObserver:self forKeyPath:@"isRunning"];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
    if (object == _manager)
    {
        if ([keyPath isEqual:@"connections"])
        {
            _connectionsLabel.stringValue = [NSString stringWithFormat:@"%lu", _manager.connections];
        }
        else if ([keyPath isEqual:@"balance"])
        {
            _balanceLabel.stringValue = [NSString stringWithFormat:@"%.4f ฿", (CGFloat) _manager.balance / 100000000.0];
        }
        else if ([keyPath isEqual:@"isRunning"])
        {
            if (_manager.isRunning)
            {
                _stateLabel.stringValue = @"Synchronizing...";
                _addressLabel.stringValue = _manager.walletAddress;
                [_sendMoneyBtn setEnabled:YES];
                [_importBtn setEnabled:YES];
                [_exportBtn setEnabled:YES];
                
                // We have to refresh transaction list here
                _transactions = [_manager allTransactions];
                [_transactionList reloadData];
            }
        }
        else if ([keyPath isEqual:@"syncProgress"])
        {
            if (_manager.syncProgress > 0)
            {
                [_progressIndicator setIndeterminate:NO];
                [_progressIndicator setDoubleValue:_manager.syncProgress];
            }
            else
            {
                [_progressIndicator setIndeterminate:YES];
            }

            if (_manager.syncProgress == 10000)
            {
                [_progressIndicator stopAnimation:self];
                _stateLabel.stringValue = @"Synchronized";
            }
            else
            {
                [_progressIndicator startAnimation:self];
                if (_manager.isRunning)
                {
                    _stateLabel.stringValue = @"Synchronizing...";
                }
            }
        }
    }
}

- (void)transactionUpdated:(NSNotification *)not
{
    // In here we simply reload all transactions.
    // Real apps can do it in more inteligent fashion
    _transactions = [_manager allTransactions];
    [_transactionList reloadData];
}

#pragma mark - TableView methods

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return _transactions.count;
}

- (id)tableView:(NSTableView *)aTableView
objectValueForTableColumn:(NSTableColumn *)aTableColumn
            row:(NSInteger)rowIndex
{
    NSDictionary *transaction = _transactions[rowIndex];
    NSString *identifier = [aTableColumn identifier];

    if ([identifier isEqual:@"category"])
    {
        return transaction[@"details"][0][@"category"];
    }
    else if ([identifier isEqual:@"amount"])
    {
        return [NSString stringWithFormat:@"%.4f ฿", [transaction[@"amount"] longLongValue] / 100000000.0];
    }
    else if ([identifier isEqual:@"address"])
    {
        return transaction[@"details"][0][@"address"];
    }
    else if ([identifier isEqual:@"time"])
    {
        return [_dateFormatter stringFromDate:transaction[@"time"]];
    }

    return nil;
}

- (IBAction)sendMoneyClicked:(NSButton *)sender
{
    _sendController = [[HISendWindowController alloc] initWithWindowNibName:@"HISendWindowController"];

    [NSApp beginSheet:_sendController.window
       modalForWindow:self.window
        modalDelegate:self
       didEndSelector:@selector(sendClosed:)
          contextInfo:NULL];
}

- (IBAction)exportWalletClicked:(NSButton *)sender
{
    NSSavePanel *sp = [NSSavePanel savePanel];
    sp.title = @"Select where to save your wallet dump";
    sp.prompt = @"Dump";
    sp.allowedFileTypes = @[@"dat"];

    if ([sp runModal] == NSFileHandlingPanelOKButton)
    {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Wallet export"];

        if ([_manager exportWalletTo:sp.URL])
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

    if ([op runModal] == NSFileHandlingPanelOKButton)
    {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Wallet import"];

        if ([_manager importWalletFrom:op.URL])
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
