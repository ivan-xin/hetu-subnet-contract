// contracts/staking/GlobalStaking.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IGlobalStaking.sol";

/**
 * @title GlobalStaking
 * @dev Global Staking Contract - Manages HETU staking for participation eligibility
 * Responsibilities:
 * 1. Manages users' global HETU staking
 * 2. Manages stake allocation to various subnets
 * 3. Provides staking query interface for NeuronManager
 */
contract GlobalStaking is ReentrancyGuard, Ownable, IGlobalStaking {
    IERC20 public immutable hetuToken;
    address public treasury; // 协议金库地址
    
    // Authorized contract addresses (NeuronManager, etc.)
    mapping(address => bool) public authorizedCallers;
    
    // User staking mapping
    mapping(address => StakeInfo) private userStakes;
    
    // Subnet allocation information
    mapping(address => mapping(uint16 => SubnetAllocation)) private subnetAllocations;
    
    modifier onlyAuthorizedCaller() {
        require(authorizedCallers[msg.sender], "UNAUTHORIZED_CALLER");
        _;
    }
    
    constructor(address _hetuToken,address _treasury, address _initialOwner) Ownable(_initialOwner) {
        require(_hetuToken != address(0), "ZERO_HETU_TOKEN");
        require(_initialOwner != address(0), "ZERO_INITIAL_OWNER");
        require(_treasury != address(0), "ZERO_TREASURY");
        hetuToken = IERC20(_hetuToken);
        treasury = _treasury;
    }
    
    
    /**
     * @dev Add global stake - Users stake HETU to gain participation eligibility
     */
    function addGlobalStake(uint256 amount) external nonReentrant {
        require(amount > 0, "ZERO_AMOUNT");
        require(hetuToken.transferFrom(msg.sender, address(this), amount), "TRANSFER_FAILED");

        StakeInfo storage stakeInfo = userStakes[msg.sender];
        stakeInfo.totalStaked += amount;
        stakeInfo.lastUpdateBlock = block.number;
        
        emit GlobalStakeAdded(msg.sender, amount);
    }
    
    /**
     * @dev Remove global stake
     */
    function removeGlobalStake(uint256 amount) external nonReentrant {
        require(amount > 0, "ZERO_AMOUNT");
        
        StakeInfo storage stakeInfo = userStakes[msg.sender];
        require(stakeInfo.totalStaked >= amount, "INSUFFICIENT_STAKE");
        
        // 计算可用余额：总质押 - 已分配 - 已消耗成本
        uint256 available = stakeInfo.totalStaked - stakeInfo.totalAllocated - stakeInfo.totalCost;
        require(available >= amount, "AMOUNT_NOT_AVAILABLE");

        stakeInfo.totalStaked -= amount;
        stakeInfo.lastUpdateBlock = block.number;
        
        require(hetuToken.transfer(msg.sender, amount), "TRANSFER_FAILED");
        
        emit GlobalStakeRemoved(msg.sender, amount);
    }

    /**
     * @dev Allocate stake to subnet
     * @param netuid Subnet ID
     * @param amount Allocation amount
     */
    function allocateToSubnet(uint16 netuid, uint256 amount) external {
        require(amount > 0, "ZERO_AMOUNT");
        _allocateToSubnetInternal(msg.sender, netuid, amount);
    }
    
    /**
     * @dev Allocate stake to subnet with custom threshold (for neuron registration)
     * @param netuid Subnet ID
     * @param amount Allocation amount
     * @param minThreshold Minimum required threshold for this allocation
     */
    function allocateToSubnetWithMinThreshold(uint16 netuid, uint256 amount, uint256 minThreshold) 
        external 
        onlyAuthorizedCaller 
    {
        require(amount >= minThreshold, "BELOW_MIN_THRESHOLD");
        
        // 从 tx.origin 获取真实用户地址
        address user = tx.origin;
        _allocateToSubnetInternal(user, netuid, amount);
    }

    /**
     * @dev 用户从子网撤回分配
     */
    function deallocateFromSubnet(uint16 netuid, uint256 amount) external {
        require(amount > 0, "ZERO_AMOUNT");
        
        SubnetAllocation storage allocation = subnetAllocations[msg.sender][netuid];
        require(allocation.allocated >= amount, "INSUFFICIENT_ALLOCATION");

        StakeInfo storage stakeInfo = userStakes[msg.sender];
        
        // 更新子网分配
        uint256 oldAmount = allocation.allocated;
        allocation.allocated -= amount;
        allocation.lastUpdateBlock = block.number;
        
        // 更新全局分配
        stakeInfo.totalAllocated -= amount;
        stakeInfo.lastUpdateBlock = block.number;
        
        emit DeallocatedFromSubnet(msg.sender, netuid, amount);
        emit SubnetAllocationChanged(msg.sender, netuid, oldAmount, allocation.allocated);
    }

        // ============ Cost Functions ============

    /**
     * @dev 收取注册成本（由 NeuronManager 调用）
     */
    function chargeRegistrationCost(address user, uint16 netuid, uint256 cost) 
        external 
        onlyAuthorizedCaller 
    {
        require(cost > 0, "ZERO_COST");
        
        StakeInfo storage stakeInfo = userStakes[user];
        
        // 检查可用余额是否足够支付成本
        uint256 available = stakeInfo.totalStaked - stakeInfo.totalAllocated - stakeInfo.totalCost;
        require(available >= cost, "INSUFFICIENT_AVAILABLE_STAKE");

        // 更新用户总成本
        stakeInfo.totalCost += cost;
        stakeInfo.lastUpdateBlock = block.number;
        
        // 更新子网成本
        SubnetAllocation storage allocation = subnetAllocations[user][netuid];
        allocation.cost += cost;
        allocation.lastUpdateBlock = block.number;
        
        // 将成本转移到协议金库
        require(hetuToken.transfer(treasury, cost), "TRANSFER_FAILED");
        
        emit RegistrationCost(user, netuid, cost);
    }

        // ============ View Functions ============

    /**
     * @dev 获取用户可用余额
     */
    function getAvailableStake(address user) external view returns (uint256) {
        StakeInfo storage stakeInfo = userStakes[user];
        return stakeInfo.totalStaked - stakeInfo.totalAllocated - stakeInfo.totalCost;
    }

    /**
     * @dev 获取用户质押信息
     */
    function getStakeInfo(address user) external view returns (StakeInfo memory) {
        return userStakes[user];
    }

    /**
     * @dev 获取子网分配信息
     */
    function getSubnetAllocation(address user, uint16 netuid) external view returns (SubnetAllocation memory) {
        return subnetAllocations[user][netuid];
    }

    /**
     * @dev 检查用户是否可以分配指定数量到子网
     */
    function canAllocateToSubnet(address user, uint256 amount) external view returns (bool) {
        StakeInfo storage stakeInfo = userStakes[user];
        uint256 available = stakeInfo.totalStaked - stakeInfo.totalAllocated - stakeInfo.totalCost;
        return available >= amount;
    }

    /**
     * @dev 检查用户是否可以支付注册成本
     */
    function canPayRegistrationCost(address user, uint256 cost) external view returns (bool) {
        StakeInfo storage stakeInfo = userStakes[user];
        uint256 available = stakeInfo.totalStaked - stakeInfo.totalAllocated - stakeInfo.totalCost;
        return available >= cost;
    }

    // ============ Internal Functions ============

    function _allocateToSubnetInternal(address user, uint16 netuid, uint256 amount) internal {
        StakeInfo storage stakeInfo = userStakes[user];
        SubnetAllocation storage allocation = subnetAllocations[user][netuid];
        
        uint256 oldAmount = allocation.allocated;
        
        if (amount > oldAmount) {
            // 增加分配
            uint256 additional = amount - oldAmount;
            uint256 available = stakeInfo.totalStaked - stakeInfo.totalAllocated - stakeInfo.totalCost;
            require(available >= additional, "INSUFFICIENT_AVAILABLE_STAKE");
            
            stakeInfo.totalAllocated += additional;
        } else if (amount < oldAmount) {
            // 减少分配
            uint256 reduction = oldAmount - amount;
            stakeInfo.totalAllocated -= reduction;
        }
        
        // 更新分配信息
        allocation.allocated = amount;
        allocation.lastUpdateBlock = block.number;
        stakeInfo.lastUpdateBlock = block.number;
        
        emit SubnetAllocationChanged(user, netuid, oldAmount, amount);
    }
    
      // ============ Admin Functions ============

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "ZERO_ADDRESS");
        treasury = _treasury;
    }

    function setAuthorizedCaller(address caller, bool authorized) external onlyOwner {
        require(caller != address(0), "ZERO_ADDRESS");
        authorizedCallers[caller] = authorized;
        emit AuthorizedCallerUpdated(caller, authorized);
    }
}
