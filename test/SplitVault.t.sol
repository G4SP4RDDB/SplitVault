// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/SplitVault.sol";

contract SplitVaultTest is Test {
    SplitVault vault;

    address alice   = makeAddr("alice");
    address bob     = makeAddr("bob");
    address charlie = makeAddr("charlie");

    // Default split: alice 50%, bob 30%, charlie 20%
    function setUp() public {
        address[] memory addrs = new address[](3);
        uint256[] memory pcts  = new uint256[](3);

        addrs[0] = alice;   pcts[0] = 50;
        addrs[1] = bob;     pcts[1] = 30;
        addrs[2] = charlie; pcts[2] = 20;

        vault = new SplitVault(addrs, pcts);
    }

    // =========================================================================
    // Constructor — validation
    // =========================================================================

    function test_RevertIf_EmptyMembers() public {
        vm.expectRevert(SplitVault.EmptyMembers.selector);
        new SplitVault(new address[](0), new uint256[](0));
    }

    function test_RevertIf_ArrayLengthMismatch() public {
        address[] memory addrs = new address[](2);
        uint256[] memory pcts  = new uint256[](1);
        addrs[0] = alice; addrs[1] = bob;
        pcts[0]  = 100;

        vm.expectRevert(SplitVault.ArrayLengthMismatch.selector);
        new SplitVault(addrs, pcts);
    }

    function test_RevertIf_ZeroAddress() public {
        address[] memory addrs = new address[](2);
        uint256[] memory pcts  = new uint256[](2);
        addrs[0] = address(0); addrs[1] = bob;
        pcts[0]  = 50;         pcts[1]  = 50;

        vm.expectRevert(SplitVault.ZeroAddress.selector);
        new SplitVault(addrs, pcts);
    }

    function test_RevertIf_DuplicateAddress() public {
        address[] memory addrs = new address[](2);
        uint256[] memory pcts  = new uint256[](2);
        addrs[0] = alice; addrs[1] = alice; // duplicate
        pcts[0]  = 50;    pcts[1]  = 50;

        vm.expectRevert(abi.encodeWithSelector(SplitVault.DuplicateAddress.selector, alice));
        new SplitVault(addrs, pcts);
    }

    function test_RevertIf_PercentagesUnder100() public {
        address[] memory addrs = new address[](2);
        uint256[] memory pcts  = new uint256[](2);
        addrs[0] = alice; addrs[1] = bob;
        pcts[0]  = 50;    pcts[1]  = 40; // 90 total

        vm.expectRevert(SplitVault.PercentagesMustSum100.selector);
        new SplitVault(addrs, pcts);
    }

    function test_RevertIf_ZeroPercentage() public {
        address[] memory addrs = new address[](2);
        uint256[] memory pcts  = new uint256[](2);
        addrs[0] = alice; addrs[1] = bob;
        pcts[0]  = 100;   pcts[1]  = 0; // bob has 0% — meaningless entry

        vm.expectRevert(SplitVault.ZeroPercentage.selector);
        new SplitVault(addrs, pcts);
    }

    function test_RevertIf_PercentagesOver100() public {
        address[] memory addrs = new address[](2);
        uint256[] memory pcts  = new uint256[](2);
        addrs[0] = alice; addrs[1] = bob;
        pcts[0]  = 60;    pcts[1]  = 60; // 120 total

        vm.expectRevert(SplitVault.PercentagesMustSum100.selector);
        new SplitVault(addrs, pcts);
    }

    function test_GetMembers() public view {
        (address[] memory addrs, uint256[] memory pcts) = vault.getMembers();
        assertEq(addrs.length, 3);
        assertEq(addrs[0], alice);   assertEq(pcts[0], 50);
        assertEq(addrs[1], bob);     assertEq(pcts[1], 30);
        assertEq(addrs[2], charlie); assertEq(pcts[2], 20);
    }

    // =========================================================================
    // Deposits
    // =========================================================================

    function test_DepositViaReceive() public {
        vm.deal(address(this), 1 ether);

        vm.expectEmit(true, false, false, true);
        emit SplitVault.Deposited(address(this), 1 ether);

        (bool ok,) = address(vault).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(address(vault).balance, 1 ether);
    }

    function test_DepositViaFunction() public {
        vm.deal(address(this), 2 ether);

        vm.expectEmit(true, false, false, true);
        emit SplitVault.Deposited(address(this), 2 ether);

        vault.deposit{value: 2 ether}();
        assertEq(address(vault).balance, 2 ether);
    }

    function testFuzz_Deposit(uint96 amount) public {
        vm.assume(amount > 0);
        vm.deal(address(this), amount);

        vault.deposit{value: amount}();
        assertEq(address(vault).balance, amount);
    }

    // =========================================================================
    // Distribution
    // =========================================================================

    function test_RevertIf_NoFunds() public {
        vm.expectRevert(SplitVault.NoFundsToDistribute.selector);
        vault.distribute();
    }

    function test_CorrectDistribution() public {
        vm.deal(address(vault), 100 ether);

        vault.distribute();

        assertEq(alice.balance,   50 ether);
        assertEq(bob.balance,     30 ether);
        assertEq(charlie.balance, 20 ether);
        assertEq(address(vault).balance, 0);
    }

    function test_DistributionEvent() public {
        vm.deal(address(vault), 1 ether);

        vm.expectEmit(false, false, false, true);
        emit SplitVault.Distributed(1 ether);

        vault.distribute();
    }

    /// @dev Integer division dust stays in the vault (not lost).
    function test_DustRemainsInVault() public {
        // 1 wei — (1 * 50)/100 = 0, (1 * 30)/100 = 0, (1 * 20)/100 = 0
        vm.deal(address(vault), 1 wei);
        vault.distribute();

        // No member received anything, dust stays in vault
        assertEq(alice.balance,   0);
        assertEq(bob.balance,     0);
        assertEq(charlie.balance, 0);
        assertEq(address(vault).balance, 1 wei);
    }

    function testFuzz_DistributionProportions(uint96 amount) public {
        vm.assume(amount >= 100); // ensure non-zero shares
        vm.deal(address(vault), amount);

        vault.distribute();

        // Each member received exactly their floor share (integer division)
        assertEq(alice.balance,   (uint256(amount) * 50) / 100);
        assertEq(bob.balance,     (uint256(amount) * 30) / 100);
        assertEq(charlie.balance, (uint256(amount) * 20) / 100);
    }

    /// @dev A vault with a single member receiving 100% must work correctly.
    function test_SingleMember() public {
        address[] memory addrs = new address[](1);
        uint256[] memory pcts  = new uint256[](1);
        addrs[0] = alice; pcts[0] = 100;

        SplitVault solo = new SplitVault(addrs, pcts);
        vm.deal(address(solo), 3 ether);

        solo.distribute();

        assertEq(alice.balance,        3 ether);
        assertEq(address(solo).balance, 0);
    }

    /// @dev Calling distribute() twice drains dust accumulated from the first round.
    function test_DistributeCalledTwice() public {
        // 10 wei: alice=5, bob=3, charlie=2 → vault=0 (clean split)
        vm.deal(address(vault), 10 wei);
        vault.distribute();
        assertEq(address(vault).balance, 0);

        // Snapshot balances — members already hold wei from round 1
        uint256 aliceBefore   = alice.balance;
        uint256 bobBefore     = bob.balance;
        uint256 charlieBefore = charlie.balance;

        // Fund again and distribute a second time
        vm.deal(address(vault), 100 ether);
        vault.distribute();

        // Each member must have received exactly their new share on top of what they had
        assertEq(alice.balance,   aliceBefore   + 50 ether);
        assertEq(bob.balance,     bobBefore     + 30 ether);
        assertEq(charlie.balance, charlieBefore + 20 ether);
        assertEq(address(vault).balance, 0);
    }

    /// @dev If a member's address is a contract that reverts on ETH receipt,
    ///      distribute() must revert with TransferFailed.
    function test_RevertIf_RecipientRejectsETH() public {
        Rejector rejector = new Rejector();

        address[] memory addrs = new address[](2);
        uint256[] memory pcts  = new uint256[](2);
        addrs[0] = address(rejector); pcts[0] = 50;
        addrs[1] = bob;               pcts[1] = 50;

        SplitVault badVault = new SplitVault(addrs, pcts);
        vm.deal(address(badVault), 2 ether);

        vm.expectRevert(
            abi.encodeWithSelector(SplitVault.TransferFailed.selector, address(rejector))
        );
        badVault.distribute();

        // Bob must NOT have received anything since the tx reverted
        assertEq(bob.balance, 0);
    }

    // =========================================================================
    // addMember
    // =========================================================================

    function test_AddMember() public {
        address dave = makeAddr("dave");

        // alice 40%, bob 25%, charlie 15%, dave 20%
        uint256[] memory newPcts = new uint256[](4);
        newPcts[0] = 40; newPcts[1] = 25; newPcts[2] = 15; newPcts[3] = 20;

        vm.expectEmit(true, false, false, true);
        emit SplitVault.MemberAdded(dave, 20);

        vault.addMember(dave, newPcts);

        (address[] memory addrs, uint256[] memory pcts) = vault.getMembers();
        assertEq(addrs.length, 4);
        assertEq(addrs[3], dave);
        assertEq(pcts[0], 40); // alice updated
        assertEq(pcts[1], 25); // bob updated
        assertEq(pcts[2], 15); // charlie updated
        assertEq(pcts[3], 20); // dave new
    }

    function test_RevertIf_AddMember_NotOwner() public {
        uint256[] memory newPcts = new uint256[](4);
        newPcts[0] = 40; newPcts[1] = 25; newPcts[2] = 15; newPcts[3] = 20;

        vm.prank(alice); // alice is not the owner
        vm.expectRevert(SplitVault.NotOwner.selector);
        vault.addMember(makeAddr("dave"), newPcts);
    }

    function test_RevertIf_AddMember_ZeroAddress() public {
        uint256[] memory newPcts = new uint256[](4);
        newPcts[0] = 40; newPcts[1] = 25; newPcts[2] = 15; newPcts[3] = 20;

        vm.expectRevert(SplitVault.ZeroAddress.selector);
        vault.addMember(address(0), newPcts);
    }

    function test_RevertIf_AddMember_Duplicate() public {
        uint256[] memory newPcts = new uint256[](4);
        newPcts[0] = 40; newPcts[1] = 25; newPcts[2] = 15; newPcts[3] = 20;

        vm.expectRevert(abi.encodeWithSelector(SplitVault.DuplicateAddress.selector, alice));
        vault.addMember(alice, newPcts); // alice already exists
    }

    function test_RevertIf_AddMember_ArrayTooShort() public {
        uint256[] memory newPcts = new uint256[](3); // should be 4
        newPcts[0] = 34; newPcts[1] = 33; newPcts[2] = 33;

        vm.expectRevert(SplitVault.ArrayLengthMismatch.selector);
        vault.addMember(makeAddr("dave"), newPcts);
    }

    function test_RevertIf_AddMember_ArrayTooLong() public {
        uint256[] memory newPcts = new uint256[](5); // should be 4
        newPcts[0] = 20; newPcts[1] = 20; newPcts[2] = 20; newPcts[3] = 20; newPcts[4] = 20;

        vm.expectRevert(SplitVault.ArrayLengthMismatch.selector);
        vault.addMember(makeAddr("dave"), newPcts);
    }

    function test_RevertIf_AddMember_SumNot100() public {
        uint256[] memory newPcts = new uint256[](4);
        newPcts[0] = 40; newPcts[1] = 25; newPcts[2] = 15; newPcts[3] = 15; // sums to 95

        vm.expectRevert(SplitVault.PercentagesMustSum100.selector);
        vault.addMember(makeAddr("dave"), newPcts);
    }

    function test_RevertIf_AddMember_ZeroPercentage() public {
        uint256[] memory newPcts = new uint256[](4);
        newPcts[0] = 50; newPcts[1] = 30; newPcts[2] = 20; newPcts[3] = 0;

        vm.expectRevert(SplitVault.ZeroPercentage.selector);
        vault.addMember(makeAddr("dave"), newPcts);
    }

    /// @dev Adding a member to a single-member vault is the minimal state transition.
    function test_AddMember_ToSingleMemberVault() public {
        address[] memory addrs = new address[](1);
        uint256[] memory pcts  = new uint256[](1);
        addrs[0] = alice; pcts[0] = 100;

        SplitVault solo = new SplitVault(addrs, pcts);

        // alice 60%, bob 40%
        uint256[] memory newPcts = new uint256[](2);
        newPcts[0] = 60; newPcts[1] = 40;
        solo.addMember(bob, newPcts);

        (address[] memory outAddrs, uint256[] memory outPcts) = solo.getMembers();
        assertEq(outAddrs.length, 2);
        assertEq(outAddrs[0], alice); assertEq(outPcts[0], 60);
        assertEq(outAddrs[1], bob);   assertEq(outPcts[1], 40);
    }

    /// @dev Adding two members sequentially keeps state consistent.
    function test_AddMemberTwice() public {
        address dave = makeAddr("dave");
        address eve  = makeAddr("eve");

        // First add: alice 40%, bob 25%, charlie 15%, dave 20%
        uint256[] memory pcts1 = new uint256[](4);
        pcts1[0] = 40; pcts1[1] = 25; pcts1[2] = 15; pcts1[3] = 20;
        vault.addMember(dave, pcts1);

        // Second add: alice 30%, bob 20%, charlie 15%, dave 15%, eve 20%
        uint256[] memory pcts2 = new uint256[](5);
        pcts2[0] = 30; pcts2[1] = 20; pcts2[2] = 15; pcts2[3] = 15; pcts2[4] = 20;
        vault.addMember(eve, pcts2);

        (address[] memory outAddrs, uint256[] memory outPcts) = vault.getMembers();
        assertEq(outAddrs.length, 5);
        assertEq(outAddrs[4], eve);
        assertEq(outPcts[0], 30); // alice
        assertEq(outPcts[1], 20); // bob
        assertEq(outPcts[2], 15); // charlie
        assertEq(outPcts[3], 15); // dave
        assertEq(outPcts[4], 20); // eve

        // Verify distribute uses the final 5-member split
        vm.deal(address(vault), 100 ether);
        vault.distribute();

        assertEq(alice.balance,        30 ether);
        assertEq(bob.balance,          20 ether);
        assertEq(charlie.balance,      15 ether);
        assertEq(dave.balance,         15 ether);
        assertEq(eve.balance,          20 ether);
        assertEq(address(vault).balance, 0);
    }

    function test_DistributeAfterAddMember() public {
        address dave = makeAddr("dave");
        uint256[] memory newPcts = new uint256[](4);
        newPcts[0] = 40; newPcts[1] = 25; newPcts[2] = 15; newPcts[3] = 20;
        vault.addMember(dave, newPcts);

        vm.deal(address(vault), 100 ether);
        vault.distribute();

        assertEq(alice.balance,   40 ether);
        assertEq(bob.balance,     25 ether);
        assertEq(charlie.balance, 15 ether);
        assertEq(dave.balance,    20 ether);
        assertEq(address(vault).balance, 0);
    }

    // =========================================================================
    // Reentrancy protection
    // =========================================================================

    function test_ReentrancyBlocked() public {
        // Build a vault where the attacker is a member
        Attacker attacker = new Attacker();

        address[] memory addrs = new address[](2);
        uint256[] memory pcts  = new uint256[](2);
        addrs[0] = address(attacker); pcts[0] = 50;
        addrs[1] = bob;               pcts[1] = 50;

        SplitVault target = new SplitVault(addrs, pcts);
        attacker.setTarget(target);

        vm.deal(address(target), 10 ether);

        // distribute() must succeed — attacker's reentrant call is silently
        // rejected by the nonReentrant guard and absorbed via try/catch.
        target.distribute();

        // Attacker received only its fair 50% — not more
        assertEq(address(attacker).balance, 5 ether);
        assertEq(bob.balance,               5 ether);
        assertEq(attacker.attackCount(),    1); // one reentrant attempt was made
    }
}

// =============================================================================
// Attacker contract — tries to reenter distribute() on receipt of ETH
// =============================================================================

/// @dev A contract with no receive/fallback — always rejects ETH.
contract Rejector {}

contract Attacker {
    SplitVault public target;
    uint256 public attackCount;

    function setTarget(SplitVault _target) external {
        target = _target;
    }

    receive() external payable {
        if (address(target).balance > 0) {
            attackCount++;
            // The reentrant call reverts (Reentrant error) — we absorb it
            // so the outer distribute() can still complete normally.
            try target.distribute() {} catch {}
        }
    }
}
