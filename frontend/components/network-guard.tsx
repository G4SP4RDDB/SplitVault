"use client";

import { useChainId, useSwitchChain, useAccount } from "wagmi";
import { sepolia } from "wagmi/chains";

export function NetworkGuard() {
  const { isConnected }          = useAccount();
  const chainId                  = useChainId();
  const { switchChain, isPending } = useSwitchChain();

  if (!isConnected || chainId === sepolia.id) return null;

  return (
    <div className="bg-yellow-900/80 border-b border-yellow-700 px-4 py-2 flex items-center justify-between text-sm">
      <span className="text-yellow-200">
        Wrong network detected. Please switch to <strong>Sepolia</strong>.
      </span>
      <button
        onClick={() => switchChain({ chainId: sepolia.id })}
        disabled={isPending}
        className="ml-4 px-3 py-1 rounded-lg bg-yellow-600 hover:bg-yellow-500 disabled:opacity-50 text-white text-xs font-medium transition-colors"
      >
        {isPending ? "Switching…" : "Switch to Sepolia"}
      </button>
    </div>
  );
}

// Hook to check if user is on the right network
export function useIsCorrectNetwork() {
  const chainId = useChainId();
  return chainId === sepolia.id;
}
