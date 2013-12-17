//
//  HISendWindowController.m
//  HIBitcoinKitDemo
//
//  Created by Bazyli Zygan on 14.07.2013.
//  Copyright (c) 2013 Hive Developers. All rights reserved.
//
#import <BitcoinJKit/BitcoinJKit.h>
#import "HISendWindowController.h"


@implementation HISendWindowController

- (id)initWithWindow:(NSWindow *)window
{
    self = [super initWithWindow:window];

    if (self) {
        // Initialization code here.
    }

    return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    // Implement this method to handle any initialization after your window controller's window has been loaded
    // from its nib file.
}

- (IBAction)cancelClicked:(NSButton *)sender
{
    [NSApp endSheet:self.window];
    [self.window close];
}

- (IBAction)sendClicked:(NSButton *)sender
{
    HIBitcoinManager *manager = [HIBitcoinManager defaultManager];

    // Sanity check first
    NSString *address = _addressField.stringValue;
    CGFloat amount = [_amountField.stringValue floatValue];
    NSLog(@"Balance %llu and amount %llu", [manager balance], (long long) (amount * 100000000));

    if (amount <= 0 ||
        [manager balance] < (long long) (amount * 100000000) ||
        ![manager isAddressValid:address])
    {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Cannot send money"];

        if (amount <= 0)
        {
            [alert setInformativeText:@"Your amount is invalid"];
        }
        else if ([manager balance] < (long long)(amount * 100000000))
        {
            [alert setInformativeText:@"You can't send more than you own"];
        }
        else if (![manager isAddressValid:address])
        {
            [alert setInformativeText:@"Given receipent address is invalid"];
        }

        [alert addButtonWithTitle:@"Ok"];
        [alert runModal];
    }
    else
    {
        [manager sendCoins:(amount * 100000000)
               toRecipient:address
                   comment:nil
                  password:nil
                     error:NULL
                completion:^(NSString *hash)
        {
            if (hash)
            {
                [self cancelClicked:sender];
            }
            else
            {
                NSAlert *alert = [[NSAlert alloc] init];
                [alert setMessageText:@"Cannot send money"];
                [alert setInformativeText:@"Failed to send money"];
                [alert addButtonWithTitle:@"Ok"];
                [alert runModal];            
            }            
        }];
    }
}

@end
