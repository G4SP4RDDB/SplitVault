"use client";

import { useState, useEffect } from "react";
import { useRouter }     from "next/navigation";
import { useAccount, useWriteContract, useWaitForTransactionReceipt, useReadContract } from "wagmi";
import { isAddress }     from "viem";
import {
  ADDRESSES, VAULT_FACTORY_ABI, ENS_MANAGER_ABI,
  VOTING_DURATION_OPTIONS,
} from "@/lib/contracts";
import { sepolia } from "wagmi/chains";

type Step = "name" | "members" | "duration" | "review";

interface MemberEntry {
  address:    string;
  percentage: number;
}

export default function NewVaultPage() {
  const router                   = useRouter();
  const { address, isConnected } = useAccount();
  const [step, setStep]          = useState<Step>("name");
  const [label, setLabel]        = useState("");
  const [members, setMembers]    = useState<MemberEntry[]>([
    { address: address ?? "", percentage: 100 },
  ]);
  const [votingDuration, setVotingDuration] = useState(86400);
  const [busy, setBusy]          = useState(false);
  const [txHash, setTxHash]      = useState<`0x${string}` | undefined>();

  const { writeContractAsync } = useWriteContract();
  const { isLoading: waiting, isSuccess: txConfirmed } = useWaitForTransactionReceipt({ hash: txHash });

  useEffect(() => {
    if (txConfirmed) router.push("/dashboard");
  }, [txConfirmed, router]);

  // ── ENS label availability ──────────────────────────────────────────────────

  const trimmedLabel = label.trim().toLowerCase();
  const { data: availableRaw, isLoading: checkingAvail } = useReadContract({
    address:      ADDRESSES.ensManager,
    abi:          ENS_MANAGER_ABI,
    functionName: "isLabelAvailable",
    args:         [trimmedLabel],
    query:        { enabled: trimmedLabel.length > 0 },
  });
  const labelAvailable = availableRaw as boolean | undefined;
  const labelValid     = trimmedLabel.length > 0 && labelAvailable === true;

  const pctSum = members.reduce((a, m) => a + m.percentage, 0);

  // ── Step 1 helpers ──────────────────────────────────────────────────────────

  function addMember() {
    setMembers([...members, { address: "", percentage: 0 }]);
  }

  function removeMember(i: number) {
    setMembers(members.filter((_, idx) => idx !== i));
  }

  function updateMember(i: number, field: keyof MemberEntry, value: string | number) {
    const next = [...members];
    (next[i] as any)[field] = value;
    setMembers(next);
  }

  function autoBalance() {
    const even = Math.floor(100 / members.length);
    const rem  = 100 - even * members.length;
    setMembers(members.map((m, i) => ({ ...m, percentage: even + (i === 0 ? rem : 0) })));
  }

  // ── Validation ──────────────────────────────────────────────────────────────

  const membersValid =
    members.length > 0 &&
    pctSum === 100 &&
    members.every((m) => isAddress(m.address) && m.percentage > 0) &&
    new Set(members.map((m) => m.address.toLowerCase())).size === members.length;

  // ── Deploy ──────────────────────────────────────────────────────────────────

  async function deploy() {
    setBusy(true);
    try {
      const addrs = members.map((m) => m.address as `0x${string}`);
      const pcts  = members.map((m) => BigInt(m.percentage));

      const tx = await writeContractAsync({
        address:      ADDRESSES.vaultFactory,
        abi:          VAULT_FACTORY_ABI,
        functionName: "createVault",
        args:         [addrs, pcts, BigInt(votingDuration), trimmedLabel],
        chain:        sepolia,
      });
      setTxHash(tx);
    } catch (e) {
      console.error(e);
      setBusy(false);
    }
  }

  if (!isConnected) {
    return (
      <div className="text-center py-20 text-gray-400">
        Connect your wallet to create a vault.
      </div>
    );
  }

  const STEPS: Step[] = ["name", "members", "duration", "review"];
  const STEP_LABELS   = { name: "Name", members: "Members", duration: "Voting", review: "Review" };

  return (
    <div className="max-w-xl mx-auto flex flex-col gap-6">
      <div>
        <h1 className="text-2xl font-bold">Create a Vault</h1>
        <p className="text-gray-400 text-sm mt-1">
          Choose a name, set up members, shares, and voting rules. One transaction deploys everything.
        </p>
      </div>

      {/* Step indicator */}
      <div className="flex items-center gap-2 text-sm">
        {STEPS.map((s, i) => (
          <div key={s} className="flex items-center gap-2">
            <div className={`w-6 h-6 rounded-full text-xs flex items-center justify-center font-bold ${
              step === s ? "bg-indigo-600 text-white" : "bg-gray-800 text-gray-400"
            }`}>
              {i + 1}
            </div>
            <span className={step === s ? "text-white" : "text-gray-500"}>
              {STEP_LABELS[s]}
            </span>
            {i < STEPS.length - 1 && <span className="text-gray-700">→</span>}
          </div>
        ))}
      </div>

      {/* ── Step 0: Name ── */}
      {step === "name" && (
        <div className="bg-gray-900 border border-gray-800 rounded-xl p-5 flex flex-col gap-4">
          <div>
            <h2 className="font-semibold">Vault Name</h2>
            <p className="text-sm text-gray-400 mt-1">
              Choose a unique ENS subdomain for this vault. It will be registered as{" "}
              <span className="font-mono text-indigo-400">
                {trimmedLabel || "yourname"}.vaulthack.eth
              </span>
            </p>
          </div>

          <div className="flex flex-col gap-2">
            <div className="flex gap-2 items-center">
              <input
                type="text"
                placeholder="e.g. teamvault"
                value={label}
                onChange={(e) => setLabel(e.target.value.toLowerCase().replace(/[^a-z0-9-]/g, ""))}
                className="flex-1 px-3 py-2 rounded-lg bg-gray-800 border border-gray-700 text-sm focus:outline-none focus:border-indigo-500 font-mono"
              />
              <span className="text-gray-500 text-sm whitespace-nowrap">.vaulthack.eth</span>
            </div>

            {trimmedLabel.length > 0 && (
              <p className="text-xs pl-1">
                {checkingAvail ? (
                  <span className="text-gray-500">Checking availability…</span>
                ) : labelAvailable === true ? (
                  <span className="text-green-400">Available</span>
                ) : labelAvailable === false ? (
                  <span className="text-red-400">Already taken</span>
                ) : null}
              </p>
            )}
          </div>

          <button
            onClick={() => setStep("members")}
            disabled={!labelValid}
            className="mt-2 px-4 py-2 rounded-lg bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed text-sm font-medium transition-colors self-end"
          >
            Next →
          </button>
        </div>
      )}

      {/* ── Step 1: Members ── */}
      {step === "members" && (
        <div className="bg-gray-900 border border-gray-800 rounded-xl p-5 flex flex-col gap-4">
          <div className="flex items-center justify-between">
            <h2 className="font-semibold">Members & Shares</h2>
            <button onClick={autoBalance} className="text-xs text-indigo-400 hover:underline">
              Auto-balance
            </button>
          </div>

          {members.map((m, i) => (
            <div key={i} className="flex gap-2 items-center">
              <input
                type="text"
                placeholder="0x… address"
                value={m.address}
                onChange={(e) => updateMember(i, "address", e.target.value)}
                className={`flex-1 px-3 py-2 rounded-lg bg-gray-800 border text-sm focus:outline-none focus:border-indigo-500 ${
                  m.address && !isAddress(m.address) ? "border-red-700" : "border-gray-700"
                }`}
              />
              <div className="flex items-center gap-1">
                <input
                  type="number"
                  min="1" max="100"
                  value={m.percentage}
                  onChange={(e) => updateMember(i, "percentage", Number(e.target.value))}
                  className="w-16 px-2 py-2 rounded-lg bg-gray-800 border border-gray-700 text-sm focus:outline-none focus:border-indigo-500 text-center"
                />
                <span className="text-gray-500 text-sm">%</span>
              </div>
              {members.length > 1 && (
                <button onClick={() => removeMember(i)} className="text-gray-500 hover:text-red-400 text-lg leading-none">
                  ×
                </button>
              )}
            </div>
          ))}

          <div className="flex items-center justify-between pt-1">
            <button onClick={addMember} className="text-sm text-indigo-400 hover:underline">
              + Add member
            </button>
            <span className={`text-sm font-medium ${pctSum === 100 ? "text-green-400" : "text-red-400"}`}>
              Total: {pctSum}%
            </span>
          </div>

          <div className="flex gap-3 self-end">
            <button onClick={() => setStep("name")} className="px-4 py-2 rounded-lg bg-gray-800 hover:bg-gray-700 text-sm transition-colors">
              ← Back
            </button>
            <button
              onClick={() => setStep("duration")}
              disabled={!membersValid}
              className="px-4 py-2 rounded-lg bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed text-sm font-medium transition-colors"
            >
              Next →
            </button>
          </div>
        </div>
      )}

      {/* ── Step 2: Voting Duration ── */}
      {step === "duration" && (
        <div className="bg-gray-900 border border-gray-800 rounded-xl p-5 flex flex-col gap-4">
          <h2 className="font-semibold">Voting Duration</h2>
          <p className="text-sm text-gray-400">
            How long members have to vote on proposals before they can be executed.
          </p>
          <div className="flex flex-col gap-2">
            {VOTING_DURATION_OPTIONS.map((opt) => (
              <label key={opt.value} className="flex items-center gap-3 cursor-pointer p-3 rounded-lg hover:bg-gray-800 transition-colors">
                <input
                  type="radio"
                  name="duration"
                  value={opt.value}
                  checked={votingDuration === opt.value}
                  onChange={() => setVotingDuration(opt.value)}
                  className="accent-indigo-500"
                />
                <span className="text-sm">{opt.label}</span>
              </label>
            ))}
          </div>
          <div className="flex gap-3 self-end">
            <button onClick={() => setStep("members")} className="px-4 py-2 rounded-lg bg-gray-800 hover:bg-gray-700 text-sm transition-colors">
              ← Back
            </button>
            <button onClick={() => setStep("review")} className="px-4 py-2 rounded-lg bg-indigo-600 hover:bg-indigo-500 text-sm font-medium transition-colors">
              Next →
            </button>
          </div>
        </div>
      )}

      {/* ── Step 3: Review ── */}
      {step === "review" && (
        <div className="bg-gray-900 border border-gray-800 rounded-xl p-5 flex flex-col gap-5">
          <h2 className="font-semibold">Review & Deploy</h2>

          <div className="flex justify-between text-sm border-b border-gray-800 pb-3">
            <span className="text-gray-400">ENS name</span>
            <span className="font-mono text-indigo-400">{trimmedLabel}.vaulthack.eth</span>
          </div>

          <div>
            <p className="text-xs text-gray-500 uppercase tracking-wider mb-2">Members</p>
            <div className="flex flex-col gap-1">
              {members.map((m) => (
                <div key={m.address} className="flex justify-between text-sm">
                  <span className="font-mono text-gray-300">
                    {m.address.slice(0, 8)}…{m.address.slice(-6)}
                    {m.address.toLowerCase() === address?.toLowerCase() && (
                      <span className="ml-2 text-indigo-400 text-xs">(you)</span>
                    )}
                  </span>
                  <span className="font-medium">{m.percentage}%</span>
                </div>
              ))}
            </div>
          </div>

          <div className="flex justify-between text-sm border-t border-gray-800 pt-3">
            <span className="text-gray-400">Voting duration</span>
            <span>{VOTING_DURATION_OPTIONS.find((o) => o.value === votingDuration)?.label}</span>
          </div>

          <div className="flex justify-between text-sm">
            <span className="text-gray-400">Token</span>
            <span>USDC (Sepolia)</span>
          </div>

          <div className="text-xs text-gray-500 bg-gray-800 rounded-lg p-3">
            This will deploy a SplitVault + MemberDAO and register{" "}
            <span className="font-mono text-indigo-400">{trimmedLabel}.vaulthack.eth</span>{" "}
            in a single transaction. The DAO immediately becomes the vault owner — all future
            changes require a governance vote.
          </div>

          <div className="flex gap-3 self-end">
            <button onClick={() => setStep("duration")} className="px-4 py-2 rounded-lg bg-gray-800 hover:bg-gray-700 text-sm transition-colors">
              ← Back
            </button>
            <button
              onClick={deploy}
              disabled={busy || waiting}
              className="px-6 py-2 rounded-lg bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed text-sm font-medium transition-colors"
            >
              {busy ? "Deploying…" : "Deploy Vault"}
            </button>
          </div>

          {busy && (
            <p className="text-xs text-indigo-400 text-center animate-pulse">
              Waiting for transaction confirmation…
            </p>
          )}
        </div>
      )}
    </div>
  );
}
