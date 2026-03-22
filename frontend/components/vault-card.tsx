"use client";

import Link from "next/link";
import { useReadContract } from "wagmi";
import { useVaultMembers } from "@/hooks/useVaults";
import { ADDRESSES, ERC20_ABI, formatUsdc } from "@/lib/contracts";

interface Props {
  vaultAddress:  `0x${string}`;
  walletAddress: `0x${string}`;
}

export function VaultCard({ vaultAddress, walletAddress }: Props) {
  const { members } = useVaultMembers(vaultAddress);

  const { data: balanceRaw } = useReadContract({
    address:      ADDRESSES.usdc,
    abi:          ERC20_ABI,
    functionName: "balanceOf",
    args:         [vaultAddress],
  });

  const balance = balanceRaw as bigint | undefined;
  const myShare = members.find(
    (m) => m.address.toLowerCase() === walletAddress.toLowerCase()
  )?.percentage;

  const short = `${vaultAddress.slice(0, 6)}…${vaultAddress.slice(-4)}`;

  return (
    <Link href={`/vault/${vaultAddress}`}>
      <div className="bg-gray-900 border border-gray-800 hover:border-indigo-500 rounded-xl p-5 cursor-pointer transition-colors">
        <div className="flex items-start justify-between mb-3">
          <div>
            <p className="font-mono text-sm text-gray-400">{short}</p>
            {myShare !== undefined && (
              <p className="text-xs text-indigo-400 mt-0.5">Your share: {myShare}%</p>
            )}
          </div>
          <span className="text-xs px-2 py-1 rounded-full bg-gray-800 border border-gray-700 text-gray-300">
            {members.length} member{members.length !== 1 ? "s" : ""}
          </span>
        </div>

        <div className="mt-3 pt-3 border-t border-gray-800">
          <p className="text-xs text-gray-500 mb-1">Vault balance</p>
          <p className="text-lg font-semibold">
            {balance !== undefined ? `${formatUsdc(balance)} USDC` : "—"}
          </p>
        </div>
      </div>
    </Link>
  );
}
