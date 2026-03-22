"use client";

import Link from "next/link";
import { useAccount } from "wagmi";
import { ConnectButton } from "@/components/connect-button";

export default function LandingPage() {
  const { isConnected } = useAccount();

  return (
    <div className="flex flex-col items-center justify-center min-h-[70vh] text-center gap-8">
      {/* Hero */}
      <div className="flex flex-col items-center gap-4">
        <span className="text-5xl font-bold text-white">
          Split<span className="text-indigo-400">Vault</span>
        </span>
        <p className="text-xl text-gray-400 max-w-lg">
          On-chain payment splitting for DAOs, associations, and teams.
          Deposit USDC, let your governance decide the shares, distribute with one click.
        </p>
      </div>

      {/* Feature pills */}
      <div className="flex flex-wrap justify-center gap-3 text-sm">
        {[
          "DAO Governance",
          "USDC Payments",
          "ENS Identities",
          "On-chain Voting",
          "Permissionless",
        ].map((f) => (
          <span
            key={f}
            className="px-3 py-1 rounded-full bg-gray-800 border border-gray-700 text-gray-300"
          >
            {f}
          </span>
        ))}
      </div>

      {/* CTA */}
      {isConnected ? (
        <div className="flex gap-4">
          <Link
            href="/dashboard"
            className="px-6 py-3 rounded-lg bg-indigo-600 hover:bg-indigo-500 font-medium transition-colors"
          >
            Go to Dashboard
          </Link>
          <Link
            href="/vault/new"
            className="px-6 py-3 rounded-lg border border-indigo-500 text-indigo-400 hover:bg-indigo-500/10 font-medium transition-colors"
          >
            Create a Vault
          </Link>
        </div>
      ) : (
        <div className="flex flex-col items-center gap-3">
          <p className="text-gray-500 text-sm">Connect your wallet to get started</p>
          <ConnectButton />
        </div>
      )}

      {/* How it works */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mt-8 w-full max-w-3xl">
        {[
          {
            step: "1",
            title: "Create a Vault",
            desc:  "Set up members and their percentage shares. Deploy in one transaction.",
          },
          {
            step: "2",
            title: "Govern Together",
            desc:  "Propose and vote on adding members or changing shares. 66% quorum required.",
          },
          {
            step: "3",
            title: "Distribute",
            desc:  "Deposit USDC into the vault and distribute it instantly to all members.",
          },
        ].map((item) => (
          <div key={item.step} className="bg-gray-900 border border-gray-800 rounded-xl p-5 text-left">
            <div className="w-7 h-7 rounded-full bg-indigo-600 text-white text-sm font-bold flex items-center justify-center mb-3">
              {item.step}
            </div>
            <h3 className="font-semibold mb-1">{item.title}</h3>
            <p className="text-sm text-gray-400">{item.desc}</p>
          </div>
        ))}
      </div>
    </div>
  );
}
