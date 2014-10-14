package com.hivewallet.bitcoinkit;

import org.bitcoinj.protocols.payments.PaymentProtocolException;

public class WrongNetworkException extends PaymentProtocolException {
    public WrongNetworkException(String message) {
        super(message);
    }

    public WrongNetworkException(Exception e) {
        super(e);
    }
}
