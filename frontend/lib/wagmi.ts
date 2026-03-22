import { createConfig, http }  from "wagmi";
import { sepolia, mainnet }    from "wagmi/chains";
import { injected }            from "wagmi/connectors";

export const wagmiConfig = createConfig({
  chains:     [sepolia, mainnet],
  connectors: [injected()],   // uses window.ethereum (MetaMask, Rabby, etc.)
  transports: {
    [sepolia.id]:  http(),
    [mainnet.id]:  http(),    // needed for ENS resolution
  },
  ssr:        true,
});
