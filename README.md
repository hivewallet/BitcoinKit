BitcoinKit.framework
===================

BitcoinKit.framework allows you to access and use bitcoin wallets in your applications. It uses both bitcoind (BitcoinKit.framework) AND BitcoinJ (BitcoinJKit.framework).

About BitcoinKit.framework
--------------------------

The BitcoinKit.framework uses original bitcoind sources to deliver functionality needed for managing bitcoin wallets. If your Mac application need the access to bitcoin network, this is what you need.

About BitcoinJKit.framework
---------------------------

The BitcoinJKit.framework uses bitcoinj sources to deliver bitcoin functionality with SPV. Your application will need to request for java support because - up till now - BitcoinJKit.framework requires external JVM. That may change in a near future.

Build Instructions for BitcoinKit.framework
-------------------------------------------


In order to be able to compile this stuff you need to use homebrew and do the following:

	brew install boost miniupnpc openssl berkeley-db4 kyoto-cabinet

&

	brew link openssl --force

And remember to fetch bitcoind sources!

	git submodule update --init --recursive

Now you're ready to go!

Build Instructions for BitcoinJKit.framework
-------------------------------------------

For that you need to have java and maven installed

	brew install maven

And you also have to remember to fetch all submodules!

	git submodule update --init --recursive

Time to compile!

How to use
----------

BitcoinKit.framework & BitcoinJKit.framework share the same API. They deliver a singleton of class HIBitcoinManager. With this object you are able to access bitcoin network and manage your wallet

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
[[HIBitcoinManager defaultManager] sendCoins:1000 toReceipent:receipentHashAddress comment:@"Here's some money for you!" completion:nil];
```

And more!

Demo App
--------

There's a demo application included with the sources. Start it up and check out how to use BitcoinKit.framework && BitcoinJKit.framework!

License
-------

BitcoinKit.framework & BitcoinJKit.framework are available under the MIT license.