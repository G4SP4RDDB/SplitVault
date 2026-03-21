// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title SplitVault
/// @notice Receives USDC (or any ERC-20) and distributes it to members
///         based on fixed percentage shares.
///         Member management (add / repartition) is delegated to MemberDAO.
///         ENS subdomain registration is handled by the separate ENSManager contract.
contract SplitVault {
    // -------------------------------------------------------------------------
    // Types
    // -------------------------------------------------------------------------

    struct Member {
        address addr;
        uint256 percentage; // out of 100
    }

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    Member[] public members;

    address public owner;

    /// @dev The ERC-20 token this vault accepts and distributes (e.g. USDC).
    IERC20 public immutable token;

    /// @dev Simple reentrancy lock: 1 = unlocked, 2 = locked
    uint256 private _status;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event Deposited(address indexed sender, uint256 amount);
    event Distributed(uint256 totalAmount);
    event MemberAdded(address indexed addr, uint256 percentage);
    event SharesUpdated();

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error EmptyMembers();
    error ArrayLengthMismatch();
    error ZeroAddress();
    error ZeroPercentage();
    error DuplicateAddress(address addr);
    error PercentagesMustSum100();
    error NoFundsToDistribute();
    error TransferFailed(address recipient);
    error Reentrant();
    error NotOwner();

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier nonReentrant() {
        if (_status == 2) revert Reentrant();
        _status = 2;
        _;
        _status = 1;
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @param _token       ERC-20 token address (e.g. USDC on Sepolia:
    ///                     0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238).
    /// @param _addrs       Ordered list of member addresses.
    /// @param _percentages Corresponding shares (must sum to exactly 100).
    constructor(
        address _token,
        address[] memory _addrs,
        uint256[] memory _percentages
    ) {
        if (_token == address(0))             revert ZeroAddress();
        if (_addrs.length == 0)               revert EmptyMembers();
        if (_addrs.length != _percentages.length) revert ArrayLengthMismatch();

        uint256 total;

        for (uint256 i = 0; i < _addrs.length; i++) {
            if (_addrs[i] == address(0)) revert ZeroAddress();
            if (_percentages[i] == 0)   revert ZeroPercentage();

            // O(n²) duplicate check — acceptable for small member sets
            for (uint256 j = 0; j < i; j++) {
                if (members[j].addr == _addrs[i]) revert DuplicateAddress(_addrs[i]);
            }

            members.push(Member(_addrs[i], _percentages[i]));
            total += _percentages[i];
        }

        if (total != 100) revert PercentagesMustSum100();

        token  = IERC20(_token);
        owner  = msg.sender;
        _status = 1; // unlock
    }

    // -------------------------------------------------------------------------
    // Deposit
    // -------------------------------------------------------------------------

    /// @notice Deposit `amount` of the vault token into this contract.
    ///         The caller must have approved this contract for at least `amount`
    ///         via `token.approve(vaultAddress, amount)` beforehand.
    function deposit(uint256 amount) external {
        token.transferFrom(msg.sender, address(this), amount);
        emit Deposited(msg.sender, amount);
    }

    // -------------------------------------------------------------------------
    // Distribution
    // -------------------------------------------------------------------------

    /// @notice Distributes the entire token balance to members pro-rata.
    /// @dev Follows checks-effects-interactions. Protected against reentrancy.
    ///      Any token dust from integer division stays in the contract.
    function distribute() external nonReentrant {
        uint256 balance = token.balanceOf(address(this));
        if (balance == 0) revert NoFundsToDistribute();

        uint256 len = members.length;

        for (uint256 i = 0; i < len; i++) {
            uint256 amount = (balance * members[i].percentage) / 100;
            bool ok = token.transfer(members[i].addr, amount);
            if (!ok) revert TransferFailed(members[i].addr);
        }

        emit Distributed(balance);
    }

    // -------------------------------------------------------------------------
    // Member management
    // -------------------------------------------------------------------------

    /// @notice Adds a new member and redistributes all percentage shares.
    /// @param newAddr        Address of the new member.
    /// @param newPercentages Full percentages array for ALL members after the addition.
    ///                       Length must equal current member count + 1.
    ///                       Existing members are listed first (same order), new member last.
    ///                       All values must be non-zero and sum to exactly 100.
    function addMember(address newAddr, uint256[] calldata newPercentages) external onlyOwner {
        if (newAddr == address(0)) revert ZeroAddress();

        uint256 currentLen = members.length;

        if (newPercentages.length != currentLen + 1) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < currentLen; i++) {
            if (members[i].addr == newAddr) revert DuplicateAddress(newAddr);
        }

        uint256 total;
        for (uint256 i = 0; i < newPercentages.length; i++) {
            if (newPercentages[i] == 0) revert ZeroPercentage();
            total += newPercentages[i];
        }
        if (total != 100) revert PercentagesMustSum100();

        for (uint256 i = 0; i < currentLen; i++) {
            members[i].percentage = newPercentages[i];
        }

        members.push(Member(newAddr, newPercentages[currentLen]));

        emit MemberAdded(newAddr, newPercentages[currentLen]);
    }

    // -------------------------------------------------------------------------
    // Share update
    // -------------------------------------------------------------------------

    /// @notice Updates percentage shares for all existing members without adding anyone.
    /// @param newPercentages Must have the same length as current members and sum to 100.
    function updateShares(uint256[] calldata newPercentages) external onlyOwner {
        uint256 len = members.length;
        if (newPercentages.length != len) revert ArrayLengthMismatch();

        uint256 total;
        for (uint256 i = 0; i < len; i++) {
            if (newPercentages[i] == 0) revert ZeroPercentage();
            total += newPercentages[i];
        }
        if (total != 100) revert PercentagesMustSum100();

        for (uint256 i = 0; i < len; i++) {
            members[i].percentage = newPercentages[i];
        }

        emit SharesUpdated();
    }

    // -------------------------------------------------------------------------
    // Ownership
    // -------------------------------------------------------------------------

    /// @notice Transfers vault ownership to a new address (e.g. MemberDAO).
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }

    // -------------------------------------------------------------------------
    // View helpers
    // -------------------------------------------------------------------------

    /// @notice Returns all members and their percentages in two parallel arrays.
    function getMembers()
        external
        view
        returns (address[] memory addrs, uint256[] memory percentages)
    {
        uint256 len = members.length;
        addrs       = new address[](len);
        percentages = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            addrs[i]       = members[i].addr;
            percentages[i] = members[i].percentage;
        }
    }
}
