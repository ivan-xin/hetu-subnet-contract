// contracts/interfaces/IGlobalStaking.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IGlobalStaking {
    struct StakeInfo {
        uint256 totalStaked;           // Total staked amount
        uint256 totalAllocated;        // Total allocated amount
        uint256 availableForAllocation; // Available stake amount
        uint256 lastUpdateBlock;       // Last update block
        uint256 pendingRewards;        // Pending rewards
    }
    
    struct SubnetAllocation {
        uint256 allocated;             // Amount allocated to subnet
        uint256 locked;                // Locked amount (locked during registration)
        uint256 lastUpdateBlock;       // Last update block
        bool isActive;                 // Is active
    }
    
    // Events
    event GlobalStakeAdded(address indexed user, uint256 amount);
    event GlobalStakeRemoved(address indexed user, uint256 amount);
    event SubnetAllocationChanged(
        address indexed user,
        uint16 indexed netuid,
        uint256 oldAmount,
        uint256 newAmount
    );
    event StakeLocked(address indexed user, uint16 indexed netuid, uint256 amount);
    event StakeUnlocked(address indexed user, uint16 indexed netuid, uint256 amount);
    event AuthorizedCallerUpdated(address indexed caller, bool authorized);

    // ============ Core Functions ============
    function addGlobalStake(uint256 amount) external;
    function removeGlobalStake(uint256 amount) external;
    function allocateToSubnet(uint16 netuid, uint256 amount) external;
    function allocateToSubnetWithThreshold(address user, uint16 netuid, uint256 amount, uint256 minThreshold) external;
    function claimRewards() external;
    
    // ============ Authorized Caller Functions ============
    function lockSubnetStake(address user, uint16 netuid, uint256 amount) external;
    function unlockSubnetStake(address user, uint16 netuid, uint256 amount) external;
    function canBecomeNeuron(address user, uint16 netuid, uint256 requiredAmount) external view returns (bool);
    function getEffectiveStake(address user, uint16 netuid) external view returns (uint256);
    function getAvailableStake(address user, uint16 netuid) external view returns (uint256);
    function hasParticipationEligibility(address user) external view returns (bool);
    
    // ============ View Functions ============
    function getStakeInfo(address user) external view returns (StakeInfo memory);
    function getSubnetAllocation(address user, uint16 netuid) external view returns (SubnetAllocation memory);
    function getUserStakeInfo(address user) external view returns (
        uint256 totalStaked,
        uint256 availableForAllocation,
        uint16[] memory allocatedSubnets
    );
    function getTotalStaked() external view returns (uint256);
    function getLockedStake(address user, uint16 netuid) external view returns (uint256);

    // ============ State Variables ============
    function hetuToken() external view returns (IERC20); 
    function totalUserStake(address user) external view returns (uint256);
    function subnetTotalStake(uint16 netuid) external view returns (uint256);
    function subnetUserStake(uint16 netuid, address user) external view returns (uint256);
    function lockedStake(address user, uint16 netuid) external view returns (uint256);
    function authorizedCallers(address caller) external view returns (bool);
    
    // ============ Admin Functions ============
    function setAuthorizedCaller(address caller, bool authorized) external;
}
