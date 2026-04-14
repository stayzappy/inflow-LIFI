import { Buffer } from 'buffer';
if (typeof window !== 'undefined' && typeof window.Buffer === 'undefined') {
    window.Buffer = Buffer;
}

import Privy, { LocalStorage } from '@privy-io/js-sdk-core';
import { ethers } from 'ethers';
import { 
    getUserEmbeddedEthereumWallet, 
    getEntropyDetailsFromUser} from '@privy-io/js-sdk-core';

// ==============================================================
// 1. CONFIGURATION & STATE (FORCED MAINNET)
// ==============================================================
const PRIVY_APP_ID: string = "cmncyqtq601ft0cjsd04v9deb"; 
const INFLOW_CONTRACT: string = "0x265ad687db2a2e2B3b39a2C9C8b0861618B90bCC"; 
const RELAY_URL: string = "https://inflow-relay.zapstream.workers.dev"; 
const USDC_ADDRESS: string = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"; // MAINNET USDC ONLY

let privy: Privy;
let ethersProvider: ethers.BrowserProvider;
let signer: ethers.Signer;
let currentEmail: string = "";
let activeWallet: string | null = null; 

// 🔥 HARDCODED MAINNET VALUES
const currentNetwork: string = "mainnet";
const chainId: number = 8453; 

const ERC20_ABI = [
    "function approve(address spender, uint256 amount) returns (bool)",
    "function allowance(address owner, address spender) view returns (uint256)",
    "function balanceOf(address account) view returns (uint256)",
    "function decimals() view returns (uint8)",
    "function transfer(address recipient, uint256 amount) returns (bool)"
];

const INFLOW_ABI = [
    "function createStream(address recipient, address asset, uint256 deposit, uint256 startTime, uint256 stopTime, bytes32 claimHash) external returns (uint256)",
    "function claimStream(uint256 streamId, string calldata secret) external",
    "function withdrawFromStream(uint256 streamId, uint256 amount) external",
    "function cancelStream(uint256 streamId) external",
    "function nextStreamId() view returns (uint256)",
    "function streams(uint256) view returns (address sender, address recipient, address asset, uint256 deposit, uint256 ratePerSecond, uint256 startTime, uint256 stopTime, uint256 remainingBalance, uint256 withdrawnAmount, bytes32 claimHash)"
];

export async function initBridge(): Promise<boolean> {
    try {
        privy = new Privy({ appId: PRIVY_APP_ID, storage: new LocalStorage() });
        const iframeUrl = privy.embeddedWallet.getURL();
        
        const iframe = document.createElement('iframe');
        iframe.src = iframeUrl;
        iframe.style.display = 'none';
        document.body.appendChild(iframe);

        privy.setMessagePoster({
            postMessage: (message: any, targetOrigin: string, transfer?: Transferable[]) => {
                iframe.contentWindow?.postMessage(message, targetOrigin, transfer);
            },
            reload: () => iframe.src = iframeUrl
        } as any);

        window.addEventListener('message', (e) => {
            if (e.origin !== 'https://auth.privy.io') return;
            try { privy.embeddedWallet.onMessage(e.data); } catch (err) {}
        });

        return true;
    } catch (error) {
        console.error("Init Error:", error);
        throw error;
    }
}

export async function sendEmailOtp(email: string): Promise<boolean> {
    try {
        currentEmail = email;
        await privy.auth.email.sendCode(email);
        return true;
    } catch (error) {
        throw error;
    }
}

export async function verifyEmailOtpAndConnect(otp: string, networkIgnored: string): Promise<string> {
    let user: any;
    try {
        try {
            const result = await privy.auth.email.loginWithCode(currentEmail, otp);
            user = result.user;
        } catch (e: any) {
            if (e.message && e.message.includes("already has one email account linked")) {
                console.log("🧹 Stale session detected! Clearing cache and retrying...");
                await privy.auth.logout();
                const retryResult = await privy.auth.email.loginWithCode(currentEmail, otp);
                user = retryResult.user;
            } else {
                throw e; 
            }
        }

        let wallet = getUserEmbeddedEthereumWallet(user);
        let isNewWallet = false; 

        if (!wallet) {
            const createResult = await privy.embeddedWallet.create({}); 
            user = createResult.user; 
            wallet = getUserEmbeddedEthereumWallet(user);
            isNewWallet = true; 
        }

        if (!wallet) throw new Error("Could not initialize embedded wallet");

        const entropyDetails = getEntropyDetailsFromUser(user);
        if (!entropyDetails) throw new Error("Auth session invalid: No entropy found.");

        const provider = await privy.embeddedWallet.getEthereumProvider({
            wallet: wallet,
            entropyId: entropyDetails.entropyId,
            entropyIdVerifier: entropyDetails.entropyIdVerifier
        });

        try {
            await provider.request({
                method: 'wallet_switchEthereumChain',
                params: [{ chainId: `0x${chainId.toString(16)}` }],
            });
        } catch (switchError) {}

        ethersProvider = new ethers.BrowserProvider(provider as any);
        signer = await ethersProvider.getSigner();
        
        const address = await signer.getAddress();
        console.log("✅ Base/EVM Connected:", address);
        
        if (isNewWallet) {
            checkAndTriggerSponsorship(address, currentNetwork);
        }

        activeWallet = address; 
        return address;

    } catch (error: any) {
        console.error("❌ [Auth Error]", error);
        throw error;
    }
}

export async function logout(): Promise<boolean> {
    if (privy) await privy.auth.logout();
    signer = null as any;
    currentEmail = "";
    return true;
}

export async function storeStreamSecret(streamId: number, secretKey: string, recipientEmail: string, n: string): Promise<boolean> {
    const accessToken = await privy.getAccessToken();
    const res = await fetch(`${RELAY_URL}/store-secret`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${accessToken}` },
        body: JSON.stringify({ streamId, secretKey, recipientEmail })
    });
    if (!res.ok) throw new Error("Failed to store secret");
    return true;
}

export async function checkAndTriggerSponsorship(address: string, n: string): Promise<string> {
    try {
        console.log("🎁 [Sponsor] Requesting startup funds from Treasury...");
        const res = await fetch(`${RELAY_URL}/sponsor-new-user`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ address: address })
        });
        
        if (!res.ok) throw new Error("Sponsorship request failed");
        
        const data = await res.json();
        return JSON.stringify(data);
    } catch (e: any) { 
        return JSON.stringify({ success: false, error: e.message });
    }
}

export async function createYieldStream(tokenSymbol: string, amountStr: string, durationSecs: number, vaultTokenAddress: string): Promise<string> {
    try {
        if (!signer) throw new Error("Wallet not connected");
        const userAddress = await signer.getAddress();
        
        const randomBytes = new Uint8Array(31);
        crypto.getRandomValues(randomBytes);
        const secretKey = "0x" + Array.from(randomBytes).map(b => b.toString(16).padStart(2, '0')).join('');
        const claimHash = ethers.keccak256(ethers.toUtf8Bytes(secretKey));

        const amountWei = ethers.parseUnits(amountStr, 6).toString(); 

        let streamAsset = USDC_ADDRESS;
        let streamDepositAmount = amountWei;

        if (vaultTokenAddress && vaultTokenAddress !== USDC_ADDRESS) {
            const quoteRes = await fetch(`https://li.quest/v1/quote?fromChain=${chainId}&toChain=${chainId}&fromToken=${USDC_ADDRESS}&toToken=${vaultTokenAddress}&fromAddress=${userAddress}&toAddress=${userAddress}&fromAmount=${amountWei}`);
            const quote = await quoteRes.json();

            if (quoteRes.ok) {
                if (quote.estimate && quote.estimate.approvalAddress) {
                    const usdcContract = new ethers.Contract(USDC_ADDRESS, ERC20_ABI, signer);
                    const allowance = await usdcContract.allowance(userAddress, quote.estimate.approvalAddress);
                    if (allowance < BigInt(amountWei)) {
                        const approveTx = await usdcContract.approve(quote.estimate.approvalAddress, amountWei);
                        const approveReceipt = await approveTx.wait();
                        if (!approveReceipt) throw new Error("LI.FI Approval Transaction Dropped");
                    }
                }
                const zapTx = await signer.sendTransaction(quote.transactionRequest);
                const zapReceipt = await zapTx.wait();
                if (!zapReceipt) throw new Error("LI.FI Zap Transaction Dropped");

                streamAsset = vaultTokenAddress;
                streamDepositAmount = quote.estimate.toAmount; 
            }
        }

        const assetContract = new ethers.Contract(streamAsset, ERC20_ABI, signer);
        const inflowAllowance = await assetContract.allowance(userAddress, INFLOW_CONTRACT);
        if (inflowAllowance < BigInt(streamDepositAmount)) {
            const approveInflowTx = await assetContract.approve(INFLOW_CONTRACT, streamDepositAmount);
            const approveInflowReceipt = await approveInflowTx.wait();
            if (!approveInflowReceipt) throw new Error("inFlow Approval Transaction Dropped");
        }

        const remainder = BigInt(streamDepositAmount) % BigInt(durationSecs);
        const finalDeposit = BigInt(streamDepositAmount) - remainder;

        const startTime = Math.floor(Date.now() / 1000) + 60; 
        const stopTime = startTime + durationSecs;

        const inflowContract = new ethers.Contract(INFLOW_CONTRACT, INFLOW_ABI, signer);
        
        const createTx = await inflowContract.createStream(
            ethers.ZeroAddress, streamAsset, finalDeposit.toString(), startTime, stopTime, claimHash
        );
        
        const receipt = await createTx.wait();
        if (!receipt) throw new Error("Stream Creation Transaction Dropped");
        
        return JSON.stringify({ txHash: receipt.hash, secret: secretKey });
    } catch (error) {
        throw error;
    }
}

export async function claimSecureStream(streamId: number): Promise<string> {
    const accessToken = await privy.getAccessToken();
    const res = await fetch(`${RELAY_URL}/get-secret`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${accessToken}` },
        body: JSON.stringify({ streamId })
    });
    
    if (!res.ok) throw new Error("Unauthorized to claim stream");
    const { secretKey } = await res.json();
    
    const inflowContract = new ethers.Contract(INFLOW_CONTRACT, INFLOW_ABI, signer);
    const claimTx = await inflowContract.claimStream(streamId, secretKey);
    const receipt = await claimTx.wait();
    if (!receipt) throw new Error("Claim Transaction Dropped");

    await fetch(`${RELAY_URL}/mark-claimed`, {
        method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ streamId })
    });

    return receipt.hash;
}

export async function withdrawAndRedeemYield(streamId: number, amountStr: string, vaultTokenAddress: string): Promise<string> {
    try {
        const userAddress = await signer.getAddress();
        const inflowContract = new ethers.Contract(INFLOW_CONTRACT, INFLOW_ABI, signer);

        const withdrawTx = await inflowContract.withdrawFromStream(streamId, amountStr);
        let receipt = await withdrawTx.wait();
        if (!receipt) throw new Error("Withdraw Transaction Dropped");

        if (vaultTokenAddress && vaultTokenAddress !== USDC_ADDRESS) {
            const quoteRes = await fetch(`https://li.quest/v1/quote?fromChain=${chainId}&toChain=${chainId}&fromToken=${vaultTokenAddress}&toToken=${USDC_ADDRESS}&fromAddress=${userAddress}&toAddress=${userAddress}&fromAmount=${amountStr}`);
            const quote = await quoteRes.json();

            if (quoteRes.ok && quote.transactionRequest) {
                if (quote.estimate && quote.estimate.approvalAddress) {
                    const vaultContract = new ethers.Contract(vaultTokenAddress, ERC20_ABI, signer);
                    const allowance = await vaultContract.allowance(userAddress, quote.estimate.approvalAddress);
                    if (allowance < BigInt(amountStr)) {
                        const approveTx = await vaultContract.approve(quote.estimate.approvalAddress, amountStr);
                        const approveReceipt = await approveTx.wait();
                        if (!approveReceipt) throw new Error("LI.FI Approval Dropped");
                    }
                }
                const redeemTx = await signer.sendTransaction(quote.transactionRequest);
                receipt = await redeemTx.wait();
                if (!receipt) throw new Error("LI.FI Redeem Transaction Dropped");
            }
        }
        return receipt.hash;
    } catch (error) {
        throw error;
    }
}

export async function cancelStream(streamId: number): Promise<string> {
    const inflowContract = new ethers.Contract(INFLOW_CONTRACT, INFLOW_ABI, signer);
    const tx = await inflowContract.cancelStream(streamId);
    const receipt = await tx.wait();
    if (!receipt) throw new Error("Cancel Transaction Dropped");
    return receipt.hash;
}

export async function executeNativeSwap(tokenInSymbol: string, tokenOutSymbol: string, amountInStr: string): Promise<string> {
    try {
        const userAddress = await signer.getAddress();
        const amountWei = ethers.parseUnits(amountInStr, 6).toString();
        const quoteRes = await fetch(`https://li.quest/v1/quote?fromChain=${chainId}&toChain=${chainId}&fromToken=${USDC_ADDRESS}&toToken=${tokenOutSymbol}&fromAddress=${userAddress}&toAddress=${userAddress}&fromAmount=${amountWei}`);
        const quote = await quoteRes.json();

        if (!quoteRes.ok) throw new Error("LI.FI Swap Route not found.");

        if (quote.estimate && quote.estimate.approvalAddress) {
            const tokenContract = new ethers.Contract(USDC_ADDRESS, ERC20_ABI, signer);
            const approveTx = await tokenContract.approve(quote.estimate.approvalAddress, amountWei);
            const approveReceipt = await approveTx.wait();
            if (!approveReceipt) throw new Error("Swap Approval Dropped");
        }

        const swapTx = await signer.sendTransaction(quote.transactionRequest);
        const receipt = await swapTx.wait();
        if (!receipt) throw new Error("Swap Transaction Dropped");
        return receipt.hash;
    } catch (error) {
        throw error;
    }
}

export async function transferToken(tokenSymbol: string, recipientAddress: string, amountStr: string): Promise<string> {
    const amountWei = ethers.parseUnits(amountStr, 6).toString(); 
    const tokenContract = new ethers.Contract(USDC_ADDRESS, ERC20_ABI, signer);
    const tx = await tokenContract.transfer(recipientAddress, amountWei);
    const receipt = await tx.wait();
    if (!receipt) throw new Error("Transfer Transaction Dropped");
    return receipt.hash;
}

export async function getBalance(tokenAddress: string): Promise<string> {
    if (!signer) return "0.00";
    try {
        const userAddress = await signer.getAddress();
        if (tokenAddress === "ETH") {
            const balance = await ethersProvider.getBalance(userAddress);
            return ethers.formatEther(balance);
        }
        const targetAddress = tokenAddress === "USDC" ? USDC_ADDRESS : tokenAddress;
        const tokenContract = new ethers.Contract(targetAddress, ERC20_ABI, ethersProvider);
        const balance = await tokenContract.balanceOf(userAddress);
        const decimals = await tokenContract.decimals();
        return ethers.formatUnits(balance, Number(decimals));
    } catch (e) {
        return "0.00";
    }
}

export async function getNextStreamId(): Promise<number> {
    if (!ethersProvider) return 1;
    const inflowContract = new ethers.Contract(INFLOW_CONTRACT, INFLOW_ABI, ethersProvider);
    const nextId = await inflowContract.nextStreamId();
    return Number(nextId);
}

export async function getStream(streamId: number): Promise<any[] | null> {
    if (!ethersProvider) return null;
    const inflowContract = new ethers.Contract(INFLOW_CONTRACT, INFLOW_ABI, ethersProvider);
    const stream = await inflowContract.streams(streamId);
    
    return [
        stream.sender, stream.recipient, stream.asset, stream.deposit.toString(), "0", 
        stream.ratePerSecond.toString(), "0", stream.startTime.toString(), stream.stopTime.toString(),
        stream.remainingBalance.toString(), "0", stream.withdrawnAmount.toString(), "0", stream.claimHash
    ];
}

export async function waitForTransaction(txHash: string): Promise<void> {
    if (!ethersProvider) return;
    await ethersProvider.waitForTransaction(txHash);
}

const zapBridgeObj = {
    initBridge, sendEmailOtp, verifyEmailOtpAndConnect, createYieldStream,
    storeStreamSecret, claimSecureStream, withdrawAndRedeemYield,
    cancelStream, executeNativeSwap, transferToken, getBalance,
    getNextStreamId, getStream, logout, waitForTransaction,
    checkAndTriggerSponsorship
};

(window as any).ZapBridge = zapBridgeObj;