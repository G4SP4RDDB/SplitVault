// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/VaultRegistry.sol";

contract VaultRegistryTest is Test {
    VaultRegistry reg;

    address alice = makeAddr("alice");
    address bob   = makeAddr("bob");
    address vault1 = makeAddr("vault1");
    address vault2 = makeAddr("vault2");
    address vault3 = makeAddr("vault3");

    function setUp() public {
        reg = new VaultRegistry();
    }

    // =========================================================================
    // register
    // =========================================================================

    function test_Register() public {
        vm.expectEmit(true, true, false, false);
        emit VaultRegistry.VaultRegistered(vault1, address(this));

        reg.register(vault1);

        assertTrue(reg.isRegistered(vault1));
        assertEq(reg.vaultCount(), 1);
    }

    function test_Register_Multiple() public {
        reg.register(vault1);
        reg.register(vault2);
        reg.register(vault3);

        assertEq(reg.vaultCount(), 3);
        assertTrue(reg.isRegistered(vault1));
        assertTrue(reg.isRegistered(vault2));
        assertTrue(reg.isRegistered(vault3));
    }

    function test_Register_ByAnyone() public {
        vm.prank(alice);
        reg.register(vault1);
        assertTrue(reg.isRegistered(vault1));

        vm.prank(bob);
        reg.register(vault2);
        assertTrue(reg.isRegistered(vault2));
    }

    function test_RevertIf_Register_ZeroAddress() public {
        vm.expectRevert(VaultRegistry.ZeroAddress.selector);
        reg.register(address(0));
    }

    function test_RevertIf_Register_AlreadyRegistered() public {
        reg.register(vault1);

        vm.expectRevert(VaultRegistry.AlreadyRegistered.selector);
        reg.register(vault1);
    }

    // =========================================================================
    // getAllVaults
    // =========================================================================

    function test_GetAllVaults_Empty() public view {
        address[] memory vaults = reg.getAllVaults();
        assertEq(vaults.length, 0);
    }

    function test_GetAllVaults() public {
        reg.register(vault1);
        reg.register(vault2);
        reg.register(vault3);

        address[] memory vaults = reg.getAllVaults();
        assertEq(vaults.length, 3);
        assertEq(vaults[0], vault1);
        assertEq(vaults[1], vault2);
        assertEq(vaults[2], vault3);
    }

    // =========================================================================
    // vaultCount
    // =========================================================================

    function test_VaultCount_StartsAtZero() public view {
        assertEq(reg.vaultCount(), 0);
    }

    function test_VaultCount_IncrementsOnRegister() public {
        reg.register(vault1);
        assertEq(reg.vaultCount(), 1);
        reg.register(vault2);
        assertEq(reg.vaultCount(), 2);
    }

    // =========================================================================
    // isRegistered
    // =========================================================================

    function test_IsRegistered_False_WhenNotRegistered() public view {
        assertFalse(reg.isRegistered(vault1));
    }

    function test_IsRegistered_True_AfterRegister() public {
        reg.register(vault1);
        assertTrue(reg.isRegistered(vault1));
    }
}
