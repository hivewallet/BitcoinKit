BitcoinKit.framework
===================

BitcoinKit.framework allows you to access and use Bitcoin wallets in your applications. It uses Mike Hearn's bitcoinj Java library. This is an SPV implementation, so it doesn't need to download the whole blockchain to work.

Since a large part of the code is in Java, your application will need to ask the user to install a JRE in the system. This might change in future if we find a way to integrate a lightweight JVM into the project.


Build Instructions for BitcoinJKit.framework
-------------------------------------------

For that you need to have java and maven installed:

    brew install maven

And you also have to remember to fetch all submodules!

    git submodule update --init --recursive

Time to compile!


How to use
----------

The main access point is the singleton object of class HIBitcoinManager. With this object you are able to access the Bitcoin network and manage your wallet.

First you need to prepare the library for launching.

Set up where wallet and Bitcoin network data should be kept:

```objective-c
[HIBitcoinManager defaultManager].dataURL = [[self applicationSupportDir] URLByAppendingPathComponent:@"com.mycompany.MyBitcoinWalletData"];
```

Decide if you want to use a testing network (or not):

```objective-c
[HIBitcoinManager defaultManager].testingNetwork = YES;
```

...and start the network!

```objective-c
[[HIBitcoinManager defaultManager] start:&error];
```

Now you can easily get the balance or wallet address:

```objective-c
NSString *walletAddress [HIBitcoinManager defaultManager].walletAddress;
uint64_t balance = [HIBitcoinManager defaultManager].balance
```

You can send coins:

```objective-c
[[HIBitcoinManager defaultManager] sendCoins:1000 toRecipient:hashAddress comment:@"Here's some money for you!" password:nil error:&error completion:nil];
```

And more!


Demo App
--------

There's a demo application included with the sources. Start it up and check out how to use BitcoinKit.framework!

License
-------

BitcoinKit.framework is available under the MIT license.
