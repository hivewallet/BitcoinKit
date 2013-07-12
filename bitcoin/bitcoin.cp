/*
 *  bitcoin.cp
 *  bitcoin
 *
 *  Created by Bazyli Zygan on 11.07.2013.
 *  Copyright (c) 2013 Hive Developers. All rights reserved.
 *
 */

#include <iostream>
#include "bitcoin.h"
#include "bitcoinPriv.h"

void bitcoin::HelloWorld(const char * s)
{
	 bitcoinPriv *theObj = new bitcoinPriv;
	 theObj->HelloWorldPriv(s);
	 delete theObj;
};

void bitcoinPriv::HelloWorldPriv(const char * s) 
{
	std::cout << s << std::endl;
};

