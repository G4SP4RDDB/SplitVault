"use client";

import { useAccount, useConnect, useDisconnect, useChainId } from "wagmi";
import { sepolia } from "wagmi/chains";

export function ConnectButton() {
  const { address, isConnected, isConnecting } = useAccount();
  const { connect, connectors }                = useConnect();
  const { disconnect }                         = useDisconnect();
  const chainId                                = useChainId();

  const onWrongChain = isConnected && chainId !== sepolia.id;

  if (isConnected && address) {
    return (
      <div className="flex items-center gap-2">
        {onWrongChain ? (
          <span className="text-xs px-2 py-1 rounded-full bg-yellow-900 border border-yellow-700 text-yellow-300">
            Wrong network
          </span>
        ) : (
          <span className="text-xs px-2 py-1 rounded-full bg-green-900 border border-green-800 text-green-400">
            Sepolia
          </span>
        )}
        <span className="text-xs text-gray-400 font-mono hidden sm:block">
          {address.slice(0, 6)}…{address.slice(-4)}
        </span>
        <button
          onClick={() => disconnect()}
          className="px-3 py-1.5 rounded-lg bg-gray-800 hover:bg-gray-700 border border-gray-700 text-sm transition-colors"
        >
          Disconnect
        </button>
      </div>
    );
  }

  return (
    <button
      onClick={() => connect({ connector: connectors[0] })}
      disabled={isConnecting}
      className="px-4 py-1.5 rounded-lg bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 text-sm font-medium transition-colors"
    >
      {isConnecting ? "Connecting…" : "Connect Wallet"}
    </button>
  );
}
