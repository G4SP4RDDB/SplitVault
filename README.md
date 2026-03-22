# SplitVault

A decentralised fund-splitting protocol with on-chain governance and ENS subdomain integration, built for the ENS Hackathon.

## What it does

SplitVault lets a group of people pool USDC into a shared vault, split earnings according to configurable percentage shares, and govern membership changes through on-chain voting — all with every vault automatically receiving a human-readable ENS name.

**Core flow:**
1. A user picks a name (e.g. `teamvault`) and creates a vault in a single transaction
2. `teamvault.vaulthack.eth` is registered in the ENS registry pointing to the vault contract
3. Anyone can deposit USDC into the vault
4. Any member can trigger a distribution — funds are split proportionally in one transaction
5. Adding a new member or changing shares requires a governance vote (66% quorum) via the MemberDAO
6. When a new member is accepted, their ENS subdomain is registered automatically (e.g. `alice.vaulthack.eth`)

## Architecture

```
SplitVault          — holds USDC, tracks member shares, distributes funds
MemberDAO           — on-chain governance: propose / vote / execute membership changes
ENSManager          — registers subdomains under vaulthack.eth for vaults and members
VaultRegistry       — on-chain directory of all deployed vaults (no indexer needed)
VaultFactory        — deploys SplitVault + MemberDAO + books ENS name in one transaction
```

Ownership chain: `VaultFactory` deploys everything → transfers vault ownership to `MemberDAO` → `MemberDAO` is the only address that can modify vault membership.

## Tech stack

| Layer | Technology |
|---|---|
| Smart contracts | Solidity 0.8.24, Foundry (forge / cast) |
| Token standard | ERC-20 (USDC on Sepolia) |
| Naming | ENS Registry + Public Resolver (Sepolia) |
| Frontend | Next.js 16, TypeScript, Tailwind CSS |
| Web3 | wagmi v2, viem v2, @tanstack/react-query |
| Wallet | MetaMask via `injected()` connector |
| Network | Ethereum Sepolia testnet |

## Deployed contracts (Sepolia)

| Contract | Address |
|---|---|
| ENSManager | `0xb2E90307A66f1E26cab830959A181c4Dfd69D150` |
| VaultRegistry | `0xF21FE8FBAcF07f05F89F8bf3FdF5Ef2474229bf0` |
| VaultFactory | `0x4Af75Daf65Fb4E59DAb1d2cd5f40Aa63E82804Be` |
| USDC (Sepolia) | `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238` |

ENS parent domain: `vaulthack.eth`

## Running locally

**Contracts**
```bash
forge build
forge test          # 128 tests
```

**Frontend**
```bash
cd frontend
npm install
npm run dev         # http://localhost:3000
```

Requires MetaMask connected to Sepolia.

## Deploy

```bash
cp .env.example .env   # fill PRIVATE_KEY, SEPOLIA_RPC_URL
forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast
```

After deployment, reclaim the ENS parent node to the new ENSManager:
```bash
cast send <BaseRegistrar> "reclaim(uint256,address)" <tokenId> <ensManagerAddr> \
  --private-key $PRIVATE_KEY --rpc-url $SEPOLIA_RPC_URL
```
