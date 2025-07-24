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
    event GlobalStakeAdded(address indexed user, uint256 amount); // User adds global stake
    event GlobalStakeRemoved(address indexed user, uint256 amount); // User removes global stake
    event SubnetAllocationChanged(
        address indexed user,
        uint16 indexed netuid,
        uint256 oldAmount,
        uint256 newAmount
    );  // User stake allocation to subnet changed
    event DeallocatedFromSubnet(address indexed user, uint16 indexed netuid, uint256 amount); // User withdraws stake from subnet
    event RegistrationCost(address indexed user, uint16 indexed netuid, uint256 cost); // User pays registration cost in subnet
    event AuthorizedCallerUpdated(address indexed caller, bool authorized); // Authorized caller update event

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
