package com.hive.bitcoinkit;

import com.google.bitcoin.core.*;
import com.google.bitcoin.crypto.KeyCrypter;
import com.google.bitcoin.crypto.KeyCrypterException;
import com.google.bitcoin.crypto.KeyCrypterScrypt;
import com.google.bitcoin.net.discovery.DnsDiscovery;
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
import java.util.HashSet;
import java.util.List;
import java.util.TimeZone;
import java.util.concurrent.TimeUnit;

public class BitcoinManager implements Thread.UncaughtExceptionHandler, TransactionConfidence.Listener
{
    private NetworkParameters networkParams;
    private Wallet wallet;
    private String dataDirectory;

    private PeerGroup peerGroup;
    private BlockStore blockStore;
    private File walletFile;
    private int blocksToDownload;
    private HashSet<Transaction> trackedTransactions;

    private static final Logger log = LoggerFactory.getLogger(BitcoinManager.class);


    /* --- Initialization & configuration --- */

    public BitcoinManager()
    {
        Threading.uncaughtExceptionHandler = this;

        trackedTransactions = new HashSet<Transaction>();

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

        wallet.addEventListener(new AbstractWalletEventListener()
        {
            // get notified when an incoming transaction is received
            @Override
            public void onCoinsReceived(Wallet w, Transaction tx, BigInteger prevBalance, BigInteger newBalance)
            {
                BitcoinManager.this.onCoinsReceived(w, tx, prevBalance, newBalance);
            }

            // get notified when we send a transaction, or when we restore an outgoing transaction from the blockchain
            @Override
            public void onCoinsSent(Wallet w, Transaction tx, BigInteger prevBalance, BigInteger newBalance)
            {
                BitcoinManager.this.onCoinsSent(w, tx, prevBalance, newBalance);
            }
        });

        startBlockchain();
    }
    
    public String addAddress()
    {
        ECKey newKey = new ECKey();
        boolean couldCreateKey = wallet.addKey(newKey);
        if(couldCreateKey)
        {
            return newKey.toAddress(networkParams).toString();
        }
        return null;
    }

    private File getBlockchainFile()
    {
        return new File(dataDirectory + "/bitcoinkit.spvchain");
    }

    private void startBlockchain() throws BlockStoreException
    {
        // Load the block chain data file or generate a new one
        File chainFile = getBlockchainFile();
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

        onBalanceChanged();
        trackPendingTransactions(wallet);

        peerGroup.startAndWait();

        // get notified about sync progress
        peerGroup.startBlockChainDownload(new AbstractPeerEventListener()
        {
            @Override
            public void onBlocksDownloaded(Peer peer, Block block, int blocksLeft)
            {
                BitcoinManager.this.onBlocksDownloaded(peer, block, blocksLeft);
            }

            @Override
            public void onChainDownloadStarted(Peer peer, int blocksLeft)
            {
                BitcoinManager.this.onChainDownloadStarted(peer, blocksLeft);
            }
        });
    }

    private void trackPendingTransactions(Wallet wallet)
    {
        // we won't receive onCoinsReceived again for transactions that we already know about,
        // so we need to listen to confidence changes again after a restart
        for (Transaction tx : wallet.getPendingTransactions())
        {
            trackTransaction(tx);
        }
    }

    private void trackTransaction(Transaction tx)
    {
        if (!trackedTransactions.contains(tx))
        {
            log.debug("Tracking transaction " + tx.getHashAsString());

            tx.getConfidence().addEventListener(this);
            trackedTransactions.add(tx);
        }
    }

    private void stopTrackingTransaction(Transaction tx)
    {
        if (trackedTransactions.contains(tx))
        {
            log.debug("Stopped tracking transaction " + tx.getHashAsString());

            tx.getConfidence().removeEventListener(this);
            trackedTransactions.remove(tx);
        }
    }

    public void resetBlockchain()
    {
        try
        {
            shutdownBlockchain();

            log.info("Deleting blockchain data file...");
            File chainFile = getBlockchainFile();
            chainFile.delete();

            blocksToDownload = 0;

            for (Transaction tx : (HashSet<Transaction>) trackedTransactions.clone())
            {
                stopTrackingTransaction(tx);
            }

            startBlockchain();
        }
        catch (Exception e)
        {
            throw new RuntimeException(e);
        }
    }

    public void stop()
    {
        try
        {
            log.info("Shutting down BitcoinManager...");

            shutdownBlockchain();

            if (wallet != null)
            {
                wallet.saveToFile(walletFile);
            }

            log.info("Shutdown done.");
        }
        catch (Exception e)
        {
            throw new RuntimeException(e);
        }
    }

    private void shutdownBlockchain() throws BlockStoreException
    {
        log.info("Shutting down PeerGroup...");

        if (peerGroup != null)
        {
            peerGroup.stopAndWait();
            peerGroup.removeWallet(wallet);
            peerGroup = null;
        }

        log.info("Shutting down BlockStore...");

        if (blockStore != null)
        {
            blockStore.close();
            blockStore = null;
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
    
    public String getAllWalletAddresses()
    {
        StringBuffer conns = new StringBuffer();
        conns.append("[");
        for(ECKey key: wallet.getKeys())
        {
            conns.append("\"" + key.toAddress(networkParams).toString() + "\",");
        }
        if(conns.substring(conns.length() -1).equals(","))
        {
            conns.deleteCharAt(conns.length() -1);
        }
        conns.append("]");
        return conns.toString();
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
                ", \"fee\": " + getTransactionFee(tx) +
                ", \"txid\": \"" + tx.getHashAsString() + "\"" +
                ", \"time\": \"" + dateFormat.format(tx.getUpdateTime()) + "\"" +
                ", \"confidence\": \"" + confidence + "\"" +
                ", \"details\": " + conns.toString() +
                "}";
    }

    public BigInteger getTransactionFee(Transaction tx)
    {
        // TODO: this will break once we do more complex transactions with multiple sources/targets (e.g. coinjoin)

        BigInteger v = BigInteger.ZERO;

        for (TransactionInput input : tx.getInputs())
        {
            TransactionOutput connected = input.getConnectedOutput();
            if (connected != null)
            {
                v = v.add(connected.getValue());
            }
            else
            {
                // we can't calculate the fee amount without having all data
                return BigInteger.ZERO;
            }
        }

        for (TransactionOutput output : tx.getOutputs())
        {
            v = v.subtract(output.getValue());
        }

        return v;
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
        if(wallet != null)
        {
            return wallet.isEncrypted();
        }
        return false;
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
        if (wallet == null)
        {
            return null;
        }

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
        onNewTransaction(tx);
    }

    public void onCoinsSent(Wallet w, Transaction tx, BigInteger prevBalance, BigInteger newBalance)
    {
        onNewTransaction(tx);
    }

    private void onNewTransaction(Transaction tx)
    {
        // avoid double updates if we get both sent + received
        if (!trackedTransactions.contains(tx))
        {
            // update the UI
            onTransactionChanged(tx.getHashAsString());

            // get notified when transaction is confirmed
            if (tx.isPending())
            {
                trackTransaction(tx);
            }
        }
    }


    /* --- TransactionConfidence.Listener --- */

    public void onConfidenceChanged(final Transaction tx, TransactionConfidence.Listener.ChangeReason reason)
    {
        if (!tx.isPending())
        {
            // coins were confirmed (appeared in a block) - we don't need to listen anymore
            stopTrackingTransaction(tx);
        }

        // update the UI
        onTransactionChanged(tx.getHashAsString());
    }


    /* --- Thread.UncaughtExceptionHandler --- */

    public void uncaughtException(Thread thread, Throwable exception)
    {
        onException(exception);
    }


	/* PeerEventListener */

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
            log.debug("Starting blockchain sync: blocksToDownload := " + blocksLeft);
        }
        else
        {
            // we've already set that once and we're only downloading the remaining part
            log.debug("Restarting blockchain sync: blocksToDownload = " + blocksToDownload + ", left = " + blocksLeft);
        }

        updateBlocksLeft(blocksLeft);
    }

    private void updateBlocksLeft(int blocksLeft)
    {
        if (blocksToDownload == 0)
        {
            log.debug("Blockchain sync finished.");
            onSynchronizationUpdate(100.0f);
        }
        else
        {
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

    public native void onException(Throwable exception);
}
