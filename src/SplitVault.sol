// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title SplitVault
/// @notice Receives ETH and distributes it to members based on fixed percentage shares.
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

    /// @dev Simple reentrancy lock: 1 = unlocked, 2 = locked
    uint256 private _status;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event Deposited(address indexed sender, uint256 amount);
    event Distributed(uint256 totalAmount);
    event MemberAdded(address indexed addr, uint256 percentage);

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

    /// @param _addrs     Ordered list of member addresses.
    /// @param _percentages Corresponding shares (must sum to exactly 100).
    constructor(address[] memory _addrs, uint256[] memory _percentages) {
        if (_addrs.length == 0) revert EmptyMembers();
        if (_addrs.length != _percentages.length) revert ArrayLengthMismatch();

        uint256 total;

        for (uint256 i = 0; i < _addrs.length; i++) {
            if (_addrs[i] == address(0)) revert ZeroAddress();
            if (_percentages[i] == 0) revert ZeroPercentage();

            // O(n²) duplicate check — acceptable for small member sets
            for (uint256 j = 0; j < i; j++) {
                if (members[j].addr == _addrs[i]) revert DuplicateAddress(_addrs[i]);
            }

            members.push(Member(_addrs[i], _percentages[i]));
            total += _percentages[i];
        }

        if (total != 100) revert PercentagesMustSum100();

        owner = msg.sender;
        _status = 1; // unlock
    }

    // -------------------------------------------------------------------------
    // Deposit
    // -------------------------------------------------------------------------

    receive() external payable {
        emit Deposited(msg.sender, msg.value);
    }

    function deposit() external payable {
        emit Deposited(msg.sender, msg.value);
    }

    // -------------------------------------------------------------------------
    // Distribution
    // -------------------------------------------------------------------------

    /// @notice Distributes the entire contract balance to members pro-rata.
    /// @dev Follows checks-effects-interactions. Protected against reentrancy.
    ///      Any wei dust from integer division stays in the contract.
    function distribute() external nonReentrant {
        uint256 balance = address(this).balance;
        if (balance == 0) revert NoFundsToDistribute();

        // Snapshot length to avoid repeated SLOADs
        uint256 len = members.length;

        for (uint256 i = 0; i < len; i++) {
            uint256 amount = (balance * members[i].percentage) / 100;

            // Low-level call as required — revert on failure
            (bool ok,) = members[i].addr.call{value: amount}("");
            if (!ok) revert TransferFailed(members[i].addr);
        }

        emit Distributed(balance);
    }

    // -------------------------------------------------------------------------
    // Member management
    // -------------------------------------------------------------------------

    /// @notice Adds a new member and redistributes all percentage shares.
    /// @param newAddr       Address of the new member.
    /// @param newPercentages Full percentages array for ALL members after the addition.
    ///                      Length must equal current member count + 1.
    ///                      Existing members are listed first (in their original order),
    ///                      the new member's share is the last element.
    ///                      All values must be non-zero and sum to exactly 100.
    function addMember(address newAddr, uint256[] calldata newPercentages) external onlyOwner {
        if (newAddr == address(0)) revert ZeroAddress();

        uint256 currentLen = members.length;

        // Must provide one percentage per existing member plus one for the new member
        if (newPercentages.length != currentLen + 1) revert ArrayLengthMismatch();

        // Duplicate check against existing members
        for (uint256 i = 0; i < currentLen; i++) {
            if (members[i].addr == newAddr) revert DuplicateAddress(newAddr);
        }

        // Validate all new percentages and compute total
        uint256 total;
        for (uint256 i = 0; i < newPercentages.length; i++) {
            if (newPercentages[i] == 0) revert ZeroPercentage();
            total += newPercentages[i];
        }
        if (total != 100) revert PercentagesMustSum100();

        // Update existing members' shares
        for (uint256 i = 0; i < currentLen; i++) {
            members[i].percentage = newPercentages[i];
        }

        // Append the new member (last element is their share)
        members.push(Member(newAddr, newPercentages[currentLen]));

        emit MemberAdded(newAddr, newPercentages[currentLen]);
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
        addrs = new address[](len);
        percentages = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            addrs[i] = members[i].addr;
            percentages[i] = members[i].percentage;
        }
    }
}
