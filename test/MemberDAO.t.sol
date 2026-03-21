// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/SplitVault.sol";
import "../src/MemberDAO.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}
    function decimals() public pure override returns (uint8) { return 6; }
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract MemberDAOTest is Test {
    MockUSDC   usdc;
    SplitVault vault;
    MemberDAO  dao;

    uint256 constant USDC = 1_000_000; // 1 USDC in raw units

    address alice   = makeAddr("alice");
    address bob     = makeAddr("bob");
    address charlie = makeAddr("charlie");
    address dave    = makeAddr("dave");   // candidate in most tests
    address eve     = makeAddr("eve");    // candidate for second-proposal tests
    address outsider = makeAddr("outsider");

    uint256 constant VOTING_DURATION = 1 days;

    // Default redistribution when dave is added: alice 40%, bob 25%, charlie 15%, dave 20%
    uint256[] davePcts;

    function setUp() public {
        // Deploy token + vault: alice 50%, bob 30%, charlie 20%
        usdc = new MockUSDC();
        address[] memory addrs = new address[](3);
        uint256[] memory pcts  = new uint256[](3);
        addrs[0] = alice;   pcts[0] = 50;
        addrs[1] = bob;     pcts[1] = 30;
        addrs[2] = charlie; pcts[2] = 20;
        vault = new SplitVault(address(usdc), addrs, pcts);

        // Deploy DAO and hand over vault ownership (no ENSManager in base tests)
        dao = new MemberDAO(payable(address(vault)), VOTING_DURATION, address(0));
        vault.transferOwnership(address(dao));

        // Reusable percentages array for adding dave
        davePcts = new uint256[](4);
        davePcts[0] = 40; davePcts[1] = 25; davePcts[2] = 15; davePcts[3] = 20;
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    /// Open a proposal as alice and return its id.
    function _propose(address candidate, uint256[] memory pcts) internal returns (uint256) {
        vm.prank(alice);
        return dao.proposeMember(candidate, pcts, "dave");
    }

    /// alice votes yes, bob votes yes (2/3 = 66.7% — passes quorum).
    function _twoYesVotes(uint256 proposalId) internal {
        vm.prank(alice);   dao.vote(proposalId, true);
        vm.prank(bob);     dao.vote(proposalId, true);
    }

    /// Warp past the voting deadline.
    function _warpPastDeadline() internal {
        vm.warp(block.timestamp + VOTING_DURATION + 1);
    }

    // =========================================================================
    // proposeMember
    // =========================================================================

    function test_ProposeMember() public {
        vm.expectEmit(true, true, true, false);
        emit MemberDAO.ProposalCreated(0, alice, dave, 0);

        uint256 id = _propose(dave, davePcts);

        assertEq(id, 0);
        assertEq(dao.proposalCount(), 1);

        (, address proposer, address newMember,,,,, bool executed, uint256 snap,) =
            dao.getProposal(0);

        assertEq(proposer,   alice);
        assertEq(newMember,  dave);
        assertEq(executed,   false);
        assertEq(snap,       3); // snapshot of current member count
    }

    function test_RevertIf_ProposeMember_NotMember() public {
        vm.prank(outsider);
        vm.expectRevert(MemberDAO.NotAMember.selector);
        dao.proposeMember(dave, davePcts, "dave");
    }

    function test_RevertIf_ProposeMember_AlreadyMember() public {
        vm.prank(alice);
        vm.expectRevert(MemberDAO.NewMemberAlreadyExists.selector);
        dao.proposeMember(alice, davePcts, "alice"); // alice is already in the vault
    }

    function test_RevertIf_ProposeMember_WrongArrayLength() public {
        uint256[] memory badPcts = new uint256[](3); // should be 4
        badPcts[0] = 34; badPcts[1] = 33; badPcts[2] = 33;

        vm.prank(alice);
        vm.expectRevert(MemberDAO.ArrayLengthMismatch.selector);
        dao.proposeMember(dave, badPcts, "dave");
    }

    // =========================================================================
    // vote
    // =========================================================================

    function test_Vote_Yes() public {
        uint256 id = _propose(dave, davePcts);

        vm.expectEmit(true, true, false, true);
        emit MemberDAO.VoteCast(id, alice, true);

        vm.prank(alice);
        dao.vote(id, true);

        (,,,,,uint256 yesVotes, uint256 noVotes,,,) = dao.getProposal(id);
        assertEq(yesVotes, 1);
        assertEq(noVotes,  0);
        assertTrue(dao.hasVoted(id, alice));
    }

    function test_Vote_No() public {
        uint256 id = _propose(dave, davePcts);

        vm.prank(bob);
        dao.vote(id, false);

        (,,,,, uint256 yesVotes, uint256 noVotes,,,) = dao.getProposal(id);
        assertEq(yesVotes, 0);
        assertEq(noVotes,  1);
    }

    function test_RevertIf_Vote_NotMember() public {
        uint256 id = _propose(dave, davePcts);

        vm.prank(outsider);
        vm.expectRevert(MemberDAO.NotAMember.selector);
        dao.vote(id, true);
    }

    function test_RevertIf_Vote_ProposalNotFound() public {
        vm.prank(alice);
        vm.expectRevert(MemberDAO.ProposalNotFound.selector);
        dao.vote(99, true);
    }

    function test_RevertIf_Vote_VotingClosed() public {
        uint256 id = _propose(dave, davePcts);
        _warpPastDeadline();

        vm.prank(alice);
        vm.expectRevert(MemberDAO.VotingClosed.selector);
        dao.vote(id, true);
    }

    function test_RevertIf_Vote_AlreadyVoted() public {
        uint256 id = _propose(dave, davePcts);

        vm.prank(alice);
        dao.vote(id, true);

        vm.prank(alice);
        vm.expectRevert(MemberDAO.AlreadyVoted.selector);
        dao.vote(id, true);
    }

    function test_RevertIf_Vote_AlreadyExecuted() public {
        uint256 id = _propose(dave, davePcts);
        _twoYesVotes(id);
        _warpPastDeadline();
        dao.executeProposal(id);

        vm.prank(charlie);
        vm.expectRevert(MemberDAO.AlreadyExecuted.selector);
        dao.vote(id, true);
    }

    // =========================================================================
    // executeProposal — reverts
    // =========================================================================

    function test_RevertIf_Execute_ProposalNotFound() public {
        vm.expectRevert(MemberDAO.ProposalNotFound.selector);
        dao.executeProposal(99);
    }

    function test_RevertIf_Execute_VotingStillOpen() public {
        uint256 id = _propose(dave, davePcts);
        _twoYesVotes(id);

        // Deadline has NOT passed yet
        vm.expectRevert(MemberDAO.VotingStillOpen.selector);
        dao.executeProposal(id);
    }

    function test_RevertIf_Execute_AlreadyExecuted() public {
        uint256 id = _propose(dave, davePcts);
        _twoYesVotes(id);
        _warpPastDeadline();
        dao.executeProposal(id);

        vm.expectRevert(MemberDAO.AlreadyExecuted.selector);
        dao.executeProposal(id);
    }

    // =========================================================================
    // executeProposal — outcomes
    // =========================================================================

    function test_ExecuteProposal_Passes() public {
        uint256 id = _propose(dave, davePcts);
        _twoYesVotes(id); // alice + bob = 2/3 = 66.7%
        _warpPastDeadline();

        vm.expectEmit(true, true, false, false);
        emit MemberDAO.ProposalPassed(id, dave);

        dao.executeProposal(id);

        // Verify dave is now in the vault
        (address[] memory addrs, uint256[] memory pcts) = vault.getMembers();
        assertEq(addrs.length, 4);
        assertEq(addrs[3], dave);
        assertEq(pcts[3],  20);
    }

    function test_ExecuteProposal_Rejected() public {
        uint256 id = _propose(dave, davePcts);

        // Only alice votes yes: 1/3 = 33% < 66%
        vm.prank(alice);
        dao.vote(id, true);

        _warpPastDeadline();

        vm.expectEmit(true, false, false, false);
        emit MemberDAO.ProposalRejected(id);

        dao.executeProposal(id);

        // Dave must NOT be in the vault
        (address[] memory addrs,) = vault.getMembers();
        assertEq(addrs.length, 3);
    }

    function test_ExecuteProposal_NoVotes_Rejected() public {
        uint256 id = _propose(dave, davePcts);
        // Nobody votes
        _warpPastDeadline();

        vm.expectEmit(true, false, false, false);
        emit MemberDAO.ProposalRejected(id);

        dao.executeProposal(id);

        (address[] memory addrs,) = vault.getMembers();
        assertEq(addrs.length, 3);
    }

    /// @dev Exactly 2/3 yes votes — boundary condition, must pass.
    function test_ExecuteProposal_ExactlyQuorum() public {
        uint256 id = _propose(dave, davePcts);
        _twoYesVotes(id); // 2 out of 3 = 66.67% ≥ 66%
        _warpPastDeadline();

        dao.executeProposal(id);

        (address[] memory addrs,) = vault.getMembers();
        assertEq(addrs.length, 4);
    }

    /// @dev If another proposal was executed first, the member count changed —
    ///      the second proposal's percentages array is stale → ProposalExpired.
    function test_ExecuteProposal_Expired_WhenMemberCountChanged() public {
        // Proposal 0: add dave
        uint256 idDave = _propose(dave, davePcts);

        // Proposal 1: add eve (snapshot is also 3 members)
        uint256[] memory evePcts = new uint256[](4);
        evePcts[0] = 35; evePcts[1] = 25; evePcts[2] = 20; evePcts[3] = 20;
        uint256 idEve = _propose(eve, evePcts);

        // Both proposals get quorum
        _twoYesVotes(idDave);
        _twoYesVotes(idEve);
        _warpPastDeadline();

        // Execute proposal 0 → dave added, vault now has 4 members
        dao.executeProposal(idDave);
        (address daveAddr,) = vault.members(3);
        assertEq(daveAddr, dave);

        // Execute proposal 1 → snapshot was 3, current is 4 → ProposalExpired
        vm.expectEmit(true, false, false, false);
        emit MemberDAO.ProposalExpired(idEve);

        dao.executeProposal(idEve);

        // Eve must NOT have been added
        (address[] memory addrs,) = vault.getMembers();
        assertEq(addrs.length, 4);
    }

    // =========================================================================
    // Full flow
    // =========================================================================

    function test_FullFlow_ProposeVoteExecuteDistribute() public {
        // Step 1 — propose
        uint256 id = _propose(dave, davePcts);

        // Step 2 — two members vote yes, one votes no
        vm.prank(alice);   dao.vote(id, true);
        vm.prank(bob);     dao.vote(id, true);
        vm.prank(charlie); dao.vote(id, false);

        // Step 3 — warp past deadline
        _warpPastDeadline();

        // Step 4 — execute
        dao.executeProposal(id);

        // Step 5 — verify vault state: 4 members with updated shares
        (address[] memory addrs, uint256[] memory pcts) = vault.getMembers();
        assertEq(addrs.length, 4);
        assertEq(addrs[0], alice);   assertEq(pcts[0], 40);
        assertEq(addrs[1], bob);     assertEq(pcts[1], 25);
        assertEq(addrs[2], charlie); assertEq(pcts[2], 15);
        assertEq(addrs[3], dave);    assertEq(pcts[3], 20);

        // Step 6 — fund and distribute with the new split
        usdc.mint(address(this), 100 * USDC);
        usdc.approve(address(vault), 100 * USDC);
        vault.deposit(100 * USDC);
        vault.distribute();

        assertEq(usdc.balanceOf(alice),   40 * USDC);
        assertEq(usdc.balanceOf(bob),     25 * USDC);
        assertEq(usdc.balanceOf(charlie), 15 * USDC);
        assertEq(usdc.balanceOf(dave),    20 * USDC);
    }

    // =========================================================================
    // View helpers
    // =========================================================================

    function test_IsQuorumReached_False() public {
        uint256 id = _propose(dave, davePcts);

        vm.prank(alice);
        dao.vote(id, true); // 1/3 = 33%

        assertFalse(dao.isQuorumReached(id));
    }

    function test_IsQuorumReached_True() public {
        uint256 id = _propose(dave, davePcts);
        _twoYesVotes(id); // 2/3 = 66.7%

        assertTrue(dao.isQuorumReached(id));
    }

    function test_GetProposal_RevertIf_NotFound() public {
        vm.expectRevert(MemberDAO.ProposalNotFound.selector);
        dao.getProposal(0);
    }

    // =========================================================================
    // Access control — vault ownership
    // =========================================================================

    /// @dev SplitVault.addMember can no longer be called directly — only DAO can.
    function test_DirectAddMember_RevertsForEveryone() public {
        // Even alice (a member) cannot bypass the DAO
        vm.prank(alice);
        vm.expectRevert(SplitVault.NotOwner.selector);
        vault.addMember(dave, davePcts);

        // The original deployer (this test contract) also cannot
        vm.expectRevert(SplitVault.NotOwner.selector);
        vault.addMember(dave, davePcts);
    }

    // =========================================================================
    // proposeRepartition
    // =========================================================================

    function test_ProposeRepartition() public {
        // alice proposes: alice 60%, bob 25%, charlie 15%
        uint256[] memory newPcts = new uint256[](3);
        newPcts[0] = 60; newPcts[1] = 25; newPcts[2] = 15;

        vm.expectEmit(true, true, false, false);
        emit MemberDAO.RepartitionProposed(0, alice, 0);

        vm.prank(alice);
        uint256 id = dao.proposeRepartition(newPcts);

        assertEq(id, 0);
        (MemberDAO.ProposalType pType,,,,,,,,, ) = dao.getProposal(id);
        assertEq(uint256(pType), uint256(MemberDAO.ProposalType.Repartition));
    }

    function test_RevertIf_ProposeRepartition_NotMember() public {
        uint256[] memory newPcts = new uint256[](3);
        newPcts[0] = 60; newPcts[1] = 25; newPcts[2] = 15;

        vm.prank(outsider);
        vm.expectRevert(MemberDAO.NotAMember.selector);
        dao.proposeRepartition(newPcts);
    }

    function test_RevertIf_ProposeRepartition_WrongArrayLength() public {
        uint256[] memory newPcts = new uint256[](4); // should be 3
        newPcts[0] = 40; newPcts[1] = 30; newPcts[2] = 20; newPcts[3] = 10;

        vm.prank(alice);
        vm.expectRevert(MemberDAO.ArrayLengthMismatch.selector);
        dao.proposeRepartition(newPcts);
    }

    function test_ExecuteRepartition_Passes() public {
        uint256[] memory newPcts = new uint256[](3);
        newPcts[0] = 60; newPcts[1] = 25; newPcts[2] = 15;

        vm.prank(alice);
        uint256 id = dao.proposeRepartition(newPcts);

        _twoYesVotes(id);
        _warpPastDeadline();
        dao.executeProposal(id);

        (, uint256[] memory pcts) = vault.getMembers();
        assertEq(pcts[0], 60);
        assertEq(pcts[1], 25);
        assertEq(pcts[2], 15);
    }

    function test_ExecuteRepartition_Rejected() public {
        uint256[] memory newPcts = new uint256[](3);
        newPcts[0] = 60; newPcts[1] = 25; newPcts[2] = 15;

        vm.prank(alice);
        uint256 id = dao.proposeRepartition(newPcts);

        // Only 1/3 votes yes — rejected
        vm.prank(alice);
        dao.vote(id, true);

        _warpPastDeadline();

        vm.expectEmit(true, false, false, false);
        emit MemberDAO.ProposalRejected(id);
        dao.executeProposal(id);

        // Shares must be unchanged
        (, uint256[] memory pcts) = vault.getMembers();
        assertEq(pcts[0], 50);
        assertEq(pcts[1], 30);
        assertEq(pcts[2], 20);
    }

    function test_FullFlow_Repartition() public {
        uint256[] memory newPcts = new uint256[](3);
        newPcts[0] = 60; newPcts[1] = 25; newPcts[2] = 15;

        vm.prank(alice);
        uint256 id = dao.proposeRepartition(newPcts);

        vm.prank(alice);   dao.vote(id, true);
        vm.prank(bob);     dao.vote(id, true);
        vm.prank(charlie); dao.vote(id, false);

        _warpPastDeadline();
        dao.executeProposal(id);

        // Distribute and verify new split
        usdc.mint(address(this), 100 * USDC);
        usdc.approve(address(vault), 100 * USDC);
        vault.deposit(100 * USDC);
        vault.distribute();

        assertEq(usdc.balanceOf(alice),   60 * USDC);
        assertEq(usdc.balanceOf(bob),     25 * USDC);
        assertEq(usdc.balanceOf(charlie), 15 * USDC);
    }

    // =========================================================================
    // Permissionless execution
    // =========================================================================

    /// @dev Anyone (even a non-member) can trigger executeProposal once the window closes.
    function test_AnyoneCanExecute() public {
        uint256 id = _propose(dave, davePcts);
        _twoYesVotes(id);
        _warpPastDeadline();

        // outsider (not a member) executes
        vm.prank(outsider);
        dao.executeProposal(id);

        (address[] memory addrs,) = vault.getMembers();
        assertEq(addrs.length, 4);
    }
}
