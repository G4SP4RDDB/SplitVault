import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "./globals.css";
import { Providers }     from "./providers";
import { Navbar }        from "@/components/navbar";
import { NetworkGuard }  from "@/components/network-guard";

const inter = Inter({ subsets: ["latin"] });

export const metadata: Metadata = {
  title:       "SplitVault",
  description: "On-chain payment splitting for DAOs and teams",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="dark">
      <body className={`${inter.className} bg-gray-950 text-gray-100 min-h-screen`}>
        <Providers>
          <Navbar />
          <NetworkGuard />
          <main className="max-w-5xl mx-auto px-4 py-8">{children}</main>
        </Providers>
      </body>
    </html>
  );
}
