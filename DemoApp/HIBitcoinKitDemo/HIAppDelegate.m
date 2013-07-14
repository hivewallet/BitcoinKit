//
//  HIAppDelegate.m
//  HIBitcoinKitDemo
//
//  Created by Bazyli Zygan on 12.07.2013.
//  Copyright (c) 2013 Hive Developers. All rights reserved.
//

#import <BitcoinKit/BitcoinKit.h>
#import "HIAppDelegate.h"

@interface HIAppDelegate ()

- (void)transactionUpdated:(NSNotification *)not;

@end

@implementation HIAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    
    [[HIBitcoinManager defaultManager] addObserver:self forKeyPath:@"connections" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:NULL];
    [[HIBitcoinManager defaultManager] addObserver:self forKeyPath:@"balance" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:NULL];
    [[HIBitcoinManager defaultManager] addObserver:self forKeyPath:@"syncProgress" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:NULL];
    [[HIBitcoinManager defaultManager] addObserver:self forKeyPath:@"isRunning" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:NULL];
    [_progressIndicator startAnimation:self];
    [HIBitcoinManager defaultManager].testingNetwork = YES;
//    [HIBitcoinManager defaultManager].enableMining = YES;
    [[HIBitcoinManager defaultManager] start];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(transactionUpdated:) name:kHIBitcoinManagerTransactionChanged object:nil];
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
            _balanceLabel.stringValue = [NSString stringWithFormat:@"%.4f ฿", (CGFloat)[HIBitcoinManager defaultManager].balance / 10000000.0];
        }
        else if ([keyPath compare:@"isRunning"] == NSOrderedSame)
        {
            if ([HIBitcoinManager defaultManager].isRunning)
            {
                _stateLabel.stringValue = @"Synchronizing...";
                _addressLabel.stringValue = [HIBitcoinManager defaultManager].walletAddress;
                
                // We have to refresh transaction list here
                NSArray *transactions = [[HIBitcoinManager defaultManager] allTransactions];
                NSLog(@"All transactions so far %@", transactions);
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
    NSLog(@"Transaction changed %@ %@", not.userInfo, not.object);
}

@end
