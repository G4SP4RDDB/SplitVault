// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/SplitVault.sol";
import "../src/MemberDAO.sol";
import "../src/ENSManager.sol";
import "../src/VaultRegistry.sol";
import "../src/VaultFactory.sol";

contract Deploy is Script {
    // ── Sepolia constants ──────────────────────────────────────────────────
    address constant USDC         = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    address constant ENS_REGISTRY = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e;
    address constant ENS_RESOLVER = 0x8FADE66B79cC9f707aB26799354482EB93a5B7dD;

    // ── Members (from .env wallets) ────────────────────────────────────────
    address constant ALICE   = 0xC52074E136b14ed301C1062E46876834FFc6579d;
    address constant BOB     = 0x7CD5EFCB045ba0759279cD2C59B0eC89a59c544B;
    address constant CHARLIE = 0xB92fBb4D567F2a7f91f4B77Aa78fa2Fc448b99bB;

    // namehash("vaulthack.eth") — `cast namehash vaulthack.eth`
    bytes32 constant VAULT_NODE =
        0x2e5efc11d27ea98d362a1019063e67aa8c706113120422c9c707518959bcc032;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        // ── 1. Infrastructure ──────────────────────────────────────────────

        VaultRegistry registry = new VaultRegistry();
        console.log("VaultRegistry :", address(registry));

        VaultFactory factory = new VaultFactory(USDC, address(registry));
        console.log("VaultFactory  :", address(factory));

        // ── 2. Demo vault via factory (alice 50%, bob 30%, charlie 20%) ────

        address[] memory addrs = new address[](3);
        uint256[] memory pcts  = new uint256[](3);
        addrs[0] = ALICE;   pcts[0] = 50;
        addrs[1] = BOB;     pcts[1] = 30;
        addrs[2] = CHARLIE; pcts[2] = 20;

        (address vaultAddr, address daoAddr) =
            factory.createVault(addrs, pcts, 1 days);

        console.log("SplitVault    :", vaultAddr);
        console.log("MemberDAO     :", daoAddr);

        // ── 3. ENSManager for vaulthack.eth (advanced, optional) ──────────

        ENSManager ens = new ENSManager(ENS_REGISTRY, ENS_RESOLVER, VAULT_NODE);
        console.log("ENSManager    :", address(ens));

        // Wire ENSManager: DAO is authorized caller, creator keeps ENS ownership
        ens.setAuthorizedCaller(daoAddr);

        // Attach ENSManager to the DAO (any member can call setENSManager)
        // We use alice's key — alice is a member
        vm.stopBroadcast();
        uint256 aliceKey = vm.envUint("ALICE_PK");
        vm.startBroadcast(aliceKey);
        MemberDAO(daoAddr).setENSManager(address(ens));
        vm.stopBroadcast();

        vm.startBroadcast(deployerKey);

        // ── 4. Sanity checks ──────────────────────────────────────────────
        console.log("---");
        console.log("Vault in registry      :", registry.isRegistered(vaultAddr));
        console.log("Vault owned by DAO     :", SplitVault(vaultAddr).owner() == daoAddr);
        console.log("ENS auth caller is DAO :", ens.authorizedCaller() == daoAddr);
        console.log("DAO ensManager set     :", address(MemberDAO(daoAddr).ensManager()) == address(ens));

        vm.stopBroadcast();
    }
}
