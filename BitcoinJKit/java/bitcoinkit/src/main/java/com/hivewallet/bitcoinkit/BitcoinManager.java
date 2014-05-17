package com.hivewallet.bitcoinkit;

import com.google.bitcoin.core.*;
import com.google.bitcoin.crypto.KeyCrypter;
import com.google.bitcoin.crypto.KeyCrypterException;
import com.google.bitcoin.crypto.KeyCrypterScrypt;
import com.google.bitcoin.net.discovery.DnsDiscovery;
import com.google.bitcoin.params.MainNetParams;
import com.google.bitcoin.params.TestNet3Params;
import com.google.bitcoin.protocols.payments.PaymentRequestException;
import com.google.bitcoin.protocols.payments.PaymentSession;
import com.google.bitcoin.script.Script;
import com.google.bitcoin.store.BlockStore;
import com.google.bitcoin.store.BlockStoreException;
import com.google.bitcoin.store.SPVBlockStore;
import com.google.bitcoin.store.UnreadableWalletException;
import com.google.bitcoin.store.WalletProtobufSerializer;
import com.google.bitcoin.utils.Threading;
import com.google.common.collect.ImmutableList;
import com.google.common.util.concurrent.FutureCallback;
import com.google.common.util.concurrent.Futures;
import com.google.common.util.concurrent.ListenableFuture;
import org.bitcoinj.wallet.Protos;
import org.codehaus.jettison.json.JSONArray;
import org.codehaus.jettison.json.JSONException;
import org.codehaus.jettison.json.JSONObject;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.impl.CocoaLogger;
import org.spongycastle.crypto.params.KeyParameter;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.math.BigInteger;
import java.nio.CharBuffer;
import java.text.SimpleDateFormat;
import java.util.Arrays;
import java.util.Date;
import java.util.HashSet;
import java.util.HashMap;
import java.util.List;
import java.util.TimeZone;
import java.util.concurrent.TimeUnit;

public class BitcoinManager implements Thread.UncaughtExceptionHandler, TransactionConfidence.Listener {
    private NetworkParameters networkParams;
    private Wallet wallet;
    private String dataDirectory;
    private String checkpointsFilePath;

    private PeerGroup peerGroup;
    private BlockStore blockStore;
    private File walletFile;
    private int blocksToDownload;
    private HashSet<Transaction> trackedTransactions;
    private HashMap<Integer, PaymentSession> paymentSessions;
    private int paymentSessionsSequenceId = 0;

    private static final Logger log = LoggerFactory.getLogger(BitcoinManager.class);


    /* --- Initialization & configuration --- */

    public BitcoinManager() {
        Threading.uncaughtExceptionHandler = this;

        trackedTransactions = new HashSet<Transaction>();
        paymentSessions = new HashMap<Integer, PaymentSession>();

        ((CocoaLogger) log).setLevel(CocoaLogger.HILoggerLevelDebug);
    }

    public void setTestingNetwork(boolean testing) {
        if (testing) {
            this.networkParams = TestNet3Params.get();
        } else {
            this.networkParams = MainNetParams.get();
        }
    }

    public void setDataDirectory(String path) {
        dataDirectory = path;
    }

    public String getCheckpointsFilePath() {
        return checkpointsFilePath;
    }

    public void setCheckpointsFilePath(String path) {
        checkpointsFilePath = path;
    }


    /* --- Wallet lifecycle --- */

    public void start() throws NoWalletException, UnreadableWalletException, IOException, BlockStoreException {
        if (networkParams == null) {
            setTestingNetwork(false);
        }

        // Try to read the wallet from storage, create a new one if not possible.
        wallet = null;
        walletFile = new File(dataDirectory + "/bitcoinkit.wallet");

        if (!walletFile.exists()) {
            // Stop here, because the caller might want to create an encrypted wallet and needs to supply a password.
            throw new NoWalletException("No wallet file found at: " + walletFile);
        }

        try {
            useWallet(loadWalletFromFile(walletFile));
        } catch (FileNotFoundException e) {
            throw new NoWalletException("No wallet file found at: " + walletFile);
        }
    }

    public void addExtensionsToWallet(Wallet wallet) {
        wallet.addExtension(new LastWalletChangeExtension());
    }

    public Wallet loadWalletFromFile(File f) throws UnreadableWalletException {
        try {
            FileInputStream stream = null;

            try {
                stream = new FileInputStream(f);

                Wallet wallet = new Wallet(networkParams);
                addExtensionsToWallet(wallet);

                Protos.Wallet walletData = WalletProtobufSerializer.parseToProto(stream);
                new WalletProtobufSerializer().readWallet(walletData, wallet);

                if (!wallet.isConsistent()) {
                    log.error("Loaded an inconsistent wallet");
                }

                return wallet;
            } finally {
                if (stream != null) {
                    stream.close();
                }
            }
        } catch (IOException e) {
            throw new UnreadableWalletException("Could not open file", e);
        }
    }

    public void createWallet() throws IOException, BlockStoreException, ExistingWalletException {
        createWallet(null);
    }

    public void createWallet(char[] utf16Password) throws IOException, BlockStoreException, ExistingWalletException {
        if (walletFile == null) {
            throw new IllegalStateException("createWallet cannot be called before start");
        } else if (walletFile.exists()) {
            throw new ExistingWalletException("Trying to create a wallet even though one exists: " + walletFile);
        }

        Wallet wallet = new Wallet(networkParams);
        addExtensionsToWallet(wallet);
        updateLastWalletChange(wallet);

        ECKey privateKey = new ECKey();
        wallet.addKey(privateKey);
        long creationTime = privateKey.getCreationTimeSeconds();

        if (utf16Password != null) {
            encryptWallet(utf16Password, wallet);

            // temporary fix for bitcoinj creation time clearing bug
            ECKey encryptedKey = wallet.getKeys().get(0);
            encryptedKey.setCreationTimeSeconds(creationTime);
        }

        wallet.saveToFile(walletFile);

        // just in case an old file exists there for some reason
        deleteBlockchainDataFile();

        useWallet(wallet);
    }

    private void useWallet(Wallet wallet) throws BlockStoreException, IOException {
        this.wallet = wallet;

        //make wallet autosave
        wallet.autosaveToFile(walletFile, 1, TimeUnit.SECONDS, null);

        wallet.addEventListener(new AbstractWalletEventListener() {
            // get notified when an incoming transaction is received
            @Override
            public void onCoinsReceived(Wallet w, Transaction tx, BigInteger prevBalance, BigInteger newBalance) {
                BitcoinManager.this.onCoinsReceived(w, tx, prevBalance, newBalance);
            }

            // get notified when we send a transaction, or when we restore an outgoing transaction from the blockchain
            @Override
            public void onCoinsSent(Wallet w, Transaction tx, BigInteger prevBalance, BigInteger newBalance) {
                BitcoinManager.this.onCoinsSent(w, tx, prevBalance, newBalance);
            }

            @Override
            public void onReorganize(Wallet wallet) {
                BitcoinManager.this.onBalanceChanged();
            }
        });

        startBlockchain();

        wallet.cleanup();
    }

    private File getBlockchainFile() {
        return new File(dataDirectory + "/bitcoinkit.spvchain");
    }

    private void startBlockchain() throws BlockStoreException {
        // Load the block chain data file or generate a new one
        File chainFile = getBlockchainFile();
        boolean chainExistedAlready = chainFile.exists();
        blockStore = new SPVBlockStore(networkParams, chainFile);

        if (!chainExistedAlready) {
            // the blockchain will need to be replayed; if the wallet already contains transactions, this might
            // cause ugly inconsistent wallet exceptions, so clear all old transaction data first
            log.info("Chain file missing - wallet transactions list will be rebuilt now");
            wallet.clearTransactions(0);

            String checkpointsFilePath = this.checkpointsFilePath;
            if (checkpointsFilePath == null) {
                checkpointsFilePath = dataDirectory + "/bitcoinkit.checkpoints";
            }

            File checkpointsFile = new File(checkpointsFilePath);
            if (checkpointsFile.exists()) {
                long earliestKeyCreationTime = wallet.getEarliestKeyCreationTime();

                if (earliestKeyCreationTime == 0) {
                    // there was a bug in bitcoinj until recently that caused encrypted keys to lose their creation time
                    // so if we have no data from the wallet, use the time of the first Hive commit (15.05.2013) instead
                    earliestKeyCreationTime = 1368620845;
                }

                try {
                    FileInputStream stream = new FileInputStream(checkpointsFile);
                    CheckpointManager.checkpoint(networkParams, stream, blockStore, earliestKeyCreationTime);
                } catch (IOException e) {
                    throw new BlockStoreException("Could not load checkpoints file");
                }
            }
        }

        BlockChain chain = new BlockChain(networkParams, wallet, blockStore);

        peerGroup = new PeerGroup(networkParams, chain);
        peerGroup.setUserAgent("BitcoinJKit", "0.9");
        peerGroup.addPeerDiscovery(new DnsDiscovery(networkParams));
        peerGroup.addWallet(wallet);

        onBalanceChanged();
        trackPendingTransactions(wallet);

        peerGroup.addEventListener(new AbstractPeerEventListener() {
            @Override
            public void onPeerConnected(Peer peer, int peerCount) {
                BitcoinManager.this.onPeerConnected(peer, peerCount);
            }

            @Override
            public void onPeerDisconnected(Peer peer, int peerCount) {
                BitcoinManager.this.onPeerDisconnected(peer, peerCount);
            }
        });

        peerGroup.startAndWait();

        // get notified about sync progress
        peerGroup.startBlockChainDownload(new AbstractPeerEventListener() {
            @Override
            public void onBlocksDownloaded(Peer peer, Block block, int blocksLeft) {
                BitcoinManager.this.onBlocksDownloaded(peer, block, blocksLeft);
            }

            @Override
            public void onChainDownloadStarted(Peer peer, int blocksLeft) {
                BitcoinManager.this.onChainDownloadStarted(peer, blocksLeft);
            }
        });
    }

    private void trackPendingTransactions(Wallet wallet) {
        // we won't receive onCoinsReceived again for transactions that we already know about,
        // so we need to listen to confidence changes again after a restart
        for (Transaction tx : wallet.getPendingTransactions()) {
            trackTransaction(tx);
        }
    }

    private void trackTransaction(Transaction tx) {
        if (!trackedTransactions.contains(tx)) {
            log.debug("Tracking transaction " + tx.getHashAsString());

            tx.getConfidence().addEventListener(this);
            trackedTransactions.add(tx);
        }
    }

    private void stopTrackingTransaction(Transaction tx) {
        if (trackedTransactions.contains(tx)) {
            log.debug("Stopped tracking transaction " + tx.getHashAsString());

            tx.getConfidence().removeEventListener(this);
            trackedTransactions.remove(tx);
        }
    }

    public void deleteBlockchainDataFile() {
        log.info("Deleting blockchain data file...");
        File chainFile = getBlockchainFile();
        chainFile.delete();
    }

    public void resetBlockchain() {
        try {
            shutdownBlockchain();
            deleteBlockchainDataFile();

            blocksToDownload = 0;

            for (Transaction tx : (HashSet<Transaction>) trackedTransactions.clone()) {
                stopTrackingTransaction(tx);
            }

            startBlockchain();
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    public void stop() {
        try {
            log.info("Shutting down BitcoinManager...");

            shutdownBlockchain();

            if (wallet != null) {
                wallet.saveToFile(walletFile);
            }

            log.info("Shutdown done.");
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    private void shutdownBlockchain() throws BlockStoreException {
        log.info("Shutting down PeerGroup...");

        if (peerGroup != null) {
            peerGroup.stopAndWait();
            peerGroup.removeWallet(wallet);
            peerGroup = null;
        }

        log.info("Shutting down BlockStore...");

        if (blockStore != null) {
            blockStore.close();
            blockStore = null;
        }
    }

    public void exportWallet(String path) throws java.io.IOException {
        File backupFile = new File(path);
        wallet.saveToFile(backupFile);
    }


    /* --- Reading wallet data --- */

    public String getWalletAddress() {
        ECKey ecKey = wallet.getKeys().get(0);
        return ecKey.toAddress(networkParams).toString();
    }

    public String getWalletDebuggingInfo() {
        return (wallet != null) ? wallet.toString() : null;
    }

    public long getAvailableBalance() {
        return (wallet != null) ? wallet.getBalance().longValue() : 0;
    }

    public long getEstimatedBalance() {
        return (wallet != null) ? wallet.getBalance(Wallet.BalanceType.ESTIMATED).longValue() : 0;
    }


    /* --- Reading transaction data --- */

    private String getJSONFromTransaction(Transaction tx) throws ScriptException, JSONException {
        if (tx == null) {
            return null;
        }

        JSONArray conns = new JSONArray();

        int connCount = 0;

        TransactionConfidence.ConfidenceType confidenceType = tx.getConfidence().getConfidenceType();
        String confidence;

        if (confidenceType == TransactionConfidence.ConfidenceType.BUILDING) {
            confidence = "building";
        } else if (confidenceType == TransactionConfidence.ConfidenceType.PENDING) {
            confidence = "pending";
        } else if (confidenceType == TransactionConfidence.ConfidenceType.DEAD) {
            confidence = "dead";
        } else {
            confidence = "unknown";
        }

        if (tx.getInputs().size() > 0 && tx.getValue(wallet).compareTo(BigInteger.ZERO) > 0) {
            TransactionInput in = tx.getInput(0);

            JSONObject transaction = new JSONObject();
            transaction.put("category", "received");

            conns.put(transaction);
            connCount++;
        }

        if (tx.getOutputs().size() > 0 && tx.getValue(wallet).compareTo(BigInteger.ZERO) < 0) {
            TransactionOutput out = tx.getOutput(0);

            try {
                JSONObject transaction = new JSONObject();

                Script scriptPubKey = out.getScriptPubKey();

                try {
                    Address toAddress = scriptPubKey.getToAddress(networkParams);
                    transaction.put("address", toAddress);
                } catch (ScriptException e) {
                    // non-standard target, there's no address or we can't figure it out
                }

                transaction.put("category", "sent");

                conns.put(transaction);
                connCount++;
            } catch (Exception e) {

            }
        }

        SimpleDateFormat dateFormat = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss z");
        dateFormat.setTimeZone(TimeZone.getTimeZone("GMT"));

        JSONObject result = new JSONObject();
        result.put("amount", tx.getValue(wallet));
        result.put("fee", getTransactionFee(tx));
        result.put("txid", tx.getHashAsString());
        result.put("time", dateFormat.format(tx.getUpdateTime()));
        result.put("confidence", confidence);
        result.put("details", conns);

        return result.toString();
    }

    public BigInteger getTransactionFee(Transaction tx) {
        // TODO: this will break once we do more complex transactions with multiple sources/targets (e.g. coinjoin)

        BigInteger v = BigInteger.ZERO;

        for (TransactionInput input : tx.getInputs()) {
            TransactionOutput connected = input.getConnectedOutput();
            if (connected != null) {
                v = v.add(connected.getValue());
            } else {
                // we can't calculate the fee amount without having all data
                return BigInteger.ZERO;
            }
        }

        for (TransactionOutput output : tx.getOutputs()) {
            v = v.subtract(output.getValue());
        }

        return v;
    }

    public int getTransactionCount() {
        return wallet.getTransactionsByTime().size();
    }

    public String getAllTransactions() throws ScriptException, JSONException {
        return getTransactions(0, getTransactionCount());
    }

    public String getTransaction(String tx) throws ScriptException, JSONException {
        Sha256Hash hash = new Sha256Hash(tx);
        return getJSONFromTransaction(wallet.getTransaction(hash));
    }

    public String getTransaction(int idx) throws ScriptException, JSONException {
        return getJSONFromTransaction(wallet.getTransactionsByTime().get(idx));
    }

    public String getTransactions(int from, int count) throws ScriptException, JSONException {
        List<Transaction> transactions = wallet.getTransactionsByTime();

        if (from >= transactions.size())
            return null;

        int to = (from + count < transactions.size()) ? from + count : transactions.size();

        StringBuffer txs = new StringBuffer();
        txs.append("[\n");
        boolean first = true;
        for (; from < to; from++) {
            if (first)
                first = false;
            else
                txs.append("\n,");

            txs.append(getJSONFromTransaction(transactions.get(from)));
        }
        txs.append("]\n");

        return txs.toString();
    }


    /* --- Sending transactions --- */

    public String feeForSendingCoins(String amount, String sendToAddressString) throws InsufficientMoneyException {
        try {
            BigInteger amountToSend = new BigInteger(amount);
            if (amountToSend.intValue() == 0 || sendToAddressString.equals("")) {
                // assume default value for now
                return Transaction.REFERENCE_DEFAULT_MIN_TX_FEE.toString();
            }

            Address sendToAddress = new Address(networkParams, sendToAddressString);
            Wallet.SendRequest request = Wallet.SendRequest.to(sendToAddress, amountToSend);

            try {
                wallet.completeTx(request);
            } catch (KeyCrypterException e) {
                // that's ok, we aren't sending this yet
            }

            return getTransactionFee(request.tx).toString();
        } catch (AddressFormatException e) {
            // assume default value for now
            return Transaction.REFERENCE_DEFAULT_MIN_TX_FEE.toString();
        }
    }

    public boolean isAddressValid(String address) {
        try {
            Address addr = new Address(networkParams, address);
            return (addr != null);
        } catch (Exception e) {
            return false;
        }
    }

    public void sendCoins(String amount, final String sendToAddressString)
            throws WrongPasswordException, SendingDustException, AddressFormatException, InsufficientMoneyException {
        sendCoins(amount, sendToAddressString, null);
    }

    public void sendCoins(String amount, final String sendToAddressString, char[] utf16Password)
            throws WrongPasswordException, SendingDustException, AddressFormatException, InsufficientMoneyException {
        KeyParameter aesKey = null;
        try {
            BigInteger aToSend = new BigInteger(amount);
            Address sendToAddress = new Address(networkParams, sendToAddressString);
            final Wallet.SendRequest request = Wallet.SendRequest.to(sendToAddress, aToSend);

            if (isDust(request)) {
                throw new SendingDustException("Can't send dust amount: " + amount);
            }

            if (utf16Password != null) {
                aesKey = aesKeyForPassword(utf16Password);
                request.aesKey = aesKey;
            }

            final Wallet.SendResult sendResult = wallet.sendCoins(peerGroup, request);
            Futures.addCallback(sendResult.broadcastComplete, new FutureCallback<Transaction>() {
                public void onSuccess(Transaction transaction) {
                    onTransactionSuccess(sendResult.tx.getHashAsString());
                }

                public void onFailure(Throwable throwable) {
                    onTransactionFailed();
                    throwable.printStackTrace();
                }
            });
        } catch (KeyCrypterException e) {
            throw new WrongPasswordException(e);
        } finally {
            wipeAesKey(aesKey);
        }
    }

    private boolean isDust(Wallet.SendRequest req) {
        for (TransactionOutput output : req.tx.getOutputs()) {
            if (output.getValue().compareTo(Utils.CENT) < 0) {
                return output.getValue().compareTo(output.getMinNonDustValue()) < 0;
            }
        }
        return false;
    }


    /* --- Handling payment requests --- */

    public void openPaymentRequestFromFile(String path, int callbackId) throws IOException {
        File requestFile = new File(path);
        FileInputStream stream = new FileInputStream(requestFile);

        try {
            org.bitcoin.protocols.payments.Protos.PaymentRequest paymentRequest =
                org.bitcoin.protocols.payments.Protos.PaymentRequest.parseFrom(stream);

            PaymentSession session = new PaymentSession(paymentRequest, false);

            validatePaymentRequest(session);

            int sessionId = ++paymentSessionsSequenceId;
            paymentSessions.put(sessionId, session);
            onPaymentRequestLoaded(callbackId, sessionId, getPaymentRequestDetails(session));
        } catch (com.google.protobuf.InvalidProtocolBufferException e) {
            onPaymentRequestLoadFailed(callbackId, e);
        } catch (JSONException e) {
            // this should never happen
            onPaymentRequestLoadFailed(callbackId, e);
        } catch (PaymentRequestException e) {
            onPaymentRequestLoadFailed(callbackId, e);
        }
    }

    public void openPaymentRequestFromURL(String url, final int callbackId) throws PaymentRequestException {
        ListenableFuture<PaymentSession> future = PaymentSession.createFromUrl(url, false);

        Futures.addCallback(future, new FutureCallback<PaymentSession>() {
            public void onSuccess(PaymentSession session) {
                try {
                    validatePaymentRequest(session);

                    int sessionId = ++paymentSessionsSequenceId;
                    paymentSessions.put(sessionId, session);
                    onPaymentRequestLoaded(callbackId, sessionId, getPaymentRequestDetails(session));
                } catch (Exception e) {
                    onPaymentRequestLoadFailed(callbackId, e);
                }
            }

            public void onFailure(Throwable throwable) {
                onPaymentRequestLoadFailed(callbackId, throwable);
            }
        });
    }

    private void validatePaymentRequest(PaymentSession session) throws PaymentRequestException {
        org.bitcoin.protocols.payments.Protos.PaymentDetails paymentDetails = session.getPaymentDetails();

        // this should really be done in bitcoinj (see https://code.google.com/p/bitcoinj/issues/detail?id=551)
        NetworkParameters params;

        if (paymentDetails.hasNetwork()) {
            params = NetworkParameters.fromPmtProtocolID(paymentDetails.getNetwork());
        } else {
            params = MainNetParams.get();
        }

        if (params != networkParams) {
            throw new WrongNetworkException("This payment request is meant for a different Bitcoin network");
        }

        if (session.isExpired()) {
            throw new PaymentRequestException.Expired("PaymentRequest is expired");
        }

        try {
            session.verifyPki();
        } catch (PaymentRequestException e) {
            // apparently we're supposed to just ignore these errors (?)
            log.warn("PKI Verification error: " + e);
        }
    }

    private String getPaymentRequestDetails(PaymentSession session) throws JSONException {
        JSONObject request = new JSONObject();

        request.put("amount", session.getValue());
        request.put("memo", session.getMemo());
        request.put("paymentURL", session.getPaymentUrl());

        if (session.pkiVerificationData != null) {
            request.put("pkiName", session.pkiVerificationData.name);
            request.put("pkiRootAuthorityName", session.pkiVerificationData.rootAuthorityName);
        }

        return request.toString();
    }

    public void sendPaymentRequest(final int sessionId, char[] utf16Password, final int callbackId)
        throws WrongPasswordException, InsufficientMoneyException, PaymentRequestException, IOException,
               SendingDustException {
        KeyParameter aesKey = null;

        try {
            PaymentSession session = paymentSessions.get(sessionId);
            final Wallet.SendRequest request = session.getSendRequest();

            if (isDust(request)) {
                throw new SendingDustException("Can't send dust amount");
            }

            if (utf16Password != null) {
                aesKey = aesKeyForPassword(utf16Password);
                request.aesKey = aesKey;
            }

            wallet.completeTx(request);

            ListenableFuture<PaymentSession.Ack> fack = session.sendPayment(ImmutableList.of(request.tx), null, null);

            if (fack != null) {
                Futures.addCallback(fack, new FutureCallback<PaymentSession.Ack>() {
                    public void onSuccess(PaymentSession.Ack ack) {
                        try {
                            wallet.commitTx(request.tx);
                            paymentSessions.remove(sessionId);
                            onPaymentRequestProcessed(callbackId, getPaymentRequestAckDetails(ack));
                        } catch (JSONException e) {
                            onPaymentRequestProcessingFailed(callbackId, e);
                        }
                    }

                    public void onFailure(Throwable throwable) {
                        onPaymentRequestProcessingFailed(callbackId, throwable);
                    }
                });
            } else {
                // no payment_url - we just need to broadcast the transaction as with a normal send

                wallet.commitTx(request.tx);
                ListenableFuture<Transaction> broadcastComplete = peerGroup.broadcastTransaction(request.tx);

                Futures.addCallback(broadcastComplete, new FutureCallback<Transaction>() {
                    public void onSuccess(Transaction transaction) {
                        paymentSessions.remove(sessionId);
                        onPaymentRequestProcessed(callbackId, "{}");
                    }

                    public void onFailure(Throwable throwable) {
                        onPaymentRequestProcessingFailed(callbackId, throwable);
                    }
                });
            }
        } catch (KeyCrypterException e) {
            throw new WrongPasswordException(e);
        } finally {
            wipeAesKey(aesKey);
        }
    }

    private String getPaymentRequestAckDetails(PaymentSession.Ack ack) throws JSONException {
        JSONObject json = new JSONObject();
        json.put("memo", ack.getMemo());
        return json.toString();
    }


    /* --- Encryption/decryption --- */

    private KeyParameter aesKeyForPassword(char[] utf16Password) throws WrongPasswordException {
        KeyCrypter keyCrypter = wallet.getKeyCrypter();
        if (keyCrypter == null) {
            throw new WrongPasswordException("Wallet is not protected.");
        }
        return deriveKeyAndWipePassword(utf16Password, keyCrypter);
    }

    private KeyParameter deriveKeyAndWipePassword(char[] utf16Password, KeyCrypter keyCrypter) {
        try {
            return keyCrypter.deriveKey(CharBuffer.wrap(utf16Password));
        } finally {
            Arrays.fill(utf16Password, '\0');
        }
    }

    private void wipeAesKey(KeyParameter aesKey) {
        if (aesKey != null) {
            Arrays.fill(aesKey.getKey(), (byte) 0);
        }
    }

    public boolean isWalletEncrypted() {
        return wallet.getKeys().get(0).isEncrypted();
    }

    public boolean isPasswordCorrect(char[] password) {
        KeyParameter aesKey = null;

        try {
            aesKey = aesKeyForPassword(password);
            return wallet.checkAESKey(aesKey);
        } catch (WrongPasswordException e) {
            return false;
        } finally {
            wipeAesKey(aesKey);
        }
    }

    public void changeWalletPassword(char[] oldUtf16Password, char[] newUtf16Password) throws WrongPasswordException {
        updateLastWalletChange(wallet);

        if (isWalletEncrypted()) {
            decryptWallet(oldUtf16Password);
        }

        encryptWallet(newUtf16Password, wallet);
    }

    private void decryptWallet(char[] oldUtf16Password) throws WrongPasswordException {
        KeyParameter oldAesKey = aesKeyForPassword(oldUtf16Password);
        try {
            wallet.decrypt(oldAesKey);
        } catch (KeyCrypterException e) {
            throw new WrongPasswordException(e);
        } finally {
            wipeAesKey(oldAesKey);
        }
    }

    private void encryptWallet(char[] utf16Password, Wallet wallet) {
        KeyCrypterScrypt keyCrypter = new KeyCrypterScrypt();
        KeyParameter aesKey = deriveKeyAndWipePassword(utf16Password, keyCrypter);
        try {
            wallet.encrypt(keyCrypter, aesKey);
        } finally {
            wipeAesKey(aesKey);
        }
    }

    public String signMessage(String message, char[] utf16Password) throws WrongPasswordException {
        KeyParameter aesKey = null;
        ECKey decryptedKey = null;

        try {
            ECKey ecKey = wallet.getKeys().get(0);

            if (utf16Password != null) {
                aesKey = aesKeyForPassword(utf16Password);
                decryptedKey = ecKey.decrypt(wallet.getKeyCrypter(), aesKey);
                return decryptedKey.signMessage(message);
            } else {
                return ecKey.signMessage(message);
            }
        } catch (KeyCrypterException e) {
            throw new WrongPasswordException(e);
        } finally {
            wipeAesKey(aesKey);

            if (decryptedKey != null) {
                decryptedKey.clearPrivateKey();
            }
        }
    }


    /* --- Handling exceptions --- */

    public String getExceptionStackTrace(Throwable exception) {
        StringBuilder buffer = new StringBuilder();

        for (StackTraceElement line : exception.getStackTrace()) {
            buffer.append("at " + line.toString() + "\n");
        }

        return buffer.toString();
    }


    /* --- Keeping last wallet change date --- */

    public void updateLastWalletChange(Wallet wallet) {
        LastWalletChangeExtension ext =
                (LastWalletChangeExtension) wallet.getExtensions().get(LastWalletChangeExtension.EXTENSION_ID);

        ext.setLastWalletChangeDate(new Date());
    }

    public Date getLastWalletChange() {
        if (wallet == null) {
            return null;
        }

        LastWalletChangeExtension ext =
                (LastWalletChangeExtension) wallet.getExtensions().get(LastWalletChangeExtension.EXTENSION_ID);

        return ext.getLastWalletChangeDate();
    }

    public long getLastWalletChangeTimestamp() {
        Date date = getLastWalletChange();
        return (date != null) ? date.getTime() : 0;
    }


    /* --- WalletEventListener --- */

    public void onCoinsReceived(Wallet w, Transaction tx, BigInteger prevBalance, BigInteger newBalance) {
        onNewTransaction(tx);
    }

    public void onCoinsSent(Wallet w, Transaction tx, BigInteger prevBalance, BigInteger newBalance) {
        onNewTransaction(tx);
    }

    private void onNewTransaction(Transaction tx) {
        // avoid double updates if we get both sent + received
        if (!trackedTransactions.contains(tx)) {
            // update the UI
            onBalanceChanged();
            onTransactionChanged(tx.getHashAsString());

            // get notified when transaction is confirmed
            if (tx.isPending()) {
                trackTransaction(tx);
            }
        }
    }


    /* --- TransactionConfidence.Listener --- */

    public void onConfidenceChanged(final Transaction tx, TransactionConfidence.Listener.ChangeReason reason) {
        if (!tx.isPending()) {
            // coins were confirmed (appeared in a block) - we don't need to listen anymore
            stopTrackingTransaction(tx);
        }

        // update the UI
        onBalanceChanged();
        onTransactionChanged(tx.getHashAsString());
    }


    /* --- Thread.UncaughtExceptionHandler --- */

    public void uncaughtException(Thread thread, Throwable exception) {
        onException(exception);
    }


    /* PeerEventListener */

    public void onPeerConnected(Peer peer, int peerCount) {
        onPeerCountChanged(peerCount);
    }

    public void onPeerDisconnected(Peer peer, int peerCount) {
        onPeerCountChanged(peerCount);
    }

    public void onBlocksDownloaded(Peer peer, Block block, int blocksLeft) {
        updateBlocksLeft(blocksLeft);
    }

    public void onChainDownloadStarted(Peer peer, int blocksLeft) {
        if (blocksToDownload == 0) {
            // remember the total amount
            blocksToDownload = blocksLeft;
            log.debug("Starting blockchain sync: blocksToDownload := " + blocksLeft);
        } else {
            // we've already set that once and we're only downloading the remaining part
            log.debug("Restarting blockchain sync: blocksToDownload = " + blocksToDownload + ", left = " + blocksLeft);
        }

        updateBlocksLeft(blocksLeft);
    }

    private void updateBlocksLeft(int blocksLeft) {
        if (blocksToDownload == 0) {
            log.debug("Blockchain sync finished.");
            onSynchronizationUpdate(100.0f);
        } else {
            int downloadedSoFar = blocksToDownload - blocksLeft;
            onSynchronizationUpdate(100.0f * downloadedSoFar / blocksToDownload);
        }
    }


	/* Native callbacks to pass data to the Cocoa side when something happens */

    public native void onTransactionChanged(String txid);

    public native void onTransactionFailed();

    public native void onTransactionSuccess(String txid);

    public native void onSynchronizationUpdate(float percent);

    public native void onBalanceChanged();

    public native void onPeerCountChanged(int peerCount);

    public native void onException(Throwable exception);

    public native void onPaymentRequestLoaded(int callbackId, int sessionId, String requestDetails);
    public native void onPaymentRequestLoadFailed(int callbackId, Throwable error);

    public native void onPaymentRequestProcessed(int callbackId, String ackDetails);
    public native void onPaymentRequestProcessingFailed(int callbackId, Throwable error);
}
