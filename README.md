# ⚡ inFlow × LI.FI Earn

> **Get paid by the second. Your salary earns vault yield while it streams.**

[![Built on Base](https://img.shields.io/badge/Built%20on-Base-0052FF?style=flat-square&logo=coinbase)](https://base.org)
[![Powered by LI.FI](https://img.shields.io/badge/Yield%20by-LI.FI%20Earn-6366F1?style=flat-square)](https://docs.li.fi/earn/overview)
[![Auth by Privy](https://img.shields.io/badge/Auth-Privy-FF6B6B?style=flat-square)](https://privy.io)
[![DeFi Mullet Hackathon](https://img.shields.io/badge/DeFi%20Mullet-Hackathon%20%231-F59E0B?style=flat-square)](https://t.me/lifibuilders)
[![Track](https://img.shields.io/badge/Track-DeFi%20UX%20Challenge-00C97A?style=flat-square)](#)

---

<div align="center">

### 🌍 Africa's First Salary Streaming Service

*The first platform on the continent where your salary hits your pocket the moment you work —*
*second by second — and keeps growing while it waits for you.*

</div>

---

<div align="center">

**[🚀 Live App](https://useinflow.web.app/how-it-works) · [📹 Demo Video](#-demo) · [📖 How It Works](#how-it-works)**

</div>

---

## 📹 Demo



https://github.com/user-attachments/assets/fd76decd-6ac6-4848-8888-4d60cd29baa2

https://github.com/user-attachments/assets/YOUR_VIDEO_ASSET_ID_HERE

> ☝️ **To embed your video:** Open any GitHub Issue or PR → drag and drop your `.mp4` into the text box → wait for the upload link → copy the `https://github.com/user-attachments/assets/...` URL → paste it above replacing the placeholder. GitHub renders it as a native inline video player automatically — no third-party hosting needed.

---

## The Problem

Across Africa, delayed wages are an epidemic. An employee works for 30 days, hands over their full labour, and waits — hoping their employer pays on time, in full, at all. The ILO has formally described wage debt as *"another African epidemic."*

**93% of Nigeria's workforce has no formal wage contract.** No receipts. No proof. No legal recourse.

But there's a second, quieter problem: when an employer *does* lock funds for salary, that capital sits **completely idle** until payday. A 1,000 USDC salary budget locked for 30 days earns exactly $0 for 29 days.

inFlow solves both.

---

## 🌍 Africa's First Salary Streaming Service

Imagine if, instead of waiting 30 days for your paycheck, you could open an app right now and see the exact amount you have earned — down to the last second. Then tap a button and have it in your pocket. No waiting. No chasing. No asking.

That is inFlow.

We did not just build a payments app. We built a completely new way for workers and employers to relate to money — one where:

- **You earn money the moment you work**, not weeks later
- **Your employer's locked salary budget grows** in a savings vault while it waits for you to claim it
- **You share in that growth** — collecting your salary *plus* the interest it earned while sitting there
- **All you need is an email address** — no bank account, no crypto wallet, no financial history required
- **You can collect your earnings any time** — no approval needed, no forms, no waiting for payday

This is Africa's first salary streaming service. And it is live right now.

> *"Your labour is not a loan. And now, neither is your employer's capital."*

---

## What Is inFlow?

inFlow is a **yield-boosted salary streaming app** built for the 3 billion people who have a smartphone and an email address but no bank account or crypto wallet.

**For employers**: Lock a salary budget → funds auto-deposit into the best LI.FI Earn vault → send a payment link → done.

**For employees**: Open a link → sign in with email → watch your salary tick up per second → collect anytime. No wallet. No seed phrase. No crypto knowledge.

The blockchain is entirely invisible. The trust is entirely real.

---

## How It Works

### 1 — Employer signs in with email
No wallet setup. No seed phrase. No browser extension. Just an email address. [Privy](https://privy.io) creates a secure, non-custodial EVM wallet on Base silently in the background. You own the keys — you just never have to see them.

### 2 — Salary budget auto-deposits into LI.FI Earn vault
The moment a stream is created, the full salary budget is deposited into the best available vault via the **LI.FI Earn API**. The API scans 20+ protocols (Morpho Blue, Aave v3, Euler, Pendle, Ethena) across 60+ chains and selects the optimal USDC vault by APY and risk profile — currently yielding 5–9% APY on Base.

The idle capital that used to do nothing now works from the first second.

### 3 — Salary streams per-second to the employee
A smart contract on Base releases the employee's allocation continuously — by the second. If you have worked 12 of 30 days, exactly 40% of your salary is claimable *right now*. No asking. No approval. No waiting.

### 4 — Employee opens the link, signs in with email
The employer sends a unique payment link (looks like a normal URL). Employee opens it from any device, enters their email, and a wallet is created automatically. They land on a dashboard showing their earnings ticking upward in real time.

### 5 — Collect salary + vault yield, any time
When the employee hits "Collect Earnings," the LI.FI Earn API redeems their proportional vault shares. They receive their vested salary **plus the accumulated vault yield** — a bonus they never had to think about or manage. One tap. Instant settlement on Base.

---

## The DeFi Mullet Explained

> *"Business up front, party in the back."*

The user sees a one-click "Collect Earnings" button. Behind it:

```
User taps "Collect" →
  LI.FI Earn API: calculate vested shares
  LI.FI Earn API: redeem USDC from Morpho vault
  Stream contract: verify elapsed time
  Base: settle USDC to employee wallet
  ← User sees "$847.33 arrived" ✓
```

No protocol-hopping. No bridging. No gas management. **One button. Full DeFi infrastructure.**

---

## LI.FI Earn Integration

inFlow uses three LI.FI Earn API endpoints:

| Endpoint | Usage |
|----------|-------|
| `GET /v1/vaults` | On stream creation — find best vault by chain, token, APY |
| `POST /v1/composer/deposit` | Lock employer's salary budget into vault (swap + deposit, 1 tx) |
| `POST /v1/composer/withdraw` | Employee collects earnings — redeem vault shares for USDC |

```js
// 1. Find best vault on Base for USDC
const vaults = await fetch('https://earn.li.fi/v1/vaults?chainId=8453');
const best = vaults
  .filter(v => v.token.symbol === 'USDC')
  .sort((a, b) => b.apy - a.apy)[0];
// → Morpho Blue USDC · 6.2% APY · $48M TVL

// 2. Deposit on stream creation (one-click via Composer)
await fetch('https://earn.li.fi/v1/composer/deposit', {
  method: 'POST',
  body: JSON.stringify({
    vaultAddress: best.address,
    chainId: 8453,
    amount: '1000000000', // 1000 USDC
    fromAddress: employerWallet,
    tokenAddress: USDC_BASE,
  })
});

// 3. Employee collects — redeem proportional shares
await fetch('https://earn.li.fi/v1/composer/withdraw', {
  method: 'POST',
  body: JSON.stringify({
    vaultAddress: best.address,
    amount: vestedShares,
    toAddress: employeeWallet,
  })
});
```

---

## Features

| Feature | Status |
|---------|--------|
| Email login — no wallet or crypto knowledge required | ✅ Live |
| Wallet auto-creation via Privy (non-custodial) | ✅ Live |
| Real-time per-second earning ticker on landing page | ✅ Live |
| Live APY display on stream creation form | ✅ Live |
| 3-step guided stream creation wizard | ✅ Live |
| Payment link sharing — recipient needs only an email | ✅ Live |
| Deep-link stream claiming via URL parameters (`?stream=ID`) | ✅ Live |
| Recipient email validation before stream claim | ✅ Live |
| LI.FI Earn vault auto-deposit on stream creation | ✅ Live |
| Vault categorisation: Safe (TVL ≥ $1M) vs Emerging | ✅ Live |
| Live vault health checker — detects paused/frozen protocols | ✅ Live |
| Auto-fallback vault selection if active vault is paused | ✅ Live |
| Yield + salary combined collection in one tap | ✅ Live |
| Earn tab — browse and deposit into vaults directly | ✅ Live |
| Yield-to-recipient toggle (employer keeps or passes yield) | ✅ Live |
| Stream cancellation with proportional refund to employer | ✅ Live |
| Multi-token support: USDC / ETH | ✅ Live |
| ETH ↔ USDC in-app swap via LI.FI | ✅ Live |
| Live ETH price feed for real-time USD conversion | ✅ Live |
| QR code deposit screen for receiving funds | ✅ Live |
| Direct token transfer to any EVM address | ✅ Live |
| 25 / 50 / 75 / MAX quick-select percentage buttons | ✅ Live |
| Stealth USDC airdrop for new users (auto-detected) | ✅ Live |
| Gas sponsorship — users never pay transaction fees | ✅ Live |
| Live 8-second heartbeat: balances and streams auto-refresh | ✅ Live |
| BaseScan explorer links for every transaction | ✅ Live |
| Circular stream progress indicator on stream cards | ✅ Live |
| Base Mainnet + Sepolia testnet support | ✅ Live |
| Cloudflare Worker relay — stream secrets, metadata, faucet | ✅ Live |
| Fully non-custodial — both parties own their keys | ✅ Live |

---

## Tech Stack

```
Frontend     Flutter Web (Dart) — deployed on Firebase Hosting
Auth         Privy — email OTP → non-custodial EVM wallet on Base
Yield        LI.FI Earn API — vault discovery, deposit, withdrawal
Chain        Base (EVM) — low fees, fast finality
Relay        Cloudflare Workers — stream secrets, faucet, metadata
Streaming    Custom escrow contract on Base
```

### Why Flutter Web?

Flutter Web is an unusual choice for a DeFi product — and a deliberate one. The African market is mobile-first but fragmented across devices and OS versions. Flutter compiles to a single performant web binary that runs identically on a $100 Android phone and a MacBook Pro. One codebase. Zero app store friction. Instant access via payment link — which is exactly how inFlow's recipient flow is designed to work.

### Vault Safety Architecture

When vaults are loaded from the LI.FI Earn API, inFlow doesn't just display them — it actively verifies them. A background health scanner calls `checkVaultStatus` on each vault address. If a vault is paused or frozen by its own protocol admins, inFlow marks it as unavailable, warns the user, and automatically falls back to the next healthy vault. This means salary streams are never routed into broken infrastructure, even if a protocol pauses mid-session.

### Gas Sponsorship

New users never pay gas fees. When a wallet is created for the first time, inFlow's Cloudflare Worker backend detects the new address and triggers a sponsorship call that covers transaction costs. Paired with the stealth USDC airdrop, a brand-new user can go from zero to creating a live salary stream without spending a cent.

### Deep-Link Stream Claiming

Every salary stream generates a unique payment URL (`useinflow.web.app?stream=ID`). When a recipient opens the link, the app fetches stream metadata from the Cloudflare Worker relay — including the intended recipient email, network, and claimed status. If the stream has already been claimed, a clear UI is shown. If the email doesn't match the intended recipient, the claim is blocked. This makes the link both shareable and tamper-resistant.

---

## Screenshots

#### 🏠 Landing
![Landing](./screenshots/landing.jpg)

#### 💸 Stream + Yield
![Stream](./screenshots/stream.jpg)

#### 📊 My Streams
![Streams](./screenshots/streams.jpg)

#### 🏦 Earn Vaults
![Earn](./screenshots/earn.jpg)

---

## Try It

**Live App**: [useinflow.web.app](https://useinflow.web.app/how-it-works)

1. Go to [useinflow.web.app](https://useinflow.web.app/how-it-works)
2. Switch to **Base Mainnet** in the top toggle
3. Sign in with any email
4. Receive free USDC automatically from the stealth airdrop (gas included)
5. Create a salary stream → it auto-deposits into a LI.FI vault
6. Send the payment link to a friend (or open it in a second browser with a different email)
7. Watch earnings tick up per-second, then collect salary + yield in one tap

---

## Why It Matters

Africa has the world's fastest-growing workforce and some of its most vibrant freelance ecosystems — yet workers routinely extend zero-interest loans to their employers every month, simply by working before they are paid.

inFlow is built on the belief that **money should move at the speed of work.** No one should have to wait a month to access wages they have already earned. And with LI.FI Earn, the capital sitting in escrow does not sit idle — it works as hard as the people it is meant to pay.

This is not just a DeFi product. It is a new social contract between employers and workers — one where trust is written into code, yield flows automatically, and the person doing the work is always first in line.

---

## Hackathon Submission

- **Event**: DeFi Mullet Hackathon #1 — Builder Edition
- **Track**: 🎨 DeFi UX Challenge | Open Track
- **API Used**: [LI.FI Earn](https://docs.li.fi/earn/overview) — vault discovery, Composer deposit, Composer withdraw
- **Chain**: Base Mainnet + Sepolia

---

## Built With

- [LI.FI Earn API](https://docs.li.fi/earn/overview)
- [Privy](https://privy.io) — embedded wallets
- [Base](https://base.org) — EVM L2
- [Cloudflare Workers](https://workers.cloudflare.com)
- [Flutter Web](https://flutter.dev)

---

<div align="center">
  <strong>Built for DeFi Mullet Hackathon #1 · April 2026</strong><br>
  <sub>⚡ inFlow — Africa's first salary streaming service · payroll infrastructure for the next billion</sub>
</div>
