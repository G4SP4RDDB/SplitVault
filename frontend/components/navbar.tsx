"use client";

import Link from "next/link";
import { ConnectButton } from "@/components/connect-button";
import { useAccount }    from "wagmi";

export function Navbar() {
  const { isConnected } = useAccount();

  return (
    <nav className="border-b border-gray-800 bg-gray-900/80 backdrop-blur sticky top-0 z-50">
      <div className="max-w-5xl mx-auto px-4 h-16 flex items-center justify-between">
        <div className="flex items-center gap-6">
          <Link href="/" className="font-bold text-lg text-indigo-400 hover:text-indigo-300">
            SplitVault
          </Link>
          {isConnected && (
            <Link
              href="/dashboard"
              className="text-sm text-gray-400 hover:text-gray-100 transition-colors"
            >
              Dashboard
            </Link>
          )}
        </div>
        <ConnectButton />
      </div>
    </nav>
  );
}
