import abis from "./abis.json";

// ── Sepolia addresses ─────────────────────────────────────────────────────────
export const ADDRESSES = {
  vaultRegistry: "0x03c2841ABfB101B521A9b1c5BbE122A5ea20AE20" as `0x${string}`,
  vaultFactory:  "0x943b0b26c3fF2a7f60503fC65A0eD87Bf4DDeE7c" as `0x${string}`,
  usdc:          "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238" as `0x${string}`,
} as const;

export const USDC_DECIMALS = 6;
export const USDC_UNIT = 1_000_000n; // 1 USDC in raw units

// ── ABIs ──────────────────────────────────────────────────────────────────────
export const SPLIT_VAULT_ABI    = abis.SplitVault    as any[];
export const MEMBER_DAO_ABI     = abis.MemberDAO     as any[];
export const VAULT_FACTORY_ABI  = abis.VaultFactory  as any[];
export const VAULT_REGISTRY_ABI = abis.VaultRegistry as any[];
export const ENS_MANAGER_ABI    = abis.ENSManager    as any[];

export const ERC20_ABI = [
  {
    name: "balanceOf",
    type: "function",
    stateMutability: "view",
    inputs:  [{ name: "account", type: "address" }],
    outputs: [{ name: "",        type: "uint256"  }],
  },
  {
    name: "allowance",
    type: "function",
    stateMutability: "view",
    inputs:  [{ name: "owner", type: "address" }, { name: "spender", type: "address" }],
    outputs: [{ name: "",      type: "uint256" }],
  },
  {
    name: "approve",
    type: "function",
    stateMutability: "nonpayable",
    inputs:  [{ name: "spender", type: "address" }, { name: "amount", type: "uint256" }],
    outputs: [{ name: "",        type: "bool"    }],
  },
  {
    name: "decimals",
    type: "function",
    stateMutability: "view",
    inputs:  [],
    outputs: [{ name: "", type: "uint8" }],
  },
] as const;

// ── Helpers ───────────────────────────────────────────────────────────────────
export function formatUsdc(raw: bigint): string {
  const whole = raw / USDC_UNIT;
  const frac  = raw % USDC_UNIT;
  if (frac === 0n) return whole.toString();
  return `${whole}.${frac.toString().padStart(6, "0").replace(/0+$/, "")}`;
}

export function parseUsdc(amount: string): bigint {
  const [whole, frac = ""] = amount.split(".");
  const fracPadded = frac.padEnd(6, "0").slice(0, 6);
  return BigInt(whole) * USDC_UNIT + BigInt(fracPadded);
}

export const VOTING_DURATION_OPTIONS = [
  { label: "1 hour  (testing)",  value: 3600      },
  { label: "1 day",              value: 86400     },
  { label: "3 days",             value: 259200    },
  { label: "1 week",             value: 604800    },
];
