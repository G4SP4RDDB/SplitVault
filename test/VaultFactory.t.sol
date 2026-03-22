// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/VaultFactory.sol";
import "../src/VaultRegistry.sol";
import "../src/SplitVault.sol";
import "../src/MemberDAO.sol";
import "../src/ENSManager.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}
    function decimals() public pure override returns (uint8) { return 6; }
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

// Minimal ENS registry mock that tracks owners per subnode
contract MockENSRegistry {
    mapping(bytes32 => address) private _owners;
    bytes32 public lastLabel;

    function setSubnodeRecord(bytes32 node, bytes32 label, address owner_, address, uint64) external {
        _owners[keccak256(abi.encodePacked(node, label))] = owner_;
        lastLabel = label;
    }

    function owner(bytes32 node) external view returns (address) {
        return _owners[node];
    }
}

contract MockPublicResolver {
    function setAddr(bytes32, address) external {}
}

contract VaultFactoryTest is Test {
    MockUSDC      usdc;
    VaultRegistry registry;
    VaultFactory  factory;      // no ENS
    VaultFactory  factoryWithENS;
    ENSManager    ens;
    MockENSRegistry ensReg;
    MockPublicResolver ensRes;

    address alice   = makeAddr("alice");
    address bob     = makeAddr("bob");
    address charlie = makeAddr("charlie");
    address dave    = makeAddr("dave");
    address outsider = makeAddr("outsider");

    uint256 constant VOTING_DURATION = 1 days;
    uint256 constant USDC_UNIT = 1_000_000;
    bytes32 constant VAULT_NODE = keccak256("vaulthack.eth");

    address[] members;
    uint256[] percentages;

    function setUp() public {
        usdc     = new MockUSDC();
        registry = new VaultRegistry();

        // Factory without ENS (most tests)
        factory = new VaultFactory(address(usdc), address(registry), address(0));

        // ENS infrastructure for ENS-path tests
        ensReg = new MockENSRegistry();
        ensRes = new MockPublicResolver();
        ens    = new ENSManager(address(ensReg), address(ensRes), VAULT_NODE);

        // Factory with ENS wired
        factoryWithENS = new VaultFactory(address(usdc), address(registry), address(ens));
        ens.addAuthorizedCaller(address(factoryWithENS));

        members = new address[](3);
        percentages = new uint256[](3);
        members[0] = alice;   percentages[0] = 50;
        members[1] = bob;     percentages[1] = 30;
        members[2] = charlie; percentages[2] = 20;
    }

    // =========================================================================
    // Constructor
    // =========================================================================

    function test_Constructor_StoresState() public view {
        assertEq(factory.token(),             address(usdc));
        assertEq(address(factory.registry()),  address(registry));
        assertEq(address(factory.ensManager()), address(0));
    }

    function test_Constructor_StoresENSManager() public view {
        assertEq(address(factoryWithENS.ensManager()), address(ens));
    }

    function test_Constructor_RevertIf_ZeroToken() public {
        vm.expectRevert(VaultFactory.ZeroAddress.selector);
        new VaultFactory(address(0), address(registry), address(0));
    }

    function test_Constructor_RevertIf_ZeroRegistry() public {
        vm.expectRevert(VaultFactory.ZeroAddress.selector);
        new VaultFactory(address(usdc), address(0), address(0));
    }

    // =========================================================================
    // createVault — deployment
    // =========================================================================

    function test_CreateVault_DeploysContracts() public {
        (address vault, address dao) = factory.createVault(members, percentages, VOTING_DURATION, "");

        assertTrue(vault != address(0));
        assertTrue(dao   != address(0));
        assertTrue(vault != dao);
    }

    function test_CreateVault_EmitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit VaultFactory.VaultCreated(address(this), address(0), address(0), "");

        factory.createVault(members, percentages, VOTING_DURATION, "");
    }

    function test_CreateVault_VaultHasCorrectToken() public {
        (address vault,) = factory.createVault(members, percentages, VOTING_DURATION, "");
        assertEq(address(SplitVault(vault).token()), address(usdc));
    }

    function test_CreateVault_VaultHasCorrectMembers() public {
        (address vault,) = factory.createVault(members, percentages, VOTING_DURATION, "");

        (address[] memory addrs, uint256[] memory pcts) = SplitVault(vault).getMembers();
        assertEq(addrs.length, 3);
        assertEq(addrs[0], alice);   assertEq(pcts[0], 50);
        assertEq(addrs[1], bob);     assertEq(pcts[1], 30);
        assertEq(addrs[2], charlie); assertEq(pcts[2], 20);
    }

    // =========================================================================
    // createVault — ownership wiring
    // =========================================================================

    function test_CreateVault_VaultOwnedByDAO() public {
        (address vault, address dao) = factory.createVault(members, percentages, VOTING_DURATION, "");
        assertEq(SplitVault(vault).owner(), dao);
    }

    function test_CreateVault_DAOPointsToVault() public {
        (address vault, address dao) = factory.createVault(members, percentages, VOTING_DURATION, "");
        assertEq(address(MemberDAO(dao).vault()), vault);
    }

    function test_CreateVault_DAOVotingDuration() public {
        (,address dao) = factory.createVault(members, percentages, VOTING_DURATION, "");
        assertEq(MemberDAO(dao).votingDuration(), VOTING_DURATION);
    }

    function test_CreateVault_NoENS_DAOHasNoENSManager() public {
        (,address dao) = factory.createVault(members, percentages, VOTING_DURATION, "");
        assertEq(address(MemberDAO(dao).ensManager()), address(0));
    }

    // =========================================================================
    // createVault — registry
    // =========================================================================

    function test_CreateVault_RegistersInRegistry() public {
        (address vault,) = factory.createVault(members, percentages, VOTING_DURATION, "");
        assertTrue(registry.isRegistered(vault));
    }

    function test_CreateVault_IncrementsRegistryCount() public {
        assertEq(registry.vaultCount(), 0);
        factory.createVault(members, percentages, VOTING_DURATION, "");
        assertEq(registry.vaultCount(), 1);
        factory.createVault(members, percentages, VOTING_DURATION, "");
        assertEq(registry.vaultCount(), 2);
    }

    function test_CreateVault_MultipleVaultsAllRegistered() public {
        (address v1,) = factory.createVault(members, percentages, VOTING_DURATION, "");
        (address v2,) = factory.createVault(members, percentages, VOTING_DURATION, "");

        address[] memory all = registry.getAllVaults();
        assertEq(all.length, 2);
        assertEq(all[0], v1);
        assertEq(all[1], v2);
    }

    // =========================================================================
    // createVault — ENS path
    // =========================================================================

    function test_CreateVault_WithENS_RegistersVaultSubdomain() public {
        (address vault, address dao) = factoryWithENS.createVault(members, percentages, VOTING_DURATION, "teamvault");

        // ENS registry was called with the vault's label
        bytes32 expectedLabel = keccak256(bytes("teamvault"));
        assertEq(ensReg.lastLabel(), expectedLabel);

        // DAO has ENSManager wired so future member proposals also register subnames
        assertEq(address(MemberDAO(dao).ensManager()), address(ens));

        assertTrue(registry.isRegistered(vault));
    }

    function test_CreateVault_WithENS_LabelMarkedTaken() public {
        factoryWithENS.createVault(members, percentages, VOTING_DURATION, "teamvault");
        assertFalse(ens.isLabelAvailable("teamvault"));
    }

    function test_RevertIf_CreateVault_WithENS_EmptyLabel() public {
        vm.expectRevert(VaultFactory.EmptyLabel.selector);
        factoryWithENS.createVault(members, percentages, VOTING_DURATION, "");
    }

    function test_RevertIf_CreateVault_WithENS_DuplicateLabel() public {
        factoryWithENS.createVault(members, percentages, VOTING_DURATION, "teamvault");

        vm.expectRevert(abi.encodeWithSelector(ENSManager.LabelAlreadyTaken.selector, "teamvault"));
        factoryWithENS.createVault(members, percentages, VOTING_DURATION, "teamvault");
    }

    // =========================================================================
    // createVault — invalid inputs (forwarded to SplitVault)
    // =========================================================================

    function test_RevertIf_CreateVault_PercentagesDontSum100() public {
        percentages[0] = 50; percentages[1] = 30; percentages[2] = 30;

        vm.expectRevert(SplitVault.PercentagesMustSum100.selector);
        factory.createVault(members, percentages, VOTING_DURATION, "");
    }

    function test_RevertIf_CreateVault_EmptyMembers() public {
        address[] memory empty = new address[](0);
        uint256[] memory emptyPcts = new uint256[](0);

        vm.expectRevert(SplitVault.EmptyMembers.selector);
        factory.createVault(empty, emptyPcts, VOTING_DURATION, "");
    }

    function test_RevertIf_CreateVault_ArrayLengthMismatch() public {
        uint256[] memory badPcts = new uint256[](2);
        badPcts[0] = 50; badPcts[1] = 50;

        vm.expectRevert(SplitVault.ArrayLengthMismatch.selector);
        factory.createVault(members, badPcts, VOTING_DURATION, "");
    }

    // =========================================================================
    // setENSManager — still available for post-creation wiring
    // =========================================================================

    function test_SetENSManager_AfterCreation() public {
        (,address dao) = factory.createVault(members, percentages, VOTING_DURATION, "");
        address fakeEns = makeAddr("ens");

        vm.prank(alice);
        MemberDAO(dao).setENSManager(fakeEns);

        assertEq(address(MemberDAO(dao).ensManager()), fakeEns);
    }

    function test_SetENSManager_RevertIf_NotMember() public {
        (,address dao) = factory.createVault(members, percentages, VOTING_DURATION, "");

        vm.prank(outsider);
        vm.expectRevert(MemberDAO.NotAMember.selector);
        MemberDAO(dao).setENSManager(makeAddr("ens"));
    }

    // =========================================================================
    // Full end-to-end flow
    // =========================================================================

    function test_FullFlow_CreateDepositDistribute() public {
        (address vault, address dao) = factory.createVault(members, percentages, VOTING_DURATION, "");

        usdc.mint(address(this), 100 * USDC_UNIT);
        usdc.approve(vault, 100 * USDC_UNIT);
        SplitVault(vault).deposit(100 * USDC_UNIT);
        SplitVault(vault).distribute();

        assertEq(usdc.balanceOf(alice),   50 * USDC_UNIT);
        assertEq(usdc.balanceOf(bob),     30 * USDC_UNIT);
        assertEq(usdc.balanceOf(charlie), 20 * USDC_UNIT);
        assertEq(usdc.balanceOf(vault),   0);

        uint256[] memory davePcts = new uint256[](4);
        davePcts[0] = 40; davePcts[1] = 25; davePcts[2] = 15; davePcts[3] = 20;

        vm.prank(outsider);
        vm.expectRevert(SplitVault.NotOwner.selector);
        SplitVault(vault).addMember(dave, davePcts);

        vm.prank(alice);
        uint256 id = MemberDAO(dao).proposeMember(dave, davePcts, "dave");

        vm.prank(alice); MemberDAO(dao).vote(id, true);
        vm.prank(bob);   MemberDAO(dao).vote(id, true);

        vm.warp(block.timestamp + VOTING_DURATION + 1);
        MemberDAO(dao).executeProposal(id);

        (address[] memory addrs,) = SplitVault(vault).getMembers();
        assertEq(addrs.length, 4);
        assertEq(addrs[3], dave);
    }

    function test_FullFlow_WithENS_VaultAndMemberBothRegistered() public {
        // Authorize DAO as well so member additions register subnames
        (address vault, address dao) = factoryWithENS.createVault(members, percentages, VOTING_DURATION, "teamvault");
        ens.addAuthorizedCaller(dao);

        // teamvault label is taken
        assertFalse(ens.isLabelAvailable("teamvault"));

        // Add dave via governance — his subname should also be registered
        uint256[] memory davePcts = new uint256[](4);
        davePcts[0] = 40; davePcts[1] = 25; davePcts[2] = 15; davePcts[3] = 20;

        vm.prank(alice);
        uint256 id = MemberDAO(dao).proposeMember(dave, davePcts, "dave");
        vm.prank(alice); MemberDAO(dao).vote(id, true);
        vm.prank(bob);   MemberDAO(dao).vote(id, true);
        vm.warp(block.timestamp + VOTING_DURATION + 1);

        vm.expectEmit(true, false, false, true);
        emit ENSManager.SubnameRegistered(dave, "dave");
        MemberDAO(dao).executeProposal(id);

        assertFalse(ens.isLabelAvailable("dave"));

        (address[] memory addrs,) = SplitVault(vault).getMembers();
        assertEq(addrs.length, 4);
        assertEq(addrs[3], dave);
    }
}
