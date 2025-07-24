// contracts/interfaces/IGlobalStaking.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IGlobalStaking {
    struct StakeInfo {
        uint256 totalStaked;           // Total staked amount
        uint256 totalAllocated;        // Total allocated amount
        uint256 totalCost;             // Total cost amount
        uint256 lastUpdateBlock;       // Last update block
    }
    
    struct SubnetAllocation {
        uint256 allocated;             // Amount allocated to subnet
        uint256 cost;                  // Costed amount (locked during registration)
        uint256 lastUpdateBlock;       // Last update block
    }
    
    // Events
    event GlobalStakeAdded(address indexed user, uint256 amount); // 用户增加全局质押
    event GlobalStakeRemoved(address indexed user, uint256 amount); // 用户减少全局质押
    event SubnetAllocationChanged(
        address indexed user,
        uint16 indexed netuid,
        uint256 oldAmount,
        uint256 newAmount
    );  // 用户分配到子网的质押变更
    event DeallocatedFromSubnet(address indexed user, uint16 indexed netuid, uint256 amount); // 用户从子网撤回质押
    event RegistrationCost(address indexed user, uint16 indexed netuid, uint256 cost); // 用户在子网支付注册成本
    event AuthorizedCallerUpdated(address indexed caller, bool authorized); // 授权调用者更新事件

    // ============ Core Functions ============
    function addGlobalStake(uint256 amount) external;
    function removeGlobalStake(uint256 amount) external;
    function allocateToSubnet(uint16 netuid, uint256 amount) external;
    function deallocateFromSubnet(uint16 netuid, uint256 amount) external;
    
    // ============ Authorized Functions ============
    function allocateToSubnetWithMinThreshold(uint16 netuid, uint256 amount, uint256 minThreshold) external;
    function chargeRegistrationCost(address user, uint16 netuid, uint256 cost) external;
    
    // ============ View Functions ============
    function getAvailableStake(address user) external view returns (uint256);
    function getStakeInfo(address user) external view returns (StakeInfo memory);
    function getSubnetAllocation(address user, uint16 netuid) external view returns (SubnetAllocation memory);
    function canAllocateToSubnet(address user, uint256 amount) external view returns (bool);
    function canPayRegistrationCost(address user, uint256 cost) external view returns (bool);
    
    // ============ Admin Functions ============
    function setAuthorizedCaller(address caller, bool authorized) external;
}
