"use client";

import { useReadContract, useReadContracts } from "wagmi";
import { ADDRESSES, VAULT_REGISTRY_ABI, SPLIT_VAULT_ABI } from "@/lib/contracts";

// Returns all vault addresses from the registry
export function useAllVaults() {
  return useReadContract({
    address: ADDRESSES.vaultRegistry,
    abi:     VAULT_REGISTRY_ABI,
    functionName: "getAllVaults",
  });
}

// Given a list of vault addresses + a wallet, returns only vaults where the wallet is a member
export function useMyVaults(allVaults: `0x${string}`[], walletAddress?: `0x${string}`) {
  const contracts = allVaults.map((vault) => ({
    address:      vault,
    abi:          SPLIT_VAULT_ABI,
    functionName: "getMembers",
  }));

  const { data, isLoading } = useReadContracts({ contracts: contracts as any });

  if (!walletAddress || !data) return { vaults: [], isLoading };

  const vaults = allVaults.filter((_, i) => {
    const result = data[i];
    if (result.status !== "success") return false;
    const [addrs] = result.result as [`0x${string}`[], bigint[]];
    return addrs.some((a) => a.toLowerCase() === walletAddress.toLowerCase());
  });

  return { vaults, isLoading };
}

// Returns members + percentages for a single vault
export function useVaultMembers(vaultAddress?: `0x${string}`) {
  const { data, isLoading, refetch } = useReadContract({
    address:      vaultAddress,
    abi:          SPLIT_VAULT_ABI,
    functionName: "getMembers",
    query: { enabled: !!vaultAddress },
  });

  const members: { address: `0x${string}`; percentage: number }[] = [];
  if (data) {
    const [addrs, pcts] = data as [`0x${string}`[], bigint[]];
    for (let i = 0; i < addrs.length; i++) {
      members.push({ address: addrs[i], percentage: Number(pcts[i]) });
    }
  }

  return { members, isLoading, refetch };
}

// Returns vault owner (the DAO address)
export function useVaultOwner(vaultAddress?: `0x${string}`) {
  return useReadContract({
    address:      vaultAddress,
    abi:          SPLIT_VAULT_ABI,
    functionName: "owner",
    query: { enabled: !!vaultAddress },
  });
}
