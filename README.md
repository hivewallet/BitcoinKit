BitcoinKit.framework
===================

BitcoinKit.framework allows you to access and use bitcoin wallets in your applications.

About BitcoinKit.framework
--------------------------

The BitcoinKit.framework uses original bitcoind sources to deliver functionality needed for managing bitcoin wallets. If your Mac application need the access to bitcoin network, this is what you need.

Build Instructions
------------------

In order to be able to compile this stuff you need to use homebrew and do the following:

	brew install boost miniupnpc openssl berkeley-db4 kyoto-cabinet

&

	brew link openssl --force

And remember to fetch bitcoind sources!

	git submodule update --init

Now you're ready to go!

How to use
----------

BitcoinKit.framework delivers a singleton of class HIBitcoinManager. With this object you are able to access bitcoin network and manage your wallet

First you need to prepare the library for launching.

Set up where wallet and bitcoin network data should be kept

```objective-c
[HIBitcoinManager defaultManager].dataURL = [[self applicationSupportDir] URLByAppendingPathComponent:@"com.mycompany.MyBitcoinWalletData"];
```

Decide if you want to use a testing network (or not)

```objective-c
[HIBitcoinManager defaultManager].testingNetwork = YES;
```

...and start the network!

```objective-c
[[HIBitcoinManager defaultManager] start];
```

Now you can easily get the balance or wallet address:

```objective-c
NSString *walletAddress [HIBitcoinManager defaultManager].walletAddress;
uint64_t balance = [HIBitcoinManager defaultManager].balance
```

You can send coins

```objective-c
[[HIBitcoinManager defaultManager] sendCoins:1000 toReceipent:receipentHashAddress comment:@"Here's some money for you!"];
```

And more!

Demo App
--------

There's a demo application included with the sources. Start it up and check out how to use BitcoinKit.framework!

License
-------

BitcoinKit.framework is available under the MIT license.