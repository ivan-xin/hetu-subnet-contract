// contracts/interfaces/IGlobalStaking.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IGlobalStaking {
    struct StakeInfo {
        uint256 totalStaked;           // 总质押量
        uint256 totalAllocated;        // 总分配量
        uint256 availableStake;        // 可用质押量
        uint256 lockedStake;           // 锁定质押量
        uint256 lastStakeTime;         // 最后质押时间
        uint256 pendingRewards;        // 待领取奖励
    }
    
    struct SubnetAllocation {
        uint256 allocated;             // 分配到子网的量
        uint256 locked;                // 锁定量（注册时锁定）
        uint256 lastUpdateBlock;       // 最后更新区块
        bool isActive;                 // 是否活跃
    }
    
    function stakeHETU(uint256 amount) external;
    function unstakeHETU(uint256 amount) external;
    function allocateToSubnet(uint16 netuid, uint256 amount) external;
    function deallocateFromSubnet(uint16 netuid, uint256 amount) external;
    function claimRewards() external;
    
    function getStakeInfo(address user) external view returns (StakeInfo memory);
    function getSubnetAllocation(address user, uint16 netuid) external view returns (SubnetAllocation memory);
    function getTotalStaked() external view returns (uint256);
}
