"use client";

import { useState }    from "react";
import { useWriteContract } from "wagmi";
import { useProposals, useProposalCount, useHasVoted, type Proposal } from "@/hooks/useProposals";
import { useVaultMembers } from "@/hooks/useVaults";
import { useIsCorrectNetwork } from "@/components/network-guard";
import { MEMBER_DAO_ABI } from "@/lib/contracts";
import { sepolia } from "wagmi/chains";

interface Props {
  vaultAddress: `0x${string}`;
  daoAddress?:  `0x${string}`;
  wallet?:      `0x${string}`;
  isMember:     boolean;
  memberCount:  number;
}

export function ProposalsTab({ vaultAddress, daoAddress, wallet, isMember, memberCount }: Props) {
  const [showForm, setShowForm] = useState(false);

  const { data: countRaw }           = useProposalCount(daoAddress);
  const count                        = Number(countRaw ?? 0n);
  const { proposals, refetch }       = useProposals(daoAddress, count);
  const { members }                  = useVaultMembers(vaultAddress);

  const open    = proposals.filter((p) => !p.executed && Date.now() / 1000 < Number(p.deadline));
  const closed  = proposals.filter((p) =>  p.executed || Date.now() / 1000 >= Number(p.deadline));

  return (
    <div className="flex flex-col gap-5">
      {/* Header */}
      <div className="flex items-center justify-between">
        <h2 className="font-semibold text-lg">Proposals</h2>
        {isMember && (
          <button
            onClick={() => setShowForm(!showForm)}
            className="px-3 py-1.5 rounded-lg bg-indigo-600 hover:bg-indigo-500 text-sm font-medium transition-colors"
          >
            {showForm ? "Cancel" : "+ New Proposal"}
          </button>
        )}
      </div>

      {/* New proposal form */}
      {showForm && daoAddress && (
        <ProposalForm
          daoAddress={daoAddress}
          members={members}
          onSuccess={() => { setShowForm(false); refetch(); }}
        />
      )}

      {/* Open proposals */}
      {open.length > 0 && (
        <Section title="Open">
          {open.map((p) => (
            <ProposalCard
              key={p.id}
              proposal={p}
              daoAddress={daoAddress!}
              wallet={wallet}
              isMember={isMember}
              totalMembers={memberCount}
              onAction={refetch}
            />
          ))}
        </Section>
      )}

      {/* Closed proposals */}
      {closed.length > 0 && (
        <Section title="Closed">
          {closed.map((p) => (
            <ProposalCard
              key={p.id}
              proposal={p}
              daoAddress={daoAddress!}
              wallet={wallet}
              isMember={isMember}
              totalMembers={memberCount}
              onAction={refetch}
            />
          ))}
        </Section>
      )}

      {proposals.length === 0 && !showForm && (
        <p className="text-gray-500 text-sm text-center py-10">No proposals yet.</p>
      )}
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div>
      <h3 className="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3">{title}</h3>
      <div className="flex flex-col gap-3">{children}</div>
    </div>
  );
}

function ProposalCard({
  proposal, daoAddress, wallet, isMember, totalMembers, onAction,
}: {
  proposal:     Proposal;
  daoAddress:   `0x${string}`;
  wallet?:      `0x${string}`;
  isMember:     boolean;
  totalMembers: number;
  onAction:     () => void;
}) {
  const { data: votedRaw }       = useHasVoted(daoAddress, proposal.id, wallet);
  const voted                    = votedRaw as boolean | undefined;
  const isCorrectNetwork         = useIsCorrectNetwork();
  const { writeContractAsync }   = useWriteContract();
  const [busyState, setBusy]     = useState(false);
  const busy                     = busyState || !isCorrectNetwork;

  const isOpen     = !proposal.executed && Date.now() / 1000 < Number(proposal.deadline);
  const canExecute = !proposal.executed && Date.now() / 1000 >= Number(proposal.deadline);
  const yes        = Number(proposal.yesVotes);
  const no         = Number(proposal.noVotes);
  const total      = yes + no;
  const quorum     = totalMembers > 0 ? (yes * 100) / totalMembers : 0;
  const deadline   = new Date(Number(proposal.deadline) * 1000);
  const typeLabel  = proposal.proposalType === 0 ? "Add Member" : "Repartition";

  async function vote(support: boolean) {
    setBusy(true);
    try {
      await writeContractAsync({
        address:      daoAddress,
        abi:          MEMBER_DAO_ABI,
        functionName: "vote",
        args:         [BigInt(proposal.id), support],
        chainId:      sepolia.id,
      });
      await new Promise((r) => setTimeout(r, 4000));
      onAction();
    } catch (e) { console.error(e); }
    finally { setBusy(false); }
  }

  async function execute() {
    setBusy(true);
    try {
      await writeContractAsync({
        address:      daoAddress,
        abi:          MEMBER_DAO_ABI,
        functionName: "executeProposal",
        args:         [BigInt(proposal.id)],
        chainId:      sepolia.id,
      });
      await new Promise((r) => setTimeout(r, 4000));
      onAction();
    } catch (e) { console.error(e); }
    finally { setBusy(false); }
  }

  return (
    <div className="bg-gray-900 border border-gray-800 rounded-xl p-4">
      <div className="flex items-start justify-between mb-2">
        <div>
          <span className="text-xs px-2 py-0.5 rounded bg-gray-800 text-gray-400 mr-2">{typeLabel}</span>
          {proposal.proposalType === 0 && (
            <span className="text-sm font-mono text-gray-300">
              {proposal.newMember.slice(0, 8)}…{proposal.newMember.slice(-4)}
              {proposal.label && ` (${proposal.label})`}
            </span>
          )}
        </div>
        <span className={`text-xs px-2 py-0.5 rounded-full ${
          isOpen     ? "bg-green-900 text-green-300 border border-green-700"
          : proposal.executed ? "bg-gray-800 text-gray-400"
          : "bg-yellow-900 text-yellow-300 border border-yellow-700"
        }`}>
          {isOpen ? "Open" : proposal.executed ? "Executed" : "Pending execution"}
        </span>
      </div>

      {/* Vote bar */}
      <div className="my-3">
        <div className="flex justify-between text-xs text-gray-500 mb-1">
          <span>Yes: {yes}</span>
          <span>{quorum.toFixed(0)}% / 66% quorum</span>
          <span>No: {no}</span>
        </div>
        <div className="h-2 rounded-full bg-gray-800 overflow-hidden">
          {total > 0 && (
            <div
              className="h-full bg-indigo-500 rounded-full"
              style={{ width: `${(yes / total) * 100}%` }}
            />
          )}
        </div>
      </div>

      <p className="text-xs text-gray-500 mb-3">
        Deadline: {deadline.toLocaleString()}
      </p>

      {/* Actions */}
      <div className="flex gap-2">
        {isOpen && isMember && !voted && (
          <>
            <button onClick={() => vote(true)}  disabled={busy} className="px-3 py-1.5 rounded-lg bg-green-800 hover:bg-green-700 disabled:opacity-50 text-xs font-medium transition-colors">
              Vote Yes
            </button>
            <button onClick={() => vote(false)} disabled={busy} className="px-3 py-1.5 rounded-lg bg-red-900 hover:bg-red-800 disabled:opacity-50 text-xs font-medium transition-colors">
              Vote No
            </button>
          </>
        )}
        {isOpen && voted && (
          <span className="text-xs text-gray-500 italic">You already voted</span>
        )}
        {canExecute && (
          <button onClick={execute} disabled={busy} className="px-3 py-1.5 rounded-lg bg-indigo-700 hover:bg-indigo-600 disabled:opacity-50 text-xs font-medium transition-colors">
            {busy ? "Executing…" : "Execute"}
          </button>
        )}
      </div>
    </div>
  );
}

function ProposalForm({
  daoAddress, members, onSuccess,
}: {
  daoAddress: `0x${string}`;
  members:    { address: `0x${string}`; percentage: number }[];
  onSuccess:  () => void;
}) {
  const [type, setType]           = useState<"addMember" | "repartition">("addMember");
  const [newAddr, setNewAddr]     = useState("");
  const [label, setLabel]         = useState("");
  const [percentages, setPercentages] = useState<string[]>(
    () => members.map((m) => m.percentage.toString())
  );
  const [newPct, setNewPct]       = useState("0");
  const [busy, setBusy]           = useState(false);
  const { writeContractAsync }    = useWriteContract();

  const allPcts = type === "addMember"
    ? [...percentages, newPct]
    : percentages;

  const sum = allPcts.reduce((a, b) => a + Number(b || 0), 0);

  async function submit() {
    setBusy(true);
    try {
      const pctsBig = allPcts.map((p) => BigInt(p || 0));
      if (type === "addMember") {
        await writeContractAsync({
          address:      daoAddress,
          abi:          MEMBER_DAO_ABI,
          functionName: "proposeMember",
          args:         [newAddr as `0x${string}`, pctsBig, label],
          chainId:      sepolia.id,
        });
      } else {
        await writeContractAsync({
          address:      daoAddress,
          abi:          MEMBER_DAO_ABI,
          functionName: "proposeRepartition",
          args:         [pctsBig],
          chainId:      sepolia.id,
        });
      }
      await new Promise((r) => setTimeout(r, 4000));
      onSuccess();
    } catch (e) { console.error(e); }
    finally { setBusy(false); }
  }

  return (
    <div className="bg-gray-900 border border-indigo-800 rounded-xl p-5 flex flex-col gap-4">
      <h3 className="font-semibold">New Proposal</h3>

      {/* Type toggle */}
      <div className="flex gap-2">
        {(["addMember", "repartition"] as const).map((t) => (
          <button
            key={t}
            onClick={() => setType(t)}
            className={`px-3 py-1.5 rounded-lg text-sm transition-colors ${
              type === t ? "bg-indigo-600 text-white" : "bg-gray-800 text-gray-400 hover:text-gray-200"
            }`}
          >
            {t === "addMember" ? "Add Member" : "Repartition"}
          </button>
        ))}
      </div>

      {/* New member inputs */}
      {type === "addMember" && (
        <div className="flex gap-2">
          <input
            type="text"
            placeholder="New member address (0x…)"
            value={newAddr}
            onChange={(e) => setNewAddr(e.target.value)}
            className="flex-1 px-3 py-2 rounded-lg bg-gray-800 border border-gray-700 text-sm focus:outline-none focus:border-indigo-500"
          />
          <input
            type="text"
            placeholder="ENS label (optional)"
            value={label}
            onChange={(e) => setLabel(e.target.value)}
            className="w-36 px-3 py-2 rounded-lg bg-gray-800 border border-gray-700 text-sm focus:outline-none focus:border-indigo-500"
          />
        </div>
      )}

      {/* Percentages */}
      <div className="flex flex-col gap-2">
        <p className="text-xs text-gray-500">
          Percentages — must sum to 100 (currently: <span className={sum === 100 ? "text-green-400" : "text-red-400"}>{sum}</span>)
        </p>
        {members.map((m, i) => (
          <div key={m.address} className="flex items-center gap-3">
            <span className="font-mono text-xs text-gray-400 w-32 truncate">
              {m.address.slice(0, 8)}…
            </span>
            <input
              type="number"
              value={percentages[i] ?? ""}
              onChange={(e) => {
                const next = [...percentages];
                next[i] = e.target.value;
                setPercentages(next);
              }}
              className="w-20 px-2 py-1 rounded-lg bg-gray-800 border border-gray-700 text-sm focus:outline-none focus:border-indigo-500"
            />
            <span className="text-gray-500 text-sm">%</span>
          </div>
        ))}
        {type === "addMember" && (
          <div className="flex items-center gap-3">
            <span className="font-mono text-xs text-indigo-400 w-32 truncate">new member</span>
            <input
              type="number"
              value={newPct}
              onChange={(e) => setNewPct(e.target.value)}
              className="w-20 px-2 py-1 rounded-lg bg-gray-800 border border-indigo-700 text-sm focus:outline-none focus:border-indigo-500"
            />
            <span className="text-gray-500 text-sm">%</span>
          </div>
        )}
      </div>

      <button
        onClick={submit}
        disabled={busy || sum !== 100}
        className="px-4 py-2 rounded-lg bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed text-sm font-medium transition-colors self-end"
      >
        {busy ? "Submitting…" : "Submit Proposal"}
      </button>
    </div>
  );
}
