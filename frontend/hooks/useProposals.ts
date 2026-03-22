"use client";

import { useReadContract, useReadContracts } from "wagmi";
import { MEMBER_DAO_ABI } from "@/lib/contracts";

export type Proposal = {
  id:           number;
  proposalType: number; // 0 = AddMember, 1 = Repartition
  proposer:     `0x${string}`;
  newMember:    `0x${string}`;
  newPercentages: bigint[];
  deadline:     bigint;
  yesVotes:     bigint;
  noVotes:      bigint;
  executed:     boolean;
  snapshotMemberCount: bigint;
  label:        string;
};

// Returns total proposal count for a DAO
export function useProposalCount(daoAddress?: `0x${string}`) {
  return useReadContract({
    address:      daoAddress,
    abi:          MEMBER_DAO_ABI,
    functionName: "proposalCount",
    query: { enabled: !!daoAddress },
  });
}

// Fetches all proposals for a DAO
export function useProposals(daoAddress?: `0x${string}`, count?: number) {
  const ids = count ? Array.from({ length: count }, (_, i) => i) : [];

  const contracts = ids.map((id) => ({
    address:      daoAddress,
    abi:          MEMBER_DAO_ABI,
    functionName: "getProposal",
    args:         [BigInt(id)],
  }));

  const { data, isLoading, refetch } = useReadContracts({
    contracts: contracts as any,
    query:     { enabled: !!daoAddress && count !== undefined && count > 0 },
  });

  const proposals: Proposal[] = [];

  if (data) {
    for (let i = 0; i < ids.length; i++) {
      const r = data[i];
      if (r.status !== "success") continue;
      const [
        proposalType, proposer, newMember, newPercentages,
        deadline, yesVotes, noVotes, executed, snapshotMemberCount, label,
      ] = r.result as any[];
      proposals.push({
        id: i,
        proposalType: Number(proposalType),
        proposer, newMember, newPercentages,
        deadline, yesVotes, noVotes, executed, snapshotMemberCount, label,
      });
    }
  }

  return { proposals, isLoading, refetch };
}

// Returns whether a given address has voted on a proposal
export function useHasVoted(daoAddress?: `0x${string}`, proposalId?: number, voter?: `0x${string}`) {
  return useReadContract({
    address:      daoAddress,
    abi:          MEMBER_DAO_ABI,
    functionName: "hasVoted",
    args:         proposalId !== undefined && voter ? [BigInt(proposalId), voter] : undefined,
    query:        { enabled: !!daoAddress && proposalId !== undefined && !!voter },
  });
}
