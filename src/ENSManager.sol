// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ENSManager
/// @notice Manages ENS subdomain registration for SplitVault members.
///
/// Separation of concerns:
///   SplitVault  → holds ETH, tracks shares
///   MemberDAO   → governance (voting)
///   ENSManager  → naming (this contract)
///
/// Setup (before transferring vault ownership to DAO):
///   1. Register a parent ENS name off-chain (e.g. "myvault.eth").
///   2. Transfer ownership of that name to this contract in the ENS registry.
///   3. Deploy ENSManager(registry, resolver, namehash("myvault.eth")).
///   4. Call bootstrapSubnames([addr0, addr1, ...], ["alice", "bob", ...]) for initial members.
///   5. Call setAuthorizedCaller(address(dao)) so the DAO can register future members.
///
/// Registry addresses:
///   ENS Registry  (mainnet + Sepolia): 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e
///   Public Resolver (Sepolia):         0x8FADE66B79cC9f707aB26799354482EB93a5B7dD
///   Public Resolver (mainnet):         0x231b0Ee14048e9dCcD1d247744d114a4EB5E8E63

interface IENSRegistry {
    /// @dev Creates or updates a subnode, setting owner, resolver and TTL atomically.
    function setSubnodeRecord(
        bytes32 node,
        bytes32 label,
        address owner,
        address resolver,
        uint64  ttl
    ) external;
}

interface IPublicResolver {
    /// @dev Points an ENS node to an Ethereum address.
    function setAddr(bytes32 node, address addr) external;
}

contract ENSManager {
    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    IENSRegistry    public immutable ensRegistry;
    IPublicResolver public immutable publicResolver;
    /// @dev namehash of the vault's parent ENS name (e.g. namehash("myvault.eth")).
    ///      This contract must own that name in the ENS registry.
    bytes32         public immutable vaultNode;

    address public owner;
    /// @dev Address allowed to call registerSubname — set to the MemberDAO after deployment.
    address public authorizedCaller;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event SubnameRegistered(address indexed addr, string label);
    event AuthorizedCallerSet(address indexed caller);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error NotOwner();
    error NotAuthorized();
    error ZeroAddress();
    error BootstrapLengthMismatch();

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @dev Owner OR the authorized caller (DAO) may register subnames.
    modifier onlyAuthorized() {
        if (msg.sender != owner && msg.sender != authorizedCaller) revert NotAuthorized();
        _;
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @param registry  ENS Registry address.
    /// @param resolver  Public Resolver address.
    /// @param node      namehash of the vault's parent ENS name.
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

    /// @notice Authorizes an address (typically the MemberDAO) to register subnames.
    ///         Must be called after the DAO is deployed, before transferring vault ownership.
    function setAuthorizedCaller(address caller) external onlyOwner {
        if (caller == address(0)) revert ZeroAddress();
        authorizedCaller = caller;
        emit AuthorizedCallerSet(caller);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }

    // -------------------------------------------------------------------------
    // Subname registration
    // -------------------------------------------------------------------------

    /// @notice Registers a subdomain for a newly added vault member.
    ///         Called by MemberDAO after a successful AddMember proposal.
    /// @param addr   The new member's wallet address.
    /// @param label  The subdomain label (e.g. "alice" → "alice.myvault.eth").
    function registerSubname(address addr, string calldata label) external onlyAuthorized {
        _register(addr, label);
    }

    /// @notice Registers subnames for the vault's initial members in a single call.
    ///         Must be called by the owner before handing control to the DAO.
    /// @param addrs   Ordered list of member addresses (same order as SplitVault.members).
    /// @param labels  Corresponding subdomain labels.
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

    /// @dev Computes the subnode hash, calls setSubnodeRecord on the ENS registry,
    ///      then sets the addr record in the public resolver.
    function _register(address addr, string memory label) internal {
        bytes32 labelHash   = keccak256(bytes(label));
        bytes32 subnodeHash = keccak256(abi.encodePacked(vaultNode, labelHash));

        // Step 1: create the subnode with ENSManager as owner so we are
        //         authorised to write records into the resolver.
        ensRegistry.setSubnodeRecord(
            vaultNode,
            labelHash,
            address(this),          // ENSManager owns the subnode temporarily
            address(publicResolver),
            0
        );

        // Step 2: point the addr record to the member's wallet.
        //         The resolver checks owner == msg.sender, so this must happen
        //         while ENSManager is still the owner.
        if (address(publicResolver) != address(0)) {
            publicResolver.setAddr(subnodeHash, addr);
        }

        emit SubnameRegistered(addr, label);
    }
}
