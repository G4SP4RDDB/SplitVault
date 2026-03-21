// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/SplitVault.sol";

// =============================================================================
// Mock tokens
// =============================================================================

/// @dev Standard mock USDC: 6 decimals, free mint.
contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {}

    function decimals() public pure override returns (uint8) { return 6; }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev Token whose transfer() always returns false — triggers TransferFailed.
contract FailToken is ERC20 {
    constructor() ERC20("Fail", "FAIL") {}

    function mint(address to, uint256 amount) external { _mint(to, amount); }

    function transfer(address, uint256) public pure override returns (bool) {
        return false;
    }
}

/// @dev Token that reenters distribute() during transfer to test nonReentrant.
contract ReentrantToken is ERC20 {
    SplitVault public target;

    constructor() ERC20("Reentrant", "RENT") {}

    function setTarget(SplitVault _target) external { target = _target; }

    function mint(address to, uint256 amount) external { _mint(to, amount); }

    function transfer(address to, uint256 amount) public override returns (bool) {
        // Attempt reentry before completing the transfer
        if (address(target) != address(0)) {
            try target.distribute() {} catch {}
        }
        return super.transfer(to, amount);
    }
}

// =============================================================================
// Helpers
// =============================================================================

// 1 USDC = 1_000_000 (6 decimals)
uint256 constant USDC = 1_000_000;

// =============================================================================
// Main test suite
// =============================================================================

contract SplitVaultTest is Test {
    SplitVault vault;
    MockUSDC   usdc;

    address alice   = makeAddr("alice");
    address bob     = makeAddr("bob");
    address charlie = makeAddr("charlie");

    // Default split: alice 50%, bob 30%, charlie 20%
    function setUp() public {
        usdc = new MockUSDC();

        address[] memory addrs = new address[](3);
        uint256[] memory pcts  = new uint256[](3);
        addrs[0] = alice;   pcts[0] = 50;
        addrs[1] = bob;     pcts[1] = 30;
        addrs[2] = charlie; pcts[2] = 20;

        vault = new SplitVault(address(usdc), addrs, pcts);
    }

    // =========================================================================
    // Constructor — validation
    // =========================================================================

    function test_RevertIf_ZeroToken() public {
        address[] memory addrs = new address[](1);
        uint256[] memory pcts  = new uint256[](1);
        addrs[0] = alice; pcts[0] = 100;

        vm.expectRevert(SplitVault.ZeroAddress.selector);
        new SplitVault(address(0), addrs, pcts);
    }

    function test_RevertIf_EmptyMembers() public {
        vm.expectRevert(SplitVault.EmptyMembers.selector);
        new SplitVault(address(usdc), new address[](0), new uint256[](0));
    }

    function test_RevertIf_ArrayLengthMismatch() public {
        address[] memory addrs = new address[](2);
        uint256[] memory pcts  = new uint256[](1);
        addrs[0] = alice; addrs[1] = bob;
        pcts[0]  = 100;

        vm.expectRevert(SplitVault.ArrayLengthMismatch.selector);
        new SplitVault(address(usdc), addrs, pcts);
    }

    function test_RevertIf_ZeroAddress() public {
        address[] memory addrs = new address[](2);
        uint256[] memory pcts  = new uint256[](2);
        addrs[0] = address(0); addrs[1] = bob;
        pcts[0]  = 50;         pcts[1]  = 50;

        vm.expectRevert(SplitVault.ZeroAddress.selector);
        new SplitVault(address(usdc), addrs, pcts);
    }

    function test_RevertIf_DuplicateAddress() public {
        address[] memory addrs = new address[](2);
        uint256[] memory pcts  = new uint256[](2);
        addrs[0] = alice; addrs[1] = alice;
        pcts[0]  = 50;    pcts[1]  = 50;

        vm.expectRevert(abi.encodeWithSelector(SplitVault.DuplicateAddress.selector, alice));
        new SplitVault(address(usdc), addrs, pcts);
    }

    function test_RevertIf_PercentagesUnder100() public {
        address[] memory addrs = new address[](2);
        uint256[] memory pcts  = new uint256[](2);
        addrs[0] = alice; addrs[1] = bob;
        pcts[0]  = 50;    pcts[1]  = 40;

        vm.expectRevert(SplitVault.PercentagesMustSum100.selector);
        new SplitVault(address(usdc), addrs, pcts);
    }

    function test_RevertIf_ZeroPercentage() public {
        address[] memory addrs = new address[](2);
        uint256[] memory pcts  = new uint256[](2);
        addrs[0] = alice; addrs[1] = bob;
        pcts[0]  = 100;   pcts[1]  = 0;

        vm.expectRevert(SplitVault.ZeroPercentage.selector);
        new SplitVault(address(usdc), addrs, pcts);
    }

    function test_RevertIf_PercentagesOver100() public {
        address[] memory addrs = new address[](2);
        uint256[] memory pcts  = new uint256[](2);
        addrs[0] = alice; addrs[1] = bob;
        pcts[0]  = 60;    pcts[1]  = 60;

        vm.expectRevert(SplitVault.PercentagesMustSum100.selector);
        new SplitVault(address(usdc), addrs, pcts);
    }

    function test_GetMembers() public view {
        (address[] memory addrs, uint256[] memory pcts) = vault.getMembers();
        assertEq(addrs.length, 3);
        assertEq(addrs[0], alice);   assertEq(pcts[0], 50);
        assertEq(addrs[1], bob);     assertEq(pcts[1], 30);
        assertEq(addrs[2], charlie); assertEq(pcts[2], 20);
    }

    function test_TokenAddress() public view {
        assertEq(address(vault.token()), address(usdc));
    }

    // =========================================================================
    // Deposits
    // =========================================================================

    function test_Deposit() public {
        usdc.mint(address(this), 100 * USDC);
        usdc.approve(address(vault), 100 * USDC);

        vm.expectEmit(true, false, false, true);
        emit SplitVault.Deposited(address(this), 100 * USDC);

        vault.deposit(100 * USDC);
        assertEq(usdc.balanceOf(address(vault)), 100 * USDC);
    }

    function test_Deposit_RequiresApproval() public {
        usdc.mint(address(this), 100 * USDC);
        // No approve → transferFrom reverts
        vm.expectRevert();
        vault.deposit(100 * USDC);
    }

    function testFuzz_Deposit(uint64 amount) public {
        vm.assume(amount > 0);
        usdc.mint(address(this), amount);
        usdc.approve(address(vault), amount);

        vault.deposit(amount);
        assertEq(usdc.balanceOf(address(vault)), amount);
    }

    // =========================================================================
    // Distribution
    // =========================================================================

    function test_RevertIf_NoFunds() public {
        vm.expectRevert(SplitVault.NoFundsToDistribute.selector);
        vault.distribute();
    }

    function test_CorrectDistribution() public {
        usdc.mint(address(vault), 100 * USDC);

        vault.distribute();

        assertEq(usdc.balanceOf(alice),   50 * USDC);
        assertEq(usdc.balanceOf(bob),     30 * USDC);
        assertEq(usdc.balanceOf(charlie), 20 * USDC);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    function test_DistributionEvent() public {
        usdc.mint(address(vault), 10 * USDC);

        vm.expectEmit(false, false, false, true);
        emit SplitVault.Distributed(10 * USDC);

        vault.distribute();
    }

    /// @dev Token dust from integer division stays in the vault.
    function test_DustRemainsInVault() public {
        // 1 token unit: (1 * 50)/100 = 0 for everyone → dust stays
        usdc.mint(address(vault), 1);
        vault.distribute();

        assertEq(usdc.balanceOf(alice),          0);
        assertEq(usdc.balanceOf(bob),            0);
        assertEq(usdc.balanceOf(charlie),        0);
        assertEq(usdc.balanceOf(address(vault)), 1);
    }

    function testFuzz_DistributionProportions(uint64 amount) public {
        vm.assume(amount >= 100);
        usdc.mint(address(vault), amount);

        vault.distribute();

        assertEq(usdc.balanceOf(alice),   (uint256(amount) * 50) / 100);
        assertEq(usdc.balanceOf(bob),     (uint256(amount) * 30) / 100);
        assertEq(usdc.balanceOf(charlie), (uint256(amount) * 20) / 100);
    }

    function test_SingleMember() public {
        address[] memory addrs = new address[](1);
        uint256[] memory pcts  = new uint256[](1);
        addrs[0] = alice; pcts[0] = 100;

        SplitVault solo = new SplitVault(address(usdc), addrs, pcts);
        usdc.mint(address(solo), 300 * USDC);

        solo.distribute();

        assertEq(usdc.balanceOf(alice),        300 * USDC);
        assertEq(usdc.balanceOf(address(solo)), 0);
    }

    function test_DistributeCalledTwice() public {
        usdc.mint(address(vault), 10 * USDC);
        vault.distribute();
        assertEq(usdc.balanceOf(address(vault)), 0);

        uint256 aliceBefore   = usdc.balanceOf(alice);
        uint256 bobBefore     = usdc.balanceOf(bob);
        uint256 charlieBefore = usdc.balanceOf(charlie);

        usdc.mint(address(vault), 100 * USDC);
        vault.distribute();

        assertEq(usdc.balanceOf(alice),   aliceBefore   + 50 * USDC);
        assertEq(usdc.balanceOf(bob),     bobBefore     + 30 * USDC);
        assertEq(usdc.balanceOf(charlie), charlieBefore + 20 * USDC);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    /// @dev token.transfer() returning false triggers TransferFailed.
    function test_RevertIf_TransferReturnsFalse() public {
        FailToken fail = new FailToken();
        fail.mint(address(this), 0); // just deploy

        address[] memory addrs = new address[](2);
        uint256[] memory pcts  = new uint256[](2);
        addrs[0] = alice; pcts[0] = 50;
        addrs[1] = bob;   pcts[1] = 50;

        SplitVault badVault = new SplitVault(address(fail), addrs, pcts);
        fail.mint(address(badVault), 100 * USDC);

        vm.expectRevert(
            abi.encodeWithSelector(SplitVault.TransferFailed.selector, alice)
        );
        badVault.distribute();
    }

    // =========================================================================
    // addMember
    // =========================================================================

    function test_AddMember() public {
        address dave = makeAddr("dave");

        uint256[] memory newPcts = new uint256[](4);
        newPcts[0] = 40; newPcts[1] = 25; newPcts[2] = 15; newPcts[3] = 20;

        vm.expectEmit(true, false, false, true);
        emit SplitVault.MemberAdded(dave, 20);

        vault.addMember(dave, newPcts);

        (address[] memory addrs, uint256[] memory pcts) = vault.getMembers();
        assertEq(addrs.length, 4);
        assertEq(addrs[3], dave);
        assertEq(pcts[0], 40);
        assertEq(pcts[1], 25);
        assertEq(pcts[2], 15);
        assertEq(pcts[3], 20);
    }

    function test_RevertIf_AddMember_NotOwner() public {
        uint256[] memory newPcts = new uint256[](4);
        newPcts[0] = 40; newPcts[1] = 25; newPcts[2] = 15; newPcts[3] = 20;

        vm.prank(alice);
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
        vault.addMember(alice, newPcts);
    }

    function test_RevertIf_AddMember_ArrayTooShort() public {
        uint256[] memory newPcts = new uint256[](3);
        newPcts[0] = 34; newPcts[1] = 33; newPcts[2] = 33;

        vm.expectRevert(SplitVault.ArrayLengthMismatch.selector);
        vault.addMember(makeAddr("dave"), newPcts);
    }

    function test_RevertIf_AddMember_ArrayTooLong() public {
        uint256[] memory newPcts = new uint256[](5);
        newPcts[0] = 20; newPcts[1] = 20; newPcts[2] = 20; newPcts[3] = 20; newPcts[4] = 20;

        vm.expectRevert(SplitVault.ArrayLengthMismatch.selector);
        vault.addMember(makeAddr("dave"), newPcts);
    }

    function test_RevertIf_AddMember_SumNot100() public {
        uint256[] memory newPcts = new uint256[](4);
        newPcts[0] = 40; newPcts[1] = 25; newPcts[2] = 15; newPcts[3] = 15; // 95

        vm.expectRevert(SplitVault.PercentagesMustSum100.selector);
        vault.addMember(makeAddr("dave"), newPcts);
    }

    function test_RevertIf_AddMember_ZeroPercentage() public {
        uint256[] memory newPcts = new uint256[](4);
        newPcts[0] = 50; newPcts[1] = 30; newPcts[2] = 20; newPcts[3] = 0;

        vm.expectRevert(SplitVault.ZeroPercentage.selector);
        vault.addMember(makeAddr("dave"), newPcts);
    }

    function test_AddMember_ToSingleMemberVault() public {
        address[] memory addrs = new address[](1);
        uint256[] memory pcts  = new uint256[](1);
        addrs[0] = alice; pcts[0] = 100;

        SplitVault solo = new SplitVault(address(usdc), addrs, pcts);

        uint256[] memory newPcts = new uint256[](2);
        newPcts[0] = 60; newPcts[1] = 40;
        solo.addMember(bob, newPcts);

        (address[] memory outAddrs, uint256[] memory outPcts) = solo.getMembers();
        assertEq(outAddrs.length, 2);
        assertEq(outAddrs[0], alice); assertEq(outPcts[0], 60);
        assertEq(outAddrs[1], bob);   assertEq(outPcts[1], 40);
    }

    function test_AddMemberTwice() public {
        address dave = makeAddr("dave");
        address eve  = makeAddr("eve");

        uint256[] memory pcts1 = new uint256[](4);
        pcts1[0] = 40; pcts1[1] = 25; pcts1[2] = 15; pcts1[3] = 20;
        vault.addMember(dave, pcts1);

        uint256[] memory pcts2 = new uint256[](5);
        pcts2[0] = 30; pcts2[1] = 20; pcts2[2] = 15; pcts2[3] = 15; pcts2[4] = 20;
        vault.addMember(eve, pcts2);

        (address[] memory outAddrs, uint256[] memory outPcts) = vault.getMembers();
        assertEq(outAddrs.length, 5);
        assertEq(outAddrs[4], eve);
        assertEq(outPcts[0], 30);
        assertEq(outPcts[1], 20);
        assertEq(outPcts[2], 15);
        assertEq(outPcts[3], 15);
        assertEq(outPcts[4], 20);

        usdc.mint(address(vault), 100 * USDC);
        vault.distribute();

        assertEq(usdc.balanceOf(alice),   30 * USDC);
        assertEq(usdc.balanceOf(bob),     20 * USDC);
        assertEq(usdc.balanceOf(charlie), 15 * USDC);
        assertEq(usdc.balanceOf(dave),    15 * USDC);
        assertEq(usdc.balanceOf(eve),     20 * USDC);
    }

    function test_DistributeAfterAddMember() public {
        address dave = makeAddr("dave");
        uint256[] memory newPcts = new uint256[](4);
        newPcts[0] = 40; newPcts[1] = 25; newPcts[2] = 15; newPcts[3] = 20;
        vault.addMember(dave, newPcts);

        usdc.mint(address(vault), 100 * USDC);
        vault.distribute();

        assertEq(usdc.balanceOf(alice),   40 * USDC);
        assertEq(usdc.balanceOf(bob),     25 * USDC);
        assertEq(usdc.balanceOf(charlie), 15 * USDC);
        assertEq(usdc.balanceOf(dave),    20 * USDC);
    }

    // =========================================================================
    // Reentrancy protection
    // =========================================================================

    function test_ReentrancyBlocked() public {
        ReentrantToken rToken = new ReentrantToken();

        address[] memory addrs = new address[](2);
        uint256[] memory pcts  = new uint256[](2);
        addrs[0] = alice; pcts[0] = 50;
        addrs[1] = bob;   pcts[1] = 50;

        SplitVault target = new SplitVault(address(rToken), addrs, pcts);
        rToken.setTarget(target);

        rToken.mint(address(target), 100 * USDC);

        // distribute() must succeed — reentrant call is absorbed by nonReentrant guard
        target.distribute();

        // Each member got their fair 50% — reentrancy did not inflate balances
        assertEq(rToken.balanceOf(alice), 50 * USDC);
        assertEq(rToken.balanceOf(bob),   50 * USDC);
        assertEq(rToken.balanceOf(address(target)), 0);
    }
}
