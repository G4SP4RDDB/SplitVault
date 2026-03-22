"use client";

import { useState, use }   from "react";
import { useAccount }      from "wagmi";
import { isAddress }       from "viem";
import { useEnsAddress }   from "wagmi";
import { OverviewTab }     from "@/components/vault/overview-tab";
import { ProposalsTab }    from "@/components/vault/proposals-tab";
import { SettingsTab }     from "@/components/vault/settings-tab";
import { useVaultMembers, useVaultOwner } from "@/hooks/useVaults";

const TABS = ["Overview", "Proposals", "Settings"] as const;
type Tab = (typeof TABS)[number];

export default function VaultPage({ params }: { params: Promise<{ address: string }> }) {
  const { address: rawAddress } = use(params);
  const { address: wallet }     = useAccount();
  const [activeTab, setActiveTab] = useState<Tab>("Overview");

  // Support ENS names in the URL
  const isEns = rawAddress.endsWith(".eth");
  const { data: ensResolved } = useEnsAddress({
    name:  isEns ? rawAddress : undefined,
    query: { enabled: isEns },
  });

  const vaultAddress = (isEns
    ? ensResolved
    : isAddress(rawAddress) ? rawAddress : undefined
  ) as `0x${string}` | undefined;

  const { members } = useVaultMembers(vaultAddress);
  const { data: daoAddress } = useVaultOwner(vaultAddress);

  const isMember = wallet && members.some(
    (m) => m.address.toLowerCase() === wallet.toLowerCase()
  );

  if (!vaultAddress) {
    return (
      <div className="text-center py-20 text-gray-400">
        {isEns ? `Resolving ${rawAddress}…` : "Invalid vault address."}
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-6">
      {/* Header */}
      <div>
        <div className="flex items-center gap-3">
          <h1 className="text-2xl font-bold">
            {isEns ? rawAddress : `${vaultAddress.slice(0, 6)}…${vaultAddress.slice(-4)}`}
          </h1>
          {isMember && (
            <span className="text-xs px-2 py-1 rounded-full bg-indigo-900 border border-indigo-700 text-indigo-300">
              Member
            </span>
          )}
        </div>
        <p className="font-mono text-xs text-gray-500 mt-1">{vaultAddress}</p>
      </div>

      {/* Tabs */}
      <div className="flex gap-1 border-b border-gray-800">
        {TABS.map((tab) => (
          <button
            key={tab}
            onClick={() => setActiveTab(tab)}
            className={`px-4 py-2 text-sm font-medium transition-colors border-b-2 -mb-px ${
              activeTab === tab
                ? "border-indigo-500 text-white"
                : "border-transparent text-gray-400 hover:text-gray-200"
            }`}
          >
            {tab}
          </button>
        ))}
      </div>

      {/* Tab content */}
      {activeTab === "Overview" && (
        <OverviewTab
          vaultAddress={vaultAddress}
          wallet={wallet}
          isMember={!!isMember}
        />
      )}
      {activeTab === "Proposals" && (
        <ProposalsTab
          vaultAddress={vaultAddress}
          daoAddress={daoAddress as `0x${string}` | undefined}
          wallet={wallet}
          isMember={!!isMember}
          memberCount={members.length}
        />
      )}
      {activeTab === "Settings" && (
        <SettingsTab
          vaultAddress={vaultAddress}
          daoAddress={daoAddress as `0x${string}` | undefined}
          isMember={!!isMember}
        />
      )}
    </div>
  );
}
