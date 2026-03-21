// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title VaultRegistry
/// @notice Public directory of all SplitVault instances.
///         Allows the frontend to discover vaults without an external indexer.
///         Registration is permissionless — anyone can list their vault.
///         The frontend verifies legitimacy by reading vault state directly.
contract VaultRegistry {
    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    address[] private _allVaults;
    mapping(address => bool) public isRegistered;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event VaultRegistered(address indexed vault, address indexed registrant);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error AlreadyRegistered();
    error ZeroAddress();

    // -------------------------------------------------------------------------
    // Registration
    // -------------------------------------------------------------------------

    /// @notice Registers a vault address in the directory.
    ///         Permissionless — called by VaultFactory or directly by vault creators.
    /// @param vault Address of the SplitVault to register.
    function register(address vault) external {
        if (vault == address(0))    revert ZeroAddress();
        if (isRegistered[vault])    revert AlreadyRegistered();

        isRegistered[vault] = true;
        _allVaults.push(vault);

        emit VaultRegistered(vault, msg.sender);
    }

    // -------------------------------------------------------------------------
    // View helpers
    // -------------------------------------------------------------------------

    /// @notice Returns all registered vault addresses.
    function getAllVaults() external view returns (address[] memory) {
        return _allVaults;
    }

    /// @notice Total number of registered vaults.
    function vaultCount() external view returns (uint256) {
        return _allVaults.length;
    }
}
