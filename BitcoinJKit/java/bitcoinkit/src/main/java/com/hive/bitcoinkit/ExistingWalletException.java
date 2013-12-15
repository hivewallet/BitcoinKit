package com.hive.bitcoinkit;

public class ExistingWalletException extends Exception
{
    public ExistingWalletException(String message)
    {
        super(message);
    }

    public ExistingWalletException(String message, Throwable cause)
    {
        super(message, cause);
    }

    public ExistingWalletException(Throwable cause)
    {
        super(cause);
    }
}
