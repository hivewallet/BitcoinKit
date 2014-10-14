package com.hivewallet.bitcoinkit;

import org.bitcoinj.protocols.payments.PaymentRequestException;

public class WrongNetworkException extends PaymentRequestException {
    public WrongNetworkException(String message) {
        super(message);
    }

    public WrongNetworkException(Exception e) {
        super(e);
    }
}
