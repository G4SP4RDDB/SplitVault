"use client";

import { useState }        from "react";
import { useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { sepolia } from "wagmi/chains";
import { useVaultMembers } from "@/hooks/useVaults";
import { useIsCorrectNetwork } from "@/components/network-guard";
import {
  ADDRESSES, ERC20_ABI, SPLIT_VAULT_ABI,
  formatUsdc, parseUsdc, USDC_UNIT,
} from "@/lib/contracts";

interface Props {
  vaultAddress: `0x${string}`;
  wallet?:      `0x${string}`;
  isMember:     boolean;
}

export function OverviewTab({ vaultAddress, wallet, isMember }: Props) {
  const { members, refetch: refetchMembers } = useVaultMembers(vaultAddress);

  const { data: balanceRaw, refetch: refetchBalance } = useReadContract({
    address:      ADDRESSES.usdc,
    abi:          ERC20_ABI,
    functionName: "balanceOf",
    args:         [vaultAddress],
  });

  const { data: allowanceRaw, refetch: refetchAllowance } = useReadContract({
    address:      ADDRESSES.usdc,
    abi:          ERC20_ABI,
    functionName: "allowance",
    args:         wallet ? [wallet, vaultAddress] : undefined,
    query:        { enabled: !!wallet },
  });

  const balance   = (balanceRaw  as bigint | undefined) ?? 0n;
  const allowance = (allowanceRaw as bigint | undefined) ?? 0n;

  const isCorrectNetwork = useIsCorrectNetwork();
  const [depositAmount, setDepositAmount] = useState("");
  const [step, setStep]   = useState<"idle" | "approving" | "depositing" | "distributing">("idle");
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>();

  const { writeContractAsync } = useWriteContract();
  const { isLoading: txPending } = useWaitForTransactionReceipt({ hash: txHash });

  const refetchAll = () => {
    refetchBalance();
    refetchMembers();
    refetchAllowance();
  };

  async function handleDeposit() {
    if (!depositAmount || !wallet) return;
    try {
      const amount = parseUsdc(depositAmount);

      if (allowance < amount) {
        setStep("approving");
        const approveTx = await writeContractAsync({
          address:      ADDRESSES.usdc,
          abi:          ERC20_ABI,
          functionName: "approve",
          args:         [vaultAddress, amount],
          chainId:      sepolia.id,
        });
        setTxHash(approveTx);
        // Wait for approval
        await new Promise((r) => setTimeout(r, 4000));
      }

      setStep("depositing");
      const depositTx = await writeContractAsync({
        address:      vaultAddress,
        abi:          SPLIT_VAULT_ABI,
        functionName: "deposit",
        args:         [amount],
        chainId:      sepolia.id,
      });
      setTxHash(depositTx);
      await new Promise((r) => setTimeout(r, 4000));
      setDepositAmount("");
      refetchAll();
    } catch (e: any) {
      console.error(e);
    } finally {
      setStep("idle");
      setTxHash(undefined);
    }
  }

  async function handleDistribute() {
    try {
      setStep("distributing");
      const tx = await writeContractAsync({
        address:      vaultAddress,
        abi:          SPLIT_VAULT_ABI,
        functionName: "distribute",
        chainId:      sepolia.id,
      });
      setTxHash(tx);
      await new Promise((r) => setTimeout(r, 4000));
      refetchAll();
    } catch (e: any) {
      console.error(e);
    } finally {
      setStep("idle");
      setTxHash(undefined);
    }
  }

  const busy = step !== "idle" || txPending || !isCorrectNetwork;

  return (
    <div className="flex flex-col gap-6">
      {/* Balance + actions */}
      <div className="bg-gray-900 border border-gray-800 rounded-xl p-5">
        <p className="text-sm text-gray-400 mb-1">Vault Balance</p>
        <p className="text-3xl font-bold mb-4">{formatUsdc(balance)} <span className="text-gray-400 text-xl">USDC</span></p>

        <div className="flex flex-col sm:flex-row gap-3">
          {/* Deposit */}
          <div className="flex gap-2 flex-1">
            <input
              type="number"
              placeholder="Amount (USDC)"
              value={depositAmount}
              onChange={(e) => setDepositAmount(e.target.value)}
              className="flex-1 px-3 py-2 rounded-lg bg-gray-800 border border-gray-700 text-sm focus:outline-none focus:border-indigo-500"
            />
            <button
              onClick={handleDeposit}
              disabled={busy || !depositAmount}
              className="px-4 py-2 rounded-lg bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed text-sm font-medium transition-colors"
            >
              {step === "approving" ? "Approving…" : step === "depositing" ? "Depositing…" : "Deposit"}
            </button>
          </div>

          {/* Distribute */}
          <button
            onClick={handleDistribute}
            disabled={busy || balance === 0n}
            className="px-4 py-2 rounded-lg bg-green-700 hover:bg-green-600 disabled:opacity-50 disabled:cursor-not-allowed text-sm font-medium transition-colors"
          >
            {step === "distributing" ? "Distributing…" : "Distribute"}
          </button>
        </div>

        {step !== "idle" && (
          <p className="text-xs text-indigo-400 mt-2 animate-pulse">
            {step === "approving"    ? "Waiting for USDC approval…"
             : step === "depositing" ? "Depositing into vault…"
             : "Distributing to members…"}
          </p>
        )}
      </div>

      {/* Members table */}
      <div className="bg-gray-900 border border-gray-800 rounded-xl overflow-hidden">
        <div className="px-5 py-4 border-b border-gray-800">
          <h2 className="font-semibold">Members ({members.length})</h2>
        </div>
        {members.length === 0 ? (
          <p className="px-5 py-4 text-gray-500 text-sm">Loading…</p>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-gray-500 text-xs border-b border-gray-800">
                <th className="px-5 py-3 font-medium">Address</th>
                <th className="px-5 py-3 font-medium">Share</th>
                <th className="px-5 py-3 font-medium text-right">≈ USDC</th>
              </tr>
            </thead>
            <tbody>
              {members.map((m) => {
                const isMe = wallet?.toLowerCase() === m.address.toLowerCase();
                const share = (balance * BigInt(m.percentage)) / 100n;
                return (
                  <tr key={m.address} className={`border-b border-gray-800/50 ${isMe ? "bg-indigo-900/10" : ""}`}>
                    <td className="px-5 py-3 font-mono text-xs text-gray-300">
                      {m.address.slice(0, 8)}…{m.address.slice(-6)}
                      {isMe && <span className="ml-2 text-indigo-400 text-xs">(you)</span>}
                    </td>
                    <td className="px-5 py-3">
                      <div className="flex items-center gap-2">
                        <div className="h-1.5 rounded-full bg-indigo-600" style={{ width: `${m.percentage}%`, maxWidth: "80px" }} />
                        <span>{m.percentage}%</span>
                      </div>
                    </td>
                    <td className="px-5 py-3 text-right text-gray-300">
                      {formatUsdc(share)}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
