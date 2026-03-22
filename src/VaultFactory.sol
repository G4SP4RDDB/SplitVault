// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./SplitVault.sol";
import "./MemberDAO.sol";
import "./VaultRegistry.sol";

/// @title VaultFactory
/// @notice Deploys a SplitVault + MemberDAO pair in a single transaction,
///         optionally books an ENS subdomain for the vault, wires ownership,
///         and registers the vault in VaultRegistry.
///
/// If ensManager is set, createVault requires a non-empty label and will:
///   - register `label.vaulthack.eth` pointing to the vault contract address
///   - wire the ENSManager into the MemberDAO so future member additions also get subnames
contract VaultFactory {
    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    address      public immutable token;
    VaultRegistry public immutable registry;
    IENSManager  public immutable ensManager;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event VaultCreated(
        address indexed creator,
        address indexed vault,
        address indexed dao,
        string  label
    );

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error ZeroAddress();
    error EmptyLabel();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @param _token       ERC-20 token address (e.g. USDC on Sepolia).
    /// @param _registry    VaultRegistry address.
    /// @param _ensManager  ENSManager address — address(0) disables ENS booking.
    constructor(address _token, address _registry, address _ensManager) {
        if (_token    == address(0)) revert ZeroAddress();
        if (_registry == address(0)) revert ZeroAddress();
        token      = _token;
        registry   = VaultRegistry(_registry);
        ensManager = IENSManager(_ensManager);
    }

    // -------------------------------------------------------------------------
    // Factory
    // -------------------------------------------------------------------------

    /// @notice Deploys a fully wired SplitVault + MemberDAO in one transaction.
    ///         If an ENSManager is configured, also books `label.vaulthack.eth`
    ///         pointing to the vault contract address.
    ///
    /// @param members         Initial member addresses (non-empty, no duplicates).
    /// @param percentages     Corresponding shares (must sum to 100, no zeros).
    /// @param votingDuration  Voting window in seconds (e.g. 1 days).
    /// @param label           ENS subdomain label for the vault (required when ensManager is set).
    /// @return vault  Address of the deployed SplitVault.
    /// @return dao    Address of the deployed MemberDAO (vault owner).
    function createVault(
        address[] calldata members,
        uint256[] calldata percentages,
        uint256            votingDuration,
        string  calldata   label
    ) external returns (address vault, address dao) {
        bool hasENS = address(ensManager) != address(0);
        if (hasENS && bytes(label).length == 0) revert EmptyLabel();

        // 1. Deploy SplitVault — factory is temporarily the owner
        SplitVault _vault = new SplitVault(token, members, percentages);

        // 2. Deploy MemberDAO, wiring ENSManager from the start so member additions
        //    automatically register subnames without a separate setENSManager call.
        MemberDAO _dao = new MemberDAO(
            payable(address(_vault)),
            votingDuration,
            hasENS ? address(ensManager) : address(0)
        );

        // 3. Hand vault ownership to the DAO
        _vault.transferOwnership(address(_dao));

        // 4. Book the vault's ENS subdomain (label.vaulthack.eth → vault address)
        if (hasENS) {
            ensManager.registerSubname(address(_vault), label);
        }

        // 5. Register in the public directory
        registry.register(address(_vault));

        emit VaultCreated(msg.sender, address(_vault), address(_dao), label);

        return (address(_vault), address(_dao));
    }
}
