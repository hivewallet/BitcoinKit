package com.hive.bitcoinkit;

public class NoWalletException extends Exception
{
    public NoWalletException(String message)
    {
        super(message);
    }

    public NoWalletException(String message, Throwable cause)
    {
        super(message, cause);
    }

    public NoWalletException(Throwable cause)
    {
        super(cause);
    }
}
