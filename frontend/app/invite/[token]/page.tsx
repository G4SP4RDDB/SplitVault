"use client";

import { use }             from "react";
import { isAddress }       from "viem";
import Link                from "next/link";
import { useAccount }      from "wagmi";
import { useVaultMembers } from "@/hooks/useVaults";
import { formatUsdc }      from "@/lib/contracts";
import { useReadContract } from "wagmi";
import { ADDRESSES, ERC20_ABI } from "@/lib/contracts";

export default function InvitePage({ params }: { params: Promise<{ token: string }> }) {
  const { token }               = use(params);
  const { address, isConnected } = useAccount();

  // token = vault address for now
  const vaultAddress = isAddress(token) ? (token as `0x${string}`) : undefined;
  const { members }  = useVaultMembers(vaultAddress);

  const { data: balanceRaw } = useReadContract({
    address:      ADDRESSES.usdc,
    abi:          ERC20_ABI,
    functionName: "balanceOf",
    args:         vaultAddress ? [vaultAddress] : undefined,
    query:        { enabled: !!vaultAddress },
  });

  const balance = (balanceRaw as bigint | undefined) ?? 0n;

  const alreadyMember = address && members.some(
    (m) => m.address.toLowerCase() === address.toLowerCase()
  );

  if (!vaultAddress) {
    return (
      <div className="text-center py-20 text-gray-400">Invalid invite link.</div>
    );
  }

  return (
    <div className="max-w-md mx-auto flex flex-col gap-6 py-10">
      {/* Header */}
      <div className="text-center">
        <h1 className="text-2xl font-bold mb-2">You've been invited</h1>
        <p className="text-gray-400 text-sm">
          Someone shared a SplitVault with you.
        </p>
      </div>

      {/* Vault info */}
      <div className="bg-gray-900 border border-gray-800 rounded-xl p-5 flex flex-col gap-4">
        <div>
          <p className="text-xs text-gray-500 mb-1">Vault Address</p>
          <p className="font-mono text-sm text-gray-300 break-all">{vaultAddress}</p>
        </div>

        <div>
          <p className="text-xs text-gray-500 mb-1">Current Balance</p>
          <p className="text-xl font-semibold">{formatUsdc(balance)} USDC</p>
        </div>

        <div>
          <p className="text-xs text-gray-500 mb-2">Members ({members.length})</p>
          <div className="flex flex-col gap-1">
            {members.map((m) => (
              <div key={m.address} className="flex justify-between text-sm">
                <span className="font-mono text-gray-400">
                  {m.address.slice(0, 8)}…{m.address.slice(-4)}
                </span>
                <span>{m.percentage}%</span>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Notice about accept/decline */}
      <div className="bg-yellow-900/20 border border-yellow-800/40 rounded-xl p-4 text-sm text-yellow-300">
        Membership is governed on-chain. To join this vault, an existing member must
        propose your address through the DAO and receive a 66% vote.
        Accept/decline functionality will be available in a future update.
      </div>

      {/* Actions */}
      <div className="flex flex-col gap-3">
        {alreadyMember ? (
          <Link
            href={`/vault/${vaultAddress}`}
            className="px-4 py-3 rounded-lg bg-indigo-600 hover:bg-indigo-500 text-sm font-medium text-center transition-colors"
          >
            Open Vault Dashboard
          </Link>
        ) : (
          <>
            {isConnected ? (
              <Link
                href={`/vault/${vaultAddress}`}
                className="px-4 py-3 rounded-lg bg-gray-800 hover:bg-gray-700 text-sm font-medium text-center transition-colors"
              >
                View Vault
              </Link>
            ) : (
              <p className="text-center text-gray-500 text-sm">
                Connect your wallet to view the vault.
              </p>
            )}
          </>
        )}
      </div>
    </div>
  );
}
