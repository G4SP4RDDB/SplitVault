// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SplitVault.sol";
import "./MemberDAO.sol";
import "./VaultRegistry.sol";

/// @title VaultFactory
/// @notice Deploys a SplitVault + MemberDAO pair in a single transaction,
///         wires ownership, and registers the vault in VaultRegistry.
///
/// ENSManager is intentionally excluded — ENS requires the creator to have
/// already registered a .eth name, so it is set up separately via
/// MemberDAO.setENSManager() after the vault is live.
contract VaultFactory {
    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /// @dev ERC-20 token (USDC) accepted by every vault created through this factory.
    address public immutable token;

    /// @dev Registry where every new vault is recorded for frontend discovery.
    VaultRegistry public immutable registry;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event VaultCreated(
        address indexed creator,
        address indexed vault,
        address indexed dao
    );

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error ZeroAddress();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @param _token    ERC-20 token address (e.g. USDC on Sepolia).
    /// @param _registry VaultRegistry address.
    constructor(address _token, address _registry) {
        if (_token    == address(0)) revert ZeroAddress();
        if (_registry == address(0)) revert ZeroAddress();
        token    = _token;
        registry = VaultRegistry(_registry);
    }

    // -------------------------------------------------------------------------
    // Factory
    // -------------------------------------------------------------------------

    /// @notice Deploys a fully wired SplitVault + MemberDAO in one transaction.
    /// @param members         Initial member addresses (non-empty, no duplicates).
    /// @param percentages     Corresponding shares (must sum to 100, no zeros).
    /// @param votingDuration  Voting window in seconds (e.g. 1 days).
    /// @return vault  Address of the deployed SplitVault.
    /// @return dao    Address of the deployed MemberDAO (vault owner).
    function createVault(
        address[] calldata members,
        uint256[] calldata percentages,
        uint256            votingDuration
    ) external returns (address vault, address dao) {
        // 1. Deploy SplitVault — factory is temporarily the owner
        SplitVault _vault = new SplitVault(token, members, percentages);

        // 2. Deploy MemberDAO with no ENSManager (set later via setENSManager)
        MemberDAO _dao = new MemberDAO(
            payable(address(_vault)),
            votingDuration,
            address(0)
        );

        // 3. Hand vault ownership to the DAO
        _vault.transferOwnership(address(_dao));

        // 4. Register in the public directory
        registry.register(address(_vault));

        emit VaultCreated(msg.sender, address(_vault), address(_dao));

        return (address(_vault), address(_dao));
    }
}
