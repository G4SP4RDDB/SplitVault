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

        // ── 1. ENSManager ────────────────────────────────────────────────
        // Deploy first. After this script, call:
        //   cast send <BaseRegistrar> "reclaim(uint256,address)" <tokenId> <ensManagerAddr>
        // to hand vaulthack.eth ownership to this contract before creating vaults.

        ENSManager ens = new ENSManager(ENS_REGISTRY, ENS_RESOLVER, VAULT_NODE);
        console.log("ENSManager    :", address(ens));

        // ── 2. Registry + Factory ─────────────────────────────────────────

        VaultRegistry registry = new VaultRegistry();
        console.log("VaultRegistry :", address(registry));

        VaultFactory factory = new VaultFactory(USDC, address(registry), address(ens));
        console.log("VaultFactory  :", address(factory));

        // ── 3. Authorize factory ──────────────────────────────────────────
        // ENSManager needs to own vaulthack.eth before this call is useful,
        // but we can pre-authorize the factory now so it's ready.

        ens.addAuthorizedCaller(address(factory));

        console.log("---");
        console.log("Factory authorized:", ens.authorizedCallers(address(factory)));
        console.log("ENS label available (demo):", ens.isLabelAvailable("demo"));

        vm.stopBroadcast();
    }
}
