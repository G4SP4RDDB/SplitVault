"use client";

import { useAccount }   from "wagmi";
import { useRouter }    from "next/navigation";
import Link             from "next/link";
import { useAllVaults, useMyVaults } from "@/hooks/useVaults";
import { VaultCard }    from "@/components/vault-card";

export default function DashboardPage() {
  const { address, isConnected } = useAccount();
  const router = useRouter();

  const { data: allVaultsRaw, isLoading: loadingAll } = useAllVaults();
  const allVaults = (allVaultsRaw as `0x${string}`[] | undefined) ?? [];
  const { vaults: myVaults, isLoading: loadingMine } = useMyVaults(allVaults, address);

  if (!isConnected) {
    return (
      <div className="text-center py-20 text-gray-400">
        Connect your wallet to see your vaults.
      </div>
    );
  }

  const isLoading = loadingAll || loadingMine;

  return (
    <div className="flex flex-col gap-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">My Vaults</h1>
          <p className="text-gray-400 text-sm mt-1">
            Vaults where your wallet is a member
          </p>
        </div>
        <Link
          href="/vault/new"
          className="px-4 py-2 rounded-lg bg-indigo-600 hover:bg-indigo-500 font-medium text-sm transition-colors"
        >
          + New Vault
        </Link>
      </div>

      {/* Join by address/ENS */}
      <JoinVaultInput onJoin={(addr) => router.push(`/vault/${addr}`)} />

      {/* Vault list */}
      {isLoading ? (
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          {[1, 2].map((i) => (
            <div key={i} className="h-36 rounded-xl bg-gray-800 animate-pulse" />
          ))}
        </div>
      ) : myVaults.length === 0 ? (
        <div className="text-center py-16 border border-dashed border-gray-700 rounded-xl text-gray-500">
          <p className="mb-4">You are not a member of any vault yet.</p>
          <Link href="/vault/new" className="text-indigo-400 hover:underline">
            Create your first vault
          </Link>
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          {myVaults.map((vault) => (
            <VaultCard key={vault} vaultAddress={vault} walletAddress={address!} />
          ))}
        </div>
      )}
    </div>
  );
}

function JoinVaultInput({ onJoin }: { onJoin: (addr: string) => void }) {
  return (
    <div className="flex gap-2">
      <input
        type="text"
        placeholder="Join vault by address or ENS name (e.g. vaulthack.eth)"
        className="flex-1 px-4 py-2 rounded-lg bg-gray-800 border border-gray-700 text-sm focus:outline-none focus:border-indigo-500 placeholder-gray-500"
        onKeyDown={(e) => {
          if (e.key === "Enter") {
            const val = (e.target as HTMLInputElement).value.trim();
            if (val) onJoin(val);
          }
        }}
      />
      <button
        className="px-4 py-2 rounded-lg bg-gray-700 hover:bg-gray-600 text-sm transition-colors"
        onClick={(e) => {
          const input = (e.currentTarget.previousSibling as HTMLInputElement);
          if (input.value.trim()) onJoin(input.value.trim());
        }}
      >
        Open
      </button>
    </div>
  );
}
