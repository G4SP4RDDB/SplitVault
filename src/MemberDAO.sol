// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SplitVault.sol";

/// @dev Minimal interface so MemberDAO can call ENSManager without importing it.
interface IENSManager {
    function registerSubname(address addr, string calldata label) external;
}

/// @title MemberDAO
/// @notice Governs the addition of new members to SplitVault via on-chain majority voting.
///
/// Flow:
///   1. An existing member calls proposeMember(newAddr, newPercentages).
///   2. Members vote yes/no within the voting window.
///   3. After the window closes, anyone calls executeProposal(id).
///      - If ≥66% of current members voted yes → new member is added to SplitVault.
///      - Otherwise the proposal is rejected (or marked expired if vault state changed).
///
/// The DAO must be the owner of SplitVault to execute membership changes.
/// Setup: deploy vault → deploy DAO → vault.transferOwnership(address(dao)).
contract MemberDAO {
    // -------------------------------------------------------------------------
    // Types
    // -------------------------------------------------------------------------

    enum ProposalType { AddMember, Repartition }

    struct Proposal {
        ProposalType proposalType;
        address proposer;
        address newMember;           // address(0) for Repartition proposals
        string  label;               // ENS subdomain label for the new member ("" for Repartition)
        uint256[] newPercentages;    // currentCount+1 for AddMember, currentCount for Repartition
        uint256 deadline;            // voting closes at this timestamp
        uint256 yesVotes;
        uint256 noVotes;
        bool executed;               // consumed once executeProposal is called
        uint256 snapshotMemberCount; // member count at creation — stale-state guard
    }

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    SplitVault   public immutable vault;
    uint256      public immutable votingDuration; // in seconds
    /// @dev Optional ENS manager — address(0) disables subname registration.
    ///      Mutable so it can be set after deployment (e.g. via VaultFactory flow).
    IENSManager  public ensManager;

    uint256 public proposalCount;

    /// @dev proposalId → Proposal
    mapping(uint256 => Proposal) private _proposals;

    /// @dev proposalId → voter → has voted
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @dev Minimum yes-vote percentage required (integer, out of 100).
    uint256 public constant QUORUM_PERCENT = 66;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address indexed newMember,
        uint256 deadline
    );
    event RepartitionProposed(
        uint256 indexed proposalId,
        address indexed proposer,
        uint256 deadline
    );
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support);
    event ProposalPassed(uint256 indexed proposalId, address indexed newMember);
    event ProposalRejected(uint256 indexed proposalId);
    /// @dev Emitted when the vault's member count changed since proposal creation,
    ///      making the stored newPercentages array invalid.
    event ProposalExpired(uint256 indexed proposalId);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error NotAMember();
    error ProposalNotFound();
    error VotingClosed();
    error VotingStillOpen();
    error AlreadyVoted();
    error AlreadyExecuted();
    error NewMemberAlreadyExists();
    error ArrayLengthMismatch();

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyMember() {
        if (!_isMember(msg.sender)) revert NotAMember();
        _;
    }


    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @param _vault          Address of the SplitVault this DAO governs.
    /// @param _votingDuration Duration of the voting window in seconds (e.g. 1 days).
    /// @param _ensManager     Address of the ENSManager contract (address(0) = no ENS).
    constructor(address payable _vault, uint256 _votingDuration, address _ensManager) {
        vault          = SplitVault(_vault);
        votingDuration = _votingDuration;
        ensManager     = IENSManager(_ensManager);
    }

    // -------------------------------------------------------------------------
    // ENS configuration
    // -------------------------------------------------------------------------

    /// @notice Sets or updates the ENSManager after deployment.
    ///         Callable by any current vault member so the DAO can wire ENS later
    ///         without redeploying. Pass address(0) to disable.
    function setENSManager(address _ensManager) external onlyMember {
        ensManager = IENSManager(_ensManager);
    }

    // -------------------------------------------------------------------------
    // Propose
    // -------------------------------------------------------------------------

    /// @notice Opens a vote to add a new member to SplitVault.
    /// @param newMember       Candidate address — must not already be a member.
    /// @param newPercentages  Full redistribution array for all members AFTER addition.
    ///                        Length must be currentMemberCount + 1.
    ///                        Existing members listed first (same order), new member last.
    ///                        Percentages are validated by SplitVault on execution.
    /// @return proposalId     ID of the newly created proposal.
    function proposeMember(
        address newMember,
        uint256[] calldata newPercentages,
        string  calldata label
    ) external onlyMember returns (uint256 proposalId) {
        (address[] memory current,) = vault.getMembers();
        uint256 currentCount = current.length;

        // Candidate must not already be a member
        for (uint256 i = 0; i < currentCount; i++) {
            if (current[i] == newMember) revert NewMemberAlreadyExists();
        }

        // newPercentages must cover all existing members + 1 for the new member
        if (newPercentages.length != currentCount + 1) revert ArrayLengthMismatch();

        proposalId = proposalCount++;

        Proposal storage p = _proposals[proposalId];
        p.proposalType        = ProposalType.AddMember;
        p.proposer            = msg.sender;
        p.newMember           = newMember;
        p.label               = label;
        p.newPercentages      = newPercentages;
        p.deadline            = block.timestamp + votingDuration;
        p.snapshotMemberCount = currentCount;

        emit ProposalCreated(proposalId, msg.sender, newMember, p.deadline);
    }

    /// @notice Opens a vote to change the percentage shares of existing members.
    /// @param newPercentages  New shares for ALL current members (same order, same length).
    ///                        Must sum to 100, no zeros. Validated by SplitVault on execution.
    /// @return proposalId     ID of the newly created proposal.
    function proposeRepartition(
        uint256[] calldata newPercentages
    ) external onlyMember returns (uint256 proposalId) {
        (address[] memory current,) = vault.getMembers();
        uint256 currentCount = current.length;

        // Must provide exactly one percentage per existing member
        if (newPercentages.length != currentCount) revert ArrayLengthMismatch();

        proposalId = proposalCount++;

        Proposal storage p = _proposals[proposalId];
        p.proposalType        = ProposalType.Repartition;
        p.proposer            = msg.sender;
        // p.newMember stays address(0)
        p.newPercentages      = newPercentages;
        p.deadline            = block.timestamp + votingDuration;
        p.snapshotMemberCount = currentCount;

        emit RepartitionProposed(proposalId, msg.sender, p.deadline);
    }

    // -------------------------------------------------------------------------
    // Vote
    // -------------------------------------------------------------------------

    /// @notice Cast a yes or no vote on an open proposal.
    ///         Each member gets exactly one vote per proposal.
    /// @param proposalId Identifier returned by proposeMember.
    /// @param support    true = approve, false = reject.
    function vote(uint256 proposalId, bool support) external onlyMember {
        if (proposalId >= proposalCount)          revert ProposalNotFound();

        Proposal storage p = _proposals[proposalId];

        if (p.executed)                           revert AlreadyExecuted();
        if (block.timestamp > p.deadline)         revert VotingClosed();
        if (hasVoted[proposalId][msg.sender])     revert AlreadyVoted();

        hasVoted[proposalId][msg.sender] = true;

        if (support) {
            p.yesVotes++;
        } else {
            p.noVotes++;
        }

        emit VoteCast(proposalId, msg.sender, support);
    }

    // -------------------------------------------------------------------------
    // Execute
    // -------------------------------------------------------------------------

    /// @notice Execute a proposal after its voting window has closed.
    ///         Permissionless — anyone may trigger execution.
    ///
    ///         Outcomes:
    ///           - ProposalExpired  : vault member count changed since creation (stale array).
    ///           - ProposalRejected : yes-votes < 66% of current member count.
    ///           - ProposalPassed   : quorum met → MemberAdded emitted by SplitVault.
    function executeProposal(uint256 proposalId) external {
        if (proposalId >= proposalCount)       revert ProposalNotFound();

        Proposal storage p = _proposals[proposalId];

        if (p.executed)                        revert AlreadyExecuted();
        if (block.timestamp <= p.deadline)     revert VotingStillOpen();

        // Mark consumed before any external calls (CEI pattern)
        p.executed = true;

        // Re-read current member count
        (address[] memory current,) = vault.getMembers();
        uint256 currentCount = current.length;

        // Guard: if membership changed the stored percentages array is stale
        if (currentCount != p.snapshotMemberCount) {
            emit ProposalExpired(proposalId);
            return;
        }

        // 66% quorum: yesVotes * 100 >= totalMembers * QUORUM_PERCENT
        if (p.yesVotes * 100 < currentCount * QUORUM_PERCENT) {
            emit ProposalRejected(proposalId);
            return;
        }

        // Quorum reached — delegate to SplitVault based on proposal type
        emit ProposalPassed(proposalId, p.newMember);

        if (p.proposalType == ProposalType.AddMember) {
            vault.addMember(p.newMember, p.newPercentages);
            // Register the ENS subname if an ENSManager has been wired up
            if (address(ensManager) != address(0)) {
                ensManager.registerSubname(p.newMember, p.label);
            }
        } else {
            vault.updateShares(p.newPercentages);
        }
    }

    // -------------------------------------------------------------------------
    // View helpers
    // -------------------------------------------------------------------------

    function getProposal(uint256 proposalId)
        external
        view
        returns (
            ProposalType proposalType,
            address proposer,
            address newMember,
            uint256[] memory newPercentages,
            uint256 deadline,
            uint256 yesVotes,
            uint256 noVotes,
            bool executed,
            uint256 snapshotMemberCount,
            string memory label
        )
    {
        if (proposalId >= proposalCount) revert ProposalNotFound();
        Proposal storage p = _proposals[proposalId];
        return (
            p.proposalType,
            p.proposer,
            p.newMember,
            p.newPercentages,
            p.deadline,
            p.yesVotes,
            p.noVotes,
            p.executed,
            p.snapshotMemberCount,
            p.label
        );
    }

    /// @notice Returns true if the proposal currently meets the 66% quorum.
    function isQuorumReached(uint256 proposalId) external view returns (bool) {
        if (proposalId >= proposalCount) revert ProposalNotFound();
        Proposal storage p = _proposals[proposalId];
        (address[] memory members,) = vault.getMembers();
        return p.yesVotes * 100 >= members.length * QUORUM_PERCENT;
    }

    // -------------------------------------------------------------------------
    // Internal
    // -------------------------------------------------------------------------

    function _isMember(address addr) internal view returns (bool) {
        (address[] memory addrs,) = vault.getMembers();
        for (uint256 i = 0; i < addrs.length; i++) {
            if (addrs[i] == addr) return true;
        }
        return false;
    }
}
