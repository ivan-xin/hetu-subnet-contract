// contracts/interfaces/IGlobalStaking.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IGlobalStaking {
    struct StakeInfo {
        uint256 totalStaked;           // 总质押量
        uint256 totalAllocated;        // 总分配量
        uint256 availableForAllocation;        // 可用质押量
        uint256 lockedStake;           // 锁定质押量
        uint256 lastUpdateBlock;         // 最后质押时间
        uint256 pendingRewards;        // 待领取奖励
    }
    
    struct SubnetAllocation {
        uint256 allocated;             // 分配到子网的量
        uint256 locked;                // 锁定量（注册时锁定）
        uint256 lastUpdateBlock;       // 最后更新区块
        bool isActive;                 // 是否活跃
    }
    
    // ============ Core Functions ============
    function addGlobalStake(uint256 amount) external;
    function removeGlobalStake(uint256 amount) external;
    function allocateToSubnet(uint16 netuid, uint256 amount) external;
    function deallocateFromSubnet(uint16 netuid, uint256 amount) external;
    function claimRewards() external;
    
    // ============ Subnet Manager Functions ============
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
    function hetuToken() external view returns (address);
    function totalUserStake(address user) external view returns (uint256);
    function subnetTotalStake(uint16 netuid) external view returns (uint256);
    function subnetUserStake(uint16 netuid, address user) external view returns (uint256);
    function lockedStake(address user, uint16 netuid) external view returns (uint256);
    function authorizedSubnetManagers(address manager) external view returns (bool);
    
    // ============ Admin Functions ============
    function setSubnetManagerAuthorization(address manager, bool authorized) external;
}
