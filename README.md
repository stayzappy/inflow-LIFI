# ⚡ inFlow

**Money that moves as fast as you do.** inFlow is a streaming salary protocol built on Base that allows workers to get paid by the second, while automatically routing idle employer budgets into DeFi yield vaults.

## 🌍 The Problem
Across Africa and emerging markets, delayed wages are an epidemic. Employees hand over 30 days of labor upfront and wait, hoping their employer pays on time. The ILO describes wage debt as a systemic issue. Workers are effectively giving their employers zero-interest loans every month.

## 💡 The Solution
inFlow makes labor verifiable and instantly liquid. Instead of waiting for payday, salaries stream continuously. If you've worked 12 days, you can withdraw exactly 40% of your salary. 

Furthermore, we made Web3 completely invisible. A first-generation smartphone user can receive a payment link via WhatsApp, log in with just their email, and withdraw their earnings to a local exchange—all without knowing what a blockchain, seed phrase, or gas fee is.

## ✨ Key Features

* **Invisible Onboarding (Privy):** Users sign in with an email address. A secure, non-custodial EVM wallet is generated silently in the background. 
* **The "Stealth Drop" (Gasless UX):** We built a custom Cloudflare Worker Treasury. The moment a new user logs in, our backend silently airdrops 0.02 USDC and 0.00015 ETH (for gas) into their account. They never see an "insufficient gas" error.
* **Auto-Yield Routing (LI.FI Composer):** Employer funds don't sit idle. When a stream is created, inFlow uses LI.FI to automatically route the budget into top-tier lending protocols (like Morpho or Aave). The budget earns APY while it waits to be streamed. Employees receive their earned salary **plus** the yield bonus.
* **Sub-Second Finality:** Built natively on Base Mainnet for fractions-of-a-penny transaction costs and Web2-like speeds.

## 🛠 How It Works

### For Employers (Payers)
1. **Sign in:** Email login. No wallet required.
2. **Set Budget:** Enter a total budget and a timeframe (e.g., 500 USDC over 30 days).
3. **Zap into Yield:** The app uses LI.FI to automatically swap and deposit the funds into an interest-bearing vault. 
4. **Send Link:** A secure URL is generated and sent to the employee.

### For Employees (Earners)
1. **Click the Link:** Open the URL sent by the employer.
2. **Authenticate:** Log in with email.
3. **Watch it Grow:** The dashboard shows the salary unlocking by the millisecond. 
4. **Collect:** Withdraw unlocked earnings (salary + yield) at any time.

## 🏗 System Architecture

* **Frontend:** Flutter Web (Responsive Desktop & Mobile UI)
* **Authentication:** Privy Embedded Wallets (EVM)
* **Smart Contracts:** Deployed on Base Mainnet
* **Cross-Chain / Yield:** LI.FI REST API & Smart Routing
* **Blockchain Interaction:** `ethers.js` via custom Webpack bridge
* **Backend Relay & Treasury:** Cloudflare Workers (handles the Stealth Drop faucet and secure stream link routing)

## 🚀 Running Locally

### 1. The Frontend (Flutter)
Ensure you have Flutter installed on the `stable` channel.
```bash
flutter clean
flutter pub get
flutter run -d chrome