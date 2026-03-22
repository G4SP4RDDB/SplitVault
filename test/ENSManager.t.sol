// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/ENSManager.sol";
import "../src/SplitVault.sol";
import "../src/MemberDAO.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}
    function decimals() public pure override returns (uint8) { return 6; }
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

// =============================================================================
// Mocks
// =============================================================================

contract MockENSRegistry {
    bytes32 public lastNode;
    bytes32 public lastLabel;
    address public lastOwner;
    address public lastResolver;

    /// @dev node → owner (address(0) = unregistered)
    mapping(bytes32 => address) private _owners;

    function setSubnodeRecord(
        bytes32 node,
        bytes32 label,
        address owner_,
        address resolver,
        uint64
    ) external {
        bytes32 subnode = keccak256(abi.encodePacked(node, label));
        _owners[subnode] = owner_;
        lastNode     = node;
        lastLabel    = label;
        lastOwner    = owner_;
        lastResolver = resolver;
    }

    function owner(bytes32 node) external view returns (address) {
        return _owners[node];
    }
}

contract MockPublicResolver {
    bytes32 public lastNode;
    address public lastAddr;

    function setAddr(bytes32 node, address addr) external {
        lastNode = node;
        lastAddr = addr;
    }
}

// =============================================================================
// ENSManager unit tests
// =============================================================================

contract ENSManagerTest is Test {
    ENSManager         ens;
    MockENSRegistry    reg;
    MockPublicResolver res;

    address owner    = makeAddr("owner");
    address alice    = makeAddr("alice");
    address bob      = makeAddr("bob");
    address charlie  = makeAddr("charlie");
    address dao      = makeAddr("dao");
    address factory  = makeAddr("factory");

    bytes32 constant VAULT_NODE = keccak256("myvault.eth");

    function setUp() public {
        reg = new MockENSRegistry();
        res = new MockPublicResolver();

        vm.prank(owner);
        ens = new ENSManager(address(reg), address(res), VAULT_NODE);
    }

    // =========================================================================
    // Constructor
    // =========================================================================

    function test_Constructor_StoresState() public view {
        assertEq(address(ens.ensRegistry()),    address(reg));
        assertEq(address(ens.publicResolver()), address(res));
        assertEq(ens.vaultNode(),               VAULT_NODE);
        assertEq(ens.owner(),                   owner);
    }

    function test_Constructor_RevertIf_ZeroRegistry() public {
        vm.expectRevert(ENSManager.ZeroAddress.selector);
        new ENSManager(address(0), address(res), VAULT_NODE);
    }

    // =========================================================================
    // addAuthorizedCaller / removeAuthorizedCaller
    // =========================================================================

    function test_AddAuthorizedCaller() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit ENSManager.AuthorizedCallerAdded(dao);

        ens.addAuthorizedCaller(dao);
        assertTrue(ens.authorizedCallers(dao));
    }

    function test_AddAuthorizedCaller_MultipleCallers() public {
        vm.prank(owner);
        ens.addAuthorizedCaller(dao);
        vm.prank(owner);
        ens.addAuthorizedCaller(factory);

        assertTrue(ens.authorizedCallers(dao));
        assertTrue(ens.authorizedCallers(factory));
    }

    function test_RemoveAuthorizedCaller() public {
        vm.prank(owner);
        ens.addAuthorizedCaller(dao);

        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit ENSManager.AuthorizedCallerRemoved(dao);

        ens.removeAuthorizedCaller(dao);
        assertFalse(ens.authorizedCallers(dao));
    }

    function test_RevertIf_AddAuthorizedCaller_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert(ENSManager.NotOwner.selector);
        ens.addAuthorizedCaller(dao);
    }

    function test_RevertIf_AddAuthorizedCaller_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(ENSManager.ZeroAddress.selector);
        ens.addAuthorizedCaller(address(0));
    }

    function test_RevertIf_RemoveAuthorizedCaller_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert(ENSManager.NotOwner.selector);
        ens.removeAuthorizedCaller(dao);
    }

    // =========================================================================
    // transferOwnership
    // =========================================================================

    function test_TransferOwnership() public {
        vm.prank(owner);
        ens.transferOwnership(alice);
        assertEq(ens.owner(), alice);
    }

    function test_RevertIf_TransferOwnership_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert(ENSManager.NotOwner.selector);
        ens.transferOwnership(bob);
    }

    function test_RevertIf_TransferOwnership_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(ENSManager.ZeroAddress.selector);
        ens.transferOwnership(address(0));
    }

    // =========================================================================
    // isLabelAvailable
    // =========================================================================

    function test_IsLabelAvailable_True_WhenNotRegistered() public view {
        assertTrue(ens.isLabelAvailable("alice"));
    }

    function test_IsLabelAvailable_False_AfterRegistration() public {
        vm.prank(owner);
        ens.registerSubname(alice, "alice");
        assertFalse(ens.isLabelAvailable("alice"));
    }

    function test_IsLabelAvailable_IndependentLabels() public {
        vm.prank(owner);
        ens.registerSubname(alice, "alice");
        assertTrue(ens.isLabelAvailable("bob")); // different label stays available
    }

    // =========================================================================
    // registerSubname
    // =========================================================================

    function test_RegisterSubname_ByOwner() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit ENSManager.SubnameRegistered(alice, "alice");

        ens.registerSubname(alice, "alice");

        bytes32 labelHash   = keccak256(bytes("alice"));
        bytes32 subnodeHash = keccak256(abi.encodePacked(VAULT_NODE, labelHash));

        assertEq(reg.lastNode(),     VAULT_NODE);
        assertEq(reg.lastLabel(),    labelHash);
        assertEq(reg.lastOwner(),    address(ens));
        assertEq(reg.lastResolver(), address(res));
        assertEq(res.lastNode(),     subnodeHash);
        assertEq(res.lastAddr(),     alice);
    }

    function test_RegisterSubname_ByAuthorizedCaller() public {
        vm.prank(owner);
        ens.addAuthorizedCaller(dao);

        vm.prank(dao);
        ens.registerSubname(bob, "bob");

        assertEq(reg.lastOwner(), address(ens));
    }

    function test_RegisterSubname_ByFactory() public {
        vm.prank(owner);
        ens.addAuthorizedCaller(factory);

        vm.prank(factory);
        ens.registerSubname(makeAddr("vault"), "teamvault");

        assertEq(reg.lastOwner(), address(ens));
    }

    function test_RevertIf_RegisterSubname_Unauthorized() public {
        vm.prank(alice);
        vm.expectRevert(ENSManager.NotAuthorized.selector);
        ens.registerSubname(alice, "alice");
    }

    function test_RevertIf_RegisterSubname_LabelAlreadyTaken() public {
        vm.prank(owner);
        ens.registerSubname(alice, "alice");

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ENSManager.LabelAlreadyTaken.selector, "alice"));
        ens.registerSubname(bob, "alice"); // same label
    }

    // =========================================================================
    // bootstrapSubnames
    // =========================================================================

    function test_BootstrapSubnames() public {
        address[] memory addrs  = new address[](3);
        string[]  memory labels = new string[](3);
        addrs[0] = alice;   labels[0] = "alice";
        addrs[1] = bob;     labels[1] = "bob";
        addrs[2] = charlie; labels[2] = "charlie";

        vm.prank(owner);
        ens.bootstrapSubnames(addrs, labels);

        bytes32 charlieHash = keccak256(bytes("charlie"));
        assertEq(reg.lastOwner(), address(ens));
        assertEq(reg.lastLabel(), charlieHash);
    }

    function test_RevertIf_BootstrapSubnames_LengthMismatch() public {
        address[] memory addrs  = new address[](2);
        string[]  memory labels = new string[](3);
        addrs[0] = alice; addrs[1] = bob;
        labels[0] = "alice"; labels[1] = "bob"; labels[2] = "charlie";

        vm.prank(owner);
        vm.expectRevert(ENSManager.BootstrapLengthMismatch.selector);
        ens.bootstrapSubnames(addrs, labels);
    }

    function test_RevertIf_BootstrapSubnames_NotOwner() public {
        address[] memory addrs  = new address[](1);
        string[]  memory labels = new string[](1);
        addrs[0] = alice; labels[0] = "alice";

        vm.prank(alice);
        vm.expectRevert(ENSManager.NotOwner.selector);
        ens.bootstrapSubnames(addrs, labels);
    }
}

// =============================================================================
// Integration test: DAO → ENSManager
// =============================================================================

contract ENSManagerIntegrationTest is Test {
    MockUSDC           usdc;
    SplitVault         vault;
    MemberDAO          daoContract;
    ENSManager         ens;
    MockENSRegistry    reg;
    MockPublicResolver res;

    address alice   = makeAddr("alice");
    address bob     = makeAddr("bob");
    address charlie = makeAddr("charlie");
    address dave    = makeAddr("dave");

    bytes32 constant VAULT_NODE    = keccak256("myvault.eth");
    uint256 constant VOTING_DURATION = 1 days;

    uint256[] davePcts;

    function setUp() public {
        usdc = new MockUSDC();
        address[] memory addrs = new address[](3);
        uint256[] memory pcts  = new uint256[](3);
        addrs[0] = alice;   pcts[0] = 50;
        addrs[1] = bob;     pcts[1] = 30;
        addrs[2] = charlie; pcts[2] = 20;
        vault = new SplitVault(address(usdc), addrs, pcts);

        reg = new MockENSRegistry();
        res = new MockPublicResolver();
        ens = new ENSManager(address(reg), address(res), VAULT_NODE);

        daoContract = new MemberDAO(payable(address(vault)), VOTING_DURATION, address(ens));

        ens.addAuthorizedCaller(address(daoContract));
        vault.transferOwnership(address(daoContract));

        davePcts = new uint256[](4);
        davePcts[0] = 40; davePcts[1] = 25; davePcts[2] = 15; davePcts[3] = 20;
    }

    function test_FullFlow_AddMember_RegistersSubname() public {
        vm.prank(alice);
        uint256 id = daoContract.proposeMember(dave, davePcts, "dave");

        vm.prank(alice); daoContract.vote(id, true);
        vm.prank(bob);   daoContract.vote(id, true);

        vm.warp(block.timestamp + VOTING_DURATION + 1);

        vm.expectEmit(true, false, false, true);
        emit ENSManager.SubnameRegistered(dave, "dave");

        daoContract.executeProposal(id);

        (address[] memory members,) = vault.getMembers();
        assertEq(members.length, 4);
        assertEq(members[3], dave);

        bytes32 expectedLabel   = keccak256(bytes("dave"));
        bytes32 expectedSubnode = keccak256(abi.encodePacked(VAULT_NODE, expectedLabel));
        assertEq(reg.lastOwner(), address(ens));
        assertEq(reg.lastLabel(), expectedLabel);
        assertEq(res.lastNode(),  expectedSubnode);
        assertEq(res.lastAddr(),  dave);
    }

    function test_Repartition_DoesNotCallENS() public {
        uint256[] memory newPcts = new uint256[](3);
        newPcts[0] = 60; newPcts[1] = 25; newPcts[2] = 15;

        vm.prank(alice);
        uint256 id = daoContract.proposeRepartition(newPcts);

        vm.prank(alice); daoContract.vote(id, true);
        vm.prank(bob);   daoContract.vote(id, true);

        vm.warp(block.timestamp + VOTING_DURATION + 1);
        daoContract.executeProposal(id);

        assertEq(reg.lastOwner(), address(0));
    }

    function test_AddMember_NoENS_WhenManagerNotSet() public {
        address[] memory addrs2 = new address[](3);
        uint256[] memory pcts2  = new uint256[](3);
        addrs2[0] = alice; pcts2[0] = 50;
        addrs2[1] = bob;   pcts2[1] = 30;
        addrs2[2] = charlie; pcts2[2] = 20;
        SplitVault vault2 = new SplitVault(address(usdc), addrs2, pcts2);

        MemberDAO daoNoEns2 = new MemberDAO(payable(address(vault2)), VOTING_DURATION, address(0));
        vault2.transferOwnership(address(daoNoEns2));

        vm.prank(alice);
        uint256 id = daoNoEns2.proposeMember(dave, davePcts, "dave");

        vm.prank(alice); daoNoEns2.vote(id, true);
        vm.prank(bob);   daoNoEns2.vote(id, true);

        vm.warp(block.timestamp + VOTING_DURATION + 1);
        daoNoEns2.executeProposal(id);

        (address[] memory members,) = vault2.getMembers();
        assertEq(members.length, 4);
        assertEq(members[3], dave);
        assertEq(reg.lastOwner(), address(0));
    }
}
