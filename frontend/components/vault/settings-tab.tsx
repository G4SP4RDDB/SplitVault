"use client";

import { useState }              from "react";
import { useReadContract, useWriteContract } from "wagmi";
import { sepolia } from "wagmi/chains";
import { MEMBER_DAO_ABI, ENS_MANAGER_ABI }  from "@/lib/contracts";

interface Props {
  vaultAddress: `0x${string}`;
  daoAddress?:  `0x${string}`;
  isMember:     boolean;
}

export function SettingsTab({ vaultAddress, daoAddress, isMember }: Props) {
  const { data: ensManagerAddr, refetch } = useReadContract({
    address:      daoAddress,
    abi:          MEMBER_DAO_ABI,
    functionName: "ensManager",
    query:        { enabled: !!daoAddress },
  }) as { data: `0x${string}` | undefined; refetch: () => void };

  const { data: votingDuration } = useReadContract({
    address:      daoAddress,
    abi:          MEMBER_DAO_ABI,
    functionName: "votingDuration",
    query:        { enabled: !!daoAddress },
  });

  const [newEnsManager, setNewEnsManager] = useState("");
  const [busy, setBusy]                   = useState(false);
  const { writeContractAsync }            = useWriteContract();

  const hasENS = ensManagerAddr && ensManagerAddr !== "0x0000000000000000000000000000000000000000";

  const inviteLink = typeof window !== "undefined"
    ? `${window.location.origin}/invite/${vaultAddress}`
    : "";

  async function setENSManager() {
    if (!daoAddress) return;
    setBusy(true);
    try {
      await writeContractAsync({
        address:      daoAddress,
        abi:          MEMBER_DAO_ABI,
        functionName: "setENSManager",
        args:         [newEnsManager as `0x${string}`],
        chainId:      sepolia.id,
      });
      await new Promise((r) => setTimeout(r, 4000));
      setNewEnsManager("");
      refetch();
    } catch (e) { console.error(e); }
    finally { setBusy(false); }
  }

  function copy(text: string) {
    navigator.clipboard.writeText(text);
  }

  const durationSec = Number(votingDuration ?? 0n);
  const durationLabel =
    durationSec >= 604800 ? `${durationSec / 604800}w`
    : durationSec >= 86400 ? `${durationSec / 86400}d`
    : durationSec >= 3600  ? `${durationSec / 3600}h`
    : `${durationSec}s`;

  return (
    <div className="flex flex-col gap-5">
      {/* Addresses */}
      <Card title="Contract Addresses">
        <Row label="SplitVault" value={vaultAddress}     onCopy={() => copy(vaultAddress)} />
        {daoAddress && <Row label="MemberDAO"  value={daoAddress}    onCopy={() => copy(daoAddress)} />}
        {hasENS     && <Row label="ENSManager" value={ensManagerAddr} onCopy={() => copy(ensManagerAddr!)} />}
      </Card>

      {/* Voting */}
      <Card title="Governance">
        <div className="flex justify-between text-sm py-1">
          <span className="text-gray-400">Voting duration</span>
          <span className="font-mono">{durationLabel}</span>
        </div>
        <div className="flex justify-between text-sm py-1">
          <span className="text-gray-400">Quorum required</span>
          <span className="font-mono">66%</span>
        </div>
      </Card>

      {/* Invite link */}
      <Card title="Invite Link">
        <p className="text-xs text-gray-400 mb-2">
          Share this link to invite someone to view this vault. They can accept/decline membership proposals via governance.
        </p>
        <div className="flex gap-2">
          <input
            readOnly
            value={inviteLink}
            className="flex-1 px-3 py-2 rounded-lg bg-gray-800 border border-gray-700 text-xs font-mono text-gray-300 focus:outline-none"
          />
          <button
            onClick={() => copy(inviteLink)}
            className="px-3 py-2 rounded-lg bg-gray-700 hover:bg-gray-600 text-xs transition-colors"
          >
            Copy
          </button>
        </div>
      </Card>

      {/* ENS Manager */}
      {isMember && (
        <Card title="ENS Manager">
          {hasENS ? (
            <p className="text-sm text-gray-300 font-mono">
              {ensManagerAddr}
            </p>
          ) : (
            <p className="text-sm text-gray-500 mb-3">
              No ENSManager set. Deploy one separately and connect it here to enable subdomain registration when members are added.
            </p>
          )}
          <div className="flex gap-2 mt-3">
            <input
              type="text"
              placeholder="ENSManager address (0x…)"
              value={newEnsManager}
              onChange={(e) => setNewEnsManager(e.target.value)}
              className="flex-1 px-3 py-2 rounded-lg bg-gray-800 border border-gray-700 text-sm focus:outline-none focus:border-indigo-500"
            />
            <button
              onClick={setENSManager}
              disabled={busy || !newEnsManager}
              className="px-3 py-2 rounded-lg bg-indigo-700 hover:bg-indigo-600 disabled:opacity-50 text-sm transition-colors"
            >
              {busy ? "Saving…" : hasENS ? "Update" : "Set"}
            </button>
          </div>
        </Card>
      )}
    </div>
  );
}

function Card({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="bg-gray-900 border border-gray-800 rounded-xl overflow-hidden">
      <div className="px-5 py-3 border-b border-gray-800">
        <h3 className="text-sm font-semibold">{title}</h3>
      </div>
      <div className="px-5 py-4">{children}</div>
    </div>
  );
}

function Row({ label, value, onCopy }: { label: string; value: string; onCopy: () => void }) {
  return (
    <div className="flex items-center justify-between py-1.5 gap-3">
      <span className="text-xs text-gray-400 w-24 shrink-0">{label}</span>
      <span className="font-mono text-xs text-gray-300 truncate flex-1">{value}</span>
      <button onClick={onCopy} className="text-xs text-gray-500 hover:text-gray-200 shrink-0">Copy</button>
    </div>
  );
}
