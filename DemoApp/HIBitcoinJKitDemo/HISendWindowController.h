//
//  HISendWindowController.h
//  HIBitcoinKitDemo
//
//  Created by Bazyli Zygan on 14.07.2013.
//  Copyright (c) 2013 Hive Developers. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface HISendWindowController : NSWindowController
@property (weak) IBOutlet NSTextField *addressField;
@property (weak) IBOutlet NSTextField *amountField;

- (IBAction)cancelClicked:(NSButton *)sender;
- (IBAction)sendClicked:(NSButton *)sender;
@end
