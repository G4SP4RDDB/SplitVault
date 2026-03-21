// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/SplitVault.sol";
import "../src/MemberDAO.sol";
import "../src/ENSManager.sol";

contract Deploy is Script {
    // ── Sepolia constants ──────────────────────────────────────────────────
    address constant USDC        = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    address constant ENS_REGISTRY = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e;
    address constant ENS_RESOLVER = 0x8FADE66B79cC9f707aB26799354482EB93a5B7dD;

    // ── Members (from .env wallets) ────────────────────────────────────────
    address constant ALICE   = 0xC52074E136b14ed301C1062E46876834FFc6579d;
    address constant BOB     = 0x7CD5EFCB045ba0759279cD2C59B0eC89a59c544B;
    address constant CHARLIE = 0xB92fBb4D567F2a7f91f4B77Aa78fa2Fc448b99bB;

    // namehash("vaulthack.eth") — pre-computed via `cast namehash vaulthack.eth`
    bytes32 constant VAULT_NODE =
        0x2e5efc11d27ea98d362a1019063e67aa8c706113120422c9c707518959bcc032;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        // 1. Deploy SplitVault: alice 50%, bob 30%, charlie 20%
        address[] memory addrs = new address[](3);
        uint256[] memory pcts  = new uint256[](3);
        addrs[0] = ALICE;   pcts[0] = 50;
        addrs[1] = BOB;     pcts[1] = 30;
        addrs[2] = CHARLIE; pcts[2] = 20;

        SplitVault vault = new SplitVault(USDC, addrs, pcts);
        console.log("SplitVault :", address(vault));

        // 2. Deploy MemberDAO (1-day voting window, wired to ENSManager below)
        //    ENSManager address is set after deployment — use address(0) for now
        //    and update with setAuthorizedCaller after ENSManager is deployed.
        MemberDAO dao = new MemberDAO(payable(address(vault)), 1 days, address(0));
        console.log("MemberDAO  :", address(dao));

        // 3. Deploy ENSManager
        ENSManager ens = new ENSManager(ENS_REGISTRY, ENS_RESOLVER, VAULT_NODE);
        console.log("ENSManager :", address(ens));

        // 4. Wire everything together
        ens.setAuthorizedCaller(address(dao));
        vault.transferOwnership(address(dao));

        vm.stopBroadcast();

        console.log("---");
        console.log("Vault owned by DAO:", vault.owner() == address(dao));
        console.log("ENS authorized caller is DAO:", ens.authorizedCaller() == address(dao));
    }
}
