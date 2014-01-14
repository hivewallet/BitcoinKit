package com.hive.bitcoinkit;

import com.google.bitcoin.core.*;
import com.google.bitcoin.crypto.KeyCrypter;
import com.google.bitcoin.crypto.KeyCrypterException;
import com.google.bitcoin.crypto.KeyCrypterScrypt;
import com.google.bitcoin.discovery.DnsDiscovery;
import com.google.bitcoin.params.MainNetParams;
import com.google.bitcoin.params.RegTestParams;
import com.google.bitcoin.params.TestNet3Params;
import com.google.bitcoin.script.Script;
import com.google.bitcoin.store.BlockStore;
import com.google.bitcoin.store.BlockStoreException;
import com.google.bitcoin.store.SPVBlockStore;
import com.google.bitcoin.store.UnreadableWalletException;
import com.google.bitcoin.store.WalletProtobufSerializer;
import com.google.bitcoin.utils.Threading;
import com.google.common.util.concurrent.FutureCallback;
import com.google.common.util.concurrent.Futures;
import org.bitcoinj.wallet.Protos;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.impl.CocoaLogger;
import org.spongycastle.crypto.params.KeyParameter;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.math.BigInteger;
import java.net.InetAddress;
import java.nio.CharBuffer;
import java.text.SimpleDateFormat;
import java.util.Arrays;
import java.util.Date;
import java.util.List;
import java.util.TimeZone;
import java.util.concurrent.TimeUnit;

public class BitcoinManager
    implements PeerEventListener, Thread.UncaughtExceptionHandler, TransactionConfidence.Listener
{
    private NetworkParameters networkParams;
    private Wallet wallet;
    private String dataDirectory;

    private PeerGroup peerGroup;
    private BlockStore blockStore;
    private File walletFile;
    private int blocksToDownload;

    private static final Logger log = LoggerFactory.getLogger(BitcoinManager.class);


    /* --- Initialization & configuration --- */

    public BitcoinManager()
    {
        Threading.uncaughtExceptionHandler = this;

        ((CocoaLogger) log).setLevel(CocoaLogger.HILoggerLevelDebug);
    }

    public void setTestingNetwork(boolean testing)
    {
        if (testing)
        {
            this.networkParams = TestNet3Params.get();
        }
        else
        {
            this.networkParams = MainNetParams.get();
        }
    }

    public void setDataDirectory(String path)
    {
        dataDirectory = path;
    }


    /* --- Wallet lifecycle --- */

    public void start() throws NoWalletException, UnreadableWalletException, IOException, BlockStoreException
    {
        if (networkParams == null)
        {
            setTestingNetwork(false);
        }

        // Try to read the wallet from storage, create a new one if not possible.
        wallet = null;
        walletFile = new File(dataDirectory + "/bitcoinkit.wallet");

        if (!walletFile.exists())
        {
            // Stop here, because the caller might want to create an encrypted wallet and needs to supply a password.
            throw new NoWalletException("No wallet file found at: " + walletFile);
        }

        try
        {
            useWallet(loadWalletFromFile(walletFile));
        }
        catch (FileNotFoundException e)
        {
            throw new NoWalletException("No wallet file found at: " + walletFile);
        }
    }

    public void addExtensionsToWallet(Wallet wallet)
    {
        wallet.addExtension(new LastWalletChangeExtension());
    }

    public Wallet loadWalletFromFile(File f) throws UnreadableWalletException
    {
        try
        {
            FileInputStream stream = null;

            try
            {
                stream = new FileInputStream(f);

                Wallet wallet = new Wallet(networkParams);
                addExtensionsToWallet(wallet);

                Protos.Wallet walletData = WalletProtobufSerializer.parseToProto(stream);
                new WalletProtobufSerializer().readWallet(walletData, wallet);

                if (!wallet.isConsistent())
                {
                    log.error("Loaded an inconsistent wallet");
                }

                return wallet;
            }
            finally
            {
                if (stream != null)
                {
                    stream.close();
                }
            }
        }
        catch (IOException e)
        {
            throw new UnreadableWalletException("Could not open file", e);
        }
    }

    public void createWallet() throws IOException, BlockStoreException, ExistingWalletException
    {
        createWallet(null);
    }

    public void createWallet(char[] utf16Password) throws IOException, BlockStoreException, ExistingWalletException
    {
        if (walletFile == null)
        {
            throw new IllegalStateException("createWallet cannot be called before start");
        }
        else if (walletFile.exists())
        {
            throw new ExistingWalletException("Trying to create a wallet even though one exists: " + walletFile);
        }

        Wallet wallet = new Wallet(networkParams);
        addExtensionsToWallet(wallet);
        updateLastWalletChange(wallet);
        wallet.addKey(new ECKey());

        if (utf16Password != null)
        {
            encryptWallet(utf16Password, wallet);
        }

        wallet.saveToFile(walletFile);

        useWallet(wallet);
    }

    private void useWallet(Wallet wallet) throws BlockStoreException, IOException
    {
        this.wallet = wallet;

        //make wallet autosave
        wallet.autosaveToFile(walletFile, 1, TimeUnit.SECONDS, null);

        // Fetch the first key in the wallet (should be the only key).
        ECKey key = wallet.getKeys().iterator().next();

        // Load the block chain data file or generate a new one
        File chainFile = new File(dataDirectory + "/bitcoinkit.spvchain");
        boolean chainExistedAlready = chainFile.exists();
        blockStore = new SPVBlockStore(networkParams, chainFile);

        if (!chainExistedAlready)
        {
            // the blockchain will need to be replayed; if the wallet already contains transactions, this might
            // cause ugly inconsistent wallet exceptions, so clear all old transaction data first
            log.info("Chain file missing - wallet transactions list will be rebuilt now");
            wallet.clearTransactions(0);
        }

        BlockChain chain = new BlockChain(networkParams, wallet, blockStore);

        peerGroup = new PeerGroup(networkParams, chain);
        peerGroup.setUserAgent("BitcoinJKit", "0.9");
        peerGroup.addPeerDiscovery(new DnsDiscovery(networkParams));
        peerGroup.addWallet(wallet);

        // get notified when an incoming transaction is received
        wallet.addEventListener(new AbstractWalletEventListener()
        {
            @Override
            public void onCoinsReceived(Wallet w, Transaction tx, BigInteger prevBalance, BigInteger newBalance)
            {
                BitcoinManager.this.onCoinsReceived(w, tx, prevBalance, newBalance);
            }
        });

        peerGroup.startAndWait();

        onBalanceChanged();

        peerGroup.startBlockChainDownload(this);
    }

    public void stop()
    {
        try
        {
            System.out.print("Shutting down ... ");

            if (peerGroup != null)
            {
                peerGroup.stopAndWait();
            }

            if (wallet != null)
            {
                wallet.saveToFile(walletFile);
            }

            if (blockStore != null)
            {
                blockStore.close();
            }

            System.out.print("done ");
        }
        catch (Exception e)
        {
            throw new RuntimeException(e);
        }
    }

    public void exportWallet(String path) throws java.io.IOException
    {
        File backupFile = new File(path);
        wallet.saveToFile(backupFile);
    }


    /* --- Reading wallet data --- */

    public String getWalletAddress()
    {
        ECKey ecKey = wallet.getKeys().get(0);
        return ecKey.toAddress(networkParams).toString();
    }

    public String getWalletDebuggingInfo()
    {
        return (wallet != null) ? wallet.toString() : null;
    }

    public long getAvailableBalance()
    {
        return (wallet != null) ? wallet.getBalance().longValue() : 0;
    }

    public long getEstimatedBalance()
    {
        return (wallet != null) ? wallet.getBalance(Wallet.BalanceType.ESTIMATED).longValue() : 0;
    }


    /* --- Reading transaction data --- */

    private String getJSONFromTransaction(Transaction tx) throws ScriptException
    {
        if (tx == null)
        {
            return null;
        }

        StringBuffer conns = new StringBuffer();
        int connCount = 0;

        TransactionConfidence.ConfidenceType confidenceType = tx.getConfidence().getConfidenceType();
        String confidence;

        if (confidenceType == TransactionConfidence.ConfidenceType.BUILDING)
        {
            confidence = "building";
        }
        else if (confidenceType == TransactionConfidence.ConfidenceType.PENDING)
        {
            confidence = "pending";
        }
        else if (confidenceType == TransactionConfidence.ConfidenceType.DEAD)
        {
            confidence = "dead";
        }
        else
        {
            confidence = "unknown";
        }

        conns.append("[");

        if (tx.getInputs().size() > 0 && tx.getValue(wallet).compareTo(BigInteger.ZERO) > 0)
        {
            TransactionInput in = tx.getInput(0);

            if (connCount > 0)
            {
                conns.append(", ");
            }

            conns.append("{ ");

            try
            {
                Script scriptSig = in.getScriptSig();

                if (scriptSig.getChunks().size() == 2)
                {
                    conns.append("\"address\": \"" + scriptSig.getFromAddress(networkParams).toString() + "\"");
                }

                conns.append(" ,\"category\": \"received\" }");

                connCount++;
            }
            catch (Exception e)
            {

            }
        }

        if (tx.getOutputs().size() > 0 && tx.getValue(wallet).compareTo(BigInteger.ZERO) < 0)
        {
            TransactionOutput out = tx.getOutput(0);

            if (connCount > 0)
            {
                conns.append(", ");
            }

            conns.append("{ ");

            try
            {
                Script scriptPubKey = out.getScriptPubKey();

                if (scriptPubKey.isSentToAddress())
                {
                    conns.append(" \"address\": \"" + scriptPubKey.getToAddress(networkParams).toString() + "\"");
                }

                conns.append(" ,\"category\": \"sent\" }");

                connCount++;
            }
            catch (Exception e)
            {

            }
        }

        conns.append("]");

        SimpleDateFormat dateFormat = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss z");
        dateFormat.setTimeZone(TimeZone.getTimeZone("GMT"));

        return "{ \"amount\": " + tx.getValue(wallet) +
                ", \"txid\": \"" + tx.getHashAsString() + "\"" +
                ", \"time\": \"" + dateFormat.format(tx.getUpdateTime()) + "\"" +
                ", \"confidence\": \"" + confidence + "\"" +
                ", \"details\": " + conns.toString() +
                "}";
    }

    public int getTransactionCount()
    {
        return wallet.getTransactionsByTime().size();
    }

    public String getAllTransactions() throws ScriptException
    {
        return getTransactions(0, getTransactionCount());
    }

    public String getTransaction(String tx) throws ScriptException
    {
        Sha256Hash hash = new Sha256Hash(tx);
        return getJSONFromTransaction(wallet.getTransaction(hash));
    }

    public String getTransaction(int idx) throws ScriptException
    {
        return getJSONFromTransaction(wallet.getTransactionsByTime().get(idx));
    }

    public String getTransactions(int from, int count) throws ScriptException
    {
        List<Transaction> transactions = wallet.getTransactionsByTime();

        if (from >= transactions.size())
            return null;

        int to = (from + count < transactions.size()) ? from + count : transactions.size();

        StringBuffer txs = new StringBuffer();
        txs.append("[\n");
        boolean first = true;
        for (; from < to; from++)
        {
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

    public String feeForSendingCoins(String amount) throws AddressFormatException
    {
        return Transaction.REFERENCE_DEFAULT_MIN_TX_FEE.toString();
    }

    public boolean isAddressValid(String address)
    {
        try
        {
            Address addr = new Address(networkParams, address);
            return (addr != null);
        }
        catch (Exception e)
        {
            return false;
        }
    }

    public void sendCoins(String amount, final String sendToAddressString) throws WrongPasswordException
    {
        sendCoins(amount, sendToAddressString, null);
    }

    public void sendCoins(String amount, final String sendToAddressString, char[] utf16Password)
            throws WrongPasswordException
    {
        KeyParameter aesKey = null;
        try
        {
            BigInteger aToSend = new BigInteger(amount);
            Address sendToAddress = new Address(networkParams, sendToAddressString);
            final Wallet.SendRequest request = Wallet.SendRequest.to(sendToAddress, aToSend);

            if (utf16Password != null)
            {
                aesKey = aesKeyForPassword(utf16Password);
                request.aesKey = aesKey;
            }

            final Wallet.SendResult sendResult = wallet.sendCoins(peerGroup, request);
            Futures.addCallback(sendResult.broadcastComplete, new FutureCallback<Transaction>()
            {
                public void onSuccess(Transaction transaction)
                {
                    wipeAesKey(request.aesKey);
                    onTransactionSuccess(sendResult.tx.getHashAsString());
                    onTransactionChanged(sendResult.tx.getHashAsString());
                }

                public void onFailure(Throwable throwable)
                {
                    wipeAesKey(request.aesKey);
                    onTransactionFailed();
                    throwable.printStackTrace();
                }
            });
        }
        catch (KeyCrypterException e)
        {
            wipeAesKey(aesKey);
            throw new WrongPasswordException(e);
        }
        catch (Exception e)
        {
            wipeAesKey(aesKey);
            onTransactionFailed();
        }
    }


    /* --- Encryption/decryption --- */

    private KeyParameter aesKeyForPassword(char[] utf16Password) throws WrongPasswordException
    {
        KeyCrypter keyCrypter = wallet.getKeyCrypter();
        if (keyCrypter == null)
        {
            throw new WrongPasswordException("Wallet is not protected.");
        }
        return deriveKeyAndWipePassword(utf16Password, keyCrypter);
    }

    private KeyParameter deriveKeyAndWipePassword(char[] utf16Password, KeyCrypter keyCrypter)
    {
        try
        {
            return keyCrypter.deriveKey(CharBuffer.wrap(utf16Password));
        }
        finally
        {
            Arrays.fill(utf16Password, '\0');
        }
    }

    private void wipeAesKey(KeyParameter aesKey)
    {
        if (aesKey != null)
        {
            Arrays.fill(aesKey.getKey(), (byte) 0);
        }
    }

    public boolean isWalletEncrypted()
    {
        return wallet.getKeys().get(0).isEncrypted();
    }

    public void changeWalletPassword(char[] oldUtf16Password, char[] newUtf16Password) throws WrongPasswordException
    {
        updateLastWalletChange(wallet);

        if (isWalletEncrypted())
        {
            decryptWallet(oldUtf16Password);
        }

        encryptWallet(newUtf16Password, wallet);
    }

    private void decryptWallet(char[] oldUtf16Password) throws WrongPasswordException
    {
        KeyParameter oldAesKey = aesKeyForPassword(oldUtf16Password);
        try
        {
            wallet.decrypt(oldAesKey);
        }
        catch (KeyCrypterException e)
        {
            throw new WrongPasswordException(e);
        }
        finally
        {
            wipeAesKey(oldAesKey);
        }
    }

    private void encryptWallet(char[] utf16Password, Wallet wallet)
    {
        KeyCrypterScrypt keyCrypter = new KeyCrypterScrypt();
        KeyParameter aesKey = deriveKeyAndWipePassword(utf16Password, keyCrypter);
        try
        {
            wallet.encrypt(keyCrypter, aesKey);
        }
        finally
        {
            wipeAesKey(aesKey);
        }
    }


    /* --- Handling exceptions --- */

    public String getExceptionStackTrace(Throwable exception)
    {
        StringBuilder buffer = new StringBuilder();

        for (StackTraceElement line : exception.getStackTrace())
        {
            buffer.append("at " + line.toString() + "\n");
        }

        return buffer.toString();
    }


    /* --- Keeping last wallet change date --- */

    public void updateLastWalletChange(Wallet wallet)
    {
        LastWalletChangeExtension ext =
            (LastWalletChangeExtension) wallet.getExtensions().get(LastWalletChangeExtension.EXTENSION_ID);

        ext.setLastWalletChangeDate(new Date());
    }

    public Date getLastWalletChange()
    {
        LastWalletChangeExtension ext =
            (LastWalletChangeExtension) wallet.getExtensions().get(LastWalletChangeExtension.EXTENSION_ID);

        return ext.getLastWalletChangeDate();
    }

    public long getLastWalletChangeTimestamp()
    {
        Date date = getLastWalletChange();
        return (date != null) ? date.getTime() : 0;
    }


    /* --- WalletEventListener --- */

    public void onCoinsReceived(Wallet w, Transaction tx, BigInteger prevBalance, BigInteger newBalance)
    {
        assert !newBalance.equals(BigInteger.ZERO);
        if (!tx.isPending()) return;

        // update the UI
        onTransactionChanged(tx.getHashAsString());

        // get notified when transaction is confirmed
        tx.getConfidence().addEventListener(this);
    }


    /* --- TransactionConfidence.Listener --- */

    public void onConfidenceChanged(final Transaction tx2, TransactionConfidence.Listener.ChangeReason reason)
    {
        if (tx2.getConfidence().getConfidenceType() == TransactionConfidence.ConfidenceType.BUILDING)
        {
            // coins were confirmed (appeared in a block) - we don't need to listen anymore
            tx2.getConfidence().removeEventListener(this);
        }

        // update the UI
        onTransactionChanged(tx2.getHashAsString());
    }


    /* --- Thread.UncaughtExceptionHandler --- */

    public void uncaughtException(Thread thread, Throwable exception)
    {
        onException(exception);
    }


	/* PeerEventListener */

    public void onPeerCountChange(int peersConnected)
    {
        //		System.out.println("Peers " + peersConnected);
    }

    public void onBlocksDownloaded(Peer peer, Block block, int blocksLeft)
    {
        updateBlocksLeft(blocksLeft);
    }

    public void onChainDownloadStarted(Peer peer, int blocksLeft)
    {
        if (blocksToDownload == 0)
        {
            // remember the total amount
            blocksToDownload = blocksLeft;
            log.debug("onChainDownloadStarted: blocksToDownload := " + blocksLeft);
        }
        else
        {
            // we've already set that once and we're only downloading the remaining part
            log.debug("onChainDownloadStarted: blocksToDownload = " + blocksToDownload + ", left = " + blocksLeft);
        }

        updateBlocksLeft(blocksLeft);
    }

    private void updateBlocksLeft(int blocksLeft)
    {
        if (blocksToDownload == 0)
        {
            onSynchronizationUpdate(100.0f);
        }
        else
        {
            int downloadedSoFar = blocksToDownload - blocksLeft;
            onSynchronizationUpdate(100.0f * downloadedSoFar / blocksToDownload);
        }
    }

    public void onPeerConnected(Peer peer, int peerCount)
    {
        onPeerCountChange(peerCount);
    }

    public void onPeerDisconnected(Peer peer, int peerCount)
    {
        onPeerCountChange(peerCount);
    }

    public Message onPreMessageReceived(Peer peer, Message m)
    {
        return m;
    }

    public void onTransaction(Peer peer, Transaction t)
    {

    }

    public List<Message> getData(Peer peer, GetDataMessage m)
    {
        return null;
    }


	/* Native callbacks to pass data to the Cocoa side when something happens */

    public native void onTransactionChanged(String txid);

    public native void onTransactionFailed();

    public native void onTransactionSuccess(String txid);

    public native void onSynchronizationUpdate(float percent);

    public native void onBalanceChanged();

    public native void onException(Throwable exception);
}
