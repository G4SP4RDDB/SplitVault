// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ENSManager
/// @notice Manages ENS subdomain registration for SplitVault members.
///
/// Separation of concerns:
///   SplitVault  → holds USDC, tracks shares
///   MemberDAO   → governance (voting)
///   ENSManager  → naming (this contract)
///
/// Setup:
///   1. Register a parent ENS name off-chain (e.g. "vaulthack.eth").
///   2. Transfer ownership of that name to this contract in the ENS registry.
///   3. Deploy ENSManager(registry, resolver, namehash("vaulthack.eth")).
///   4. Deploy VaultFactory(token, registry, address(this)).
///   5. addAuthorizedCaller(address(factory)) — factory registers vault names.
///   6. After each vault is created, addAuthorizedCaller(daoAddr) — DAO registers member names.
///
/// Registry addresses:
///   ENS Registry  (mainnet + Sepolia): 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e
///   Public Resolver (Sepolia):         0x8FADE66B79cC9f707aB26799354482EB93a5B7dD
///   Public Resolver (mainnet):         0x231b0Ee14048e9dCcD1d247744d114a4EB5E8E63

interface IENSRegistry {
    function setSubnodeRecord(
        bytes32 node,
        bytes32 label,
        address owner,
        address resolver,
        uint64  ttl
    ) external;

    /// @dev Returns the owner of a node (address(0) = unregistered).
    function owner(bytes32 node) external view returns (address);
}

interface IPublicResolver {
    function setAddr(bytes32 node, address addr) external;
}

contract ENSManager {
    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    IENSRegistry    public immutable ensRegistry;
    IPublicResolver public immutable publicResolver;
    /// @dev namehash of the vault's parent ENS name (e.g. namehash("vaulthack.eth")).
    ///      This contract must own that name in the ENS registry.
    bytes32         public immutable vaultNode;

    address public owner;

    /// @dev Addresses allowed to call registerSubname (factory + DAOs).
    mapping(address => bool) public authorizedCallers;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event SubnameRegistered(address indexed addr, string label);
    event AuthorizedCallerAdded(address indexed caller);
    event AuthorizedCallerRemoved(address indexed caller);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error NotOwner();
    error NotAuthorized();
    error ZeroAddress();
    error BootstrapLengthMismatch();
    error LabelAlreadyTaken(string label);

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @dev Owner OR any authorized caller (factory, DAO) may register subnames.
    modifier onlyAuthorized() {
        if (msg.sender != owner && !authorizedCallers[msg.sender]) revert NotAuthorized();
        _;
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address registry, address resolver, bytes32 node) {
        if (registry == address(0)) revert ZeroAddress();
        ensRegistry    = IENSRegistry(registry);
        publicResolver = IPublicResolver(resolver);
        vaultNode      = node;
        owner          = msg.sender;
    }

    // -------------------------------------------------------------------------
    // Configuration
    // -------------------------------------------------------------------------

    /// @notice Grants an address (factory or DAO) permission to register subnames.
    function addAuthorizedCaller(address caller) external onlyOwner {
        if (caller == address(0)) revert ZeroAddress();
        authorizedCallers[caller] = true;
        emit AuthorizedCallerAdded(caller);
    }

    /// @notice Revokes a previously granted caller's permission.
    function removeAuthorizedCaller(address caller) external onlyOwner {
        authorizedCallers[caller] = false;
        emit AuthorizedCallerRemoved(caller);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }

    // -------------------------------------------------------------------------
    // Availability
    // -------------------------------------------------------------------------

    /// @notice Returns true if the label is not yet registered under vaultNode.
    function isLabelAvailable(string calldata label) external view returns (bool) {
        bytes32 labelHash   = keccak256(bytes(label));
        bytes32 subnodeHash = keccak256(abi.encodePacked(vaultNode, labelHash));
        return ensRegistry.owner(subnodeHash) == address(0);
    }

    // -------------------------------------------------------------------------
    // Subname registration
    // -------------------------------------------------------------------------

    /// @notice Registers a subdomain pointing to `addr`.
    ///         Called by the factory (for vault names) and by MemberDAO (for member names).
    /// @param addr   The address the subdomain should resolve to.
    /// @param label  The subdomain label (e.g. "teamvault" or "alice").
    function registerSubname(address addr, string calldata label) external onlyAuthorized {
        _register(addr, label);
    }

    /// @notice Registers subnames for the vault's initial members in a single call.
    ///         Must be called by the owner before handing control to the DAO.
    function bootstrapSubnames(
        address[] calldata addrs,
        string[]  calldata labels
    ) external onlyOwner {
        if (addrs.length != labels.length) revert BootstrapLengthMismatch();
        for (uint256 i = 0; i < addrs.length; i++) {
            _register(addrs[i], labels[i]);
        }
    }

    // -------------------------------------------------------------------------
    // Internal
    // -------------------------------------------------------------------------

    function _register(address addr, string memory label) internal {
        bytes32 labelHash   = keccak256(bytes(label));
        bytes32 subnodeHash = keccak256(abi.encodePacked(vaultNode, labelHash));

        // Revert if this label is already taken
        if (ensRegistry.owner(subnodeHash) != address(0)) revert LabelAlreadyTaken(label);

        // Step 1: create the subnode owned by ENSManager so we can write resolver records
        ensRegistry.setSubnodeRecord(
            vaultNode,
            labelHash,
            address(this),
            address(publicResolver),
            0
        );

        // Step 2: point the addr record to the target address
        if (address(publicResolver) != address(0)) {
            publicResolver.setAddr(subnodeHash, addr);
        }

        emit SubnameRegistered(addr, label);
    }
}
