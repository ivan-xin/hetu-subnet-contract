// contracts/staking/GlobalStaking.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IGlobalStaking.sol";

/**
 * @title GlobalStaking
 * @dev 全局质押合约 - 管理HETU质押以获得参与资格
 * 职责：
 * 1. 管理用户的全局HETU质押
 * 2. 管理质押到各子网的分配
 * 3. 提供质押查询接口给NeuronManager
 */
contract GlobalStaking is ReentrancyGuard, Ownable, IGlobalStaking {
    IERC20 public immutable hetuToken;
    
    // 授权的合约地址（NeuronManager等）
    mapping(address => bool) public authorizedCallers;
    
    // 用户质押映射
    mapping(address => StakeInfo) private userStakes;
    mapping(address => uint256) public totalUserStake;
    
    // 子网质押统计
    mapping(uint16 => uint256) public subnetTotalStake;
    mapping(uint16 => mapping(address => uint256)) public subnetUserStake;
    
    // 锁定的质押（用于神经元注册）
    mapping(address => mapping(uint16 => uint256)) public lockedStake;
    
    // 子网分配信息
    mapping(address => mapping(uint16 => SubnetAllocation)) private subnetAllocations;
    mapping(address => uint16[]) private userAllocatedSubnets;
    uint256 private totalStaked;

    // 最小质押要求
    uint256 public constant MIN_STAKE_TO_PARTICIPATE = 100 ether; // 100 HETU
    uint256 public constant MIN_SUBNET_ALLOCATION = 10 ether;     // 10 HETU
    
    modifier onlyAuthorizedCaller() {
        require(authorizedCallers[msg.sender], "UNAUTHORIZED_CALLER");
        _;
    }
    
    constructor(address _hetuToken, address _initialOwner) Ownable(_initialOwner) {
        require(_hetuToken != address(0), "ZERO_HETU_TOKEN");
        require(_initialOwner != address(0), "ZERO_INITIAL_OWNER");
        hetuToken = IERC20(_hetuToken);
    }
    
    /**
     * @dev 授权调用者（如NeuronManager）
     */
    function setAuthorizedCaller(address caller, bool authorized) external onlyOwner {
        require(caller != address(0), "ZERO_ADDRESS");
        authorizedCallers[caller] = authorized;
        emit AuthorizedCallerUpdated(caller, authorized);
    }
    
    /**
     * @dev 添加全局质押 - 用户质押HETU获得参与资格
     */
    function addGlobalStake(uint256 amount) external nonReentrant {
        require(amount > 0, "AMOUNT_ZERO");
        
        hetuToken.transferFrom(msg.sender, address(this), amount);
        
        StakeInfo storage stakeInfo = userStakes[msg.sender];
        stakeInfo.totalStaked += amount;
        stakeInfo.availableForAllocation += amount;
        stakeInfo.lastUpdateBlock = block.number;
        
        totalUserStake[msg.sender] += amount;
        totalStaked += amount;
        
        emit GlobalStakeAdded(msg.sender, amount);
    }
    
    /**
     * @dev 移除全局质押
     */
    function removeGlobalStake(uint256 amount) external nonReentrant {
        require(amount > 0, "AMOUNT_ZERO");
        
        StakeInfo storage stakeInfo = userStakes[msg.sender];
        require(stakeInfo.availableForAllocation >= amount, "INSUFFICIENT_AVAILABLE_STAKE");
        
        stakeInfo.totalStaked -= amount;
        stakeInfo.availableForAllocation -= amount;
        stakeInfo.lastUpdateBlock = block.number;
        
        totalUserStake[msg.sender] -= amount;
        totalStaked -= amount;
        
        hetuToken.transfer(msg.sender, amount);
        
        emit GlobalStakeRemoved(msg.sender, amount);
    }

    /**
     * @dev 分配质押到子网
     * @param netuid 子网ID
     * @param amount 分配数量
     */
    function allocateToSubnet(uint16 netuid, uint256 amount) external nonReentrant {
        require(amount >= MIN_SUBNET_ALLOCATION || amount == 0, "BELOW_MIN_ALLOCATION");
        
        StakeInfo storage stakeInfo = userStakes[msg.sender];
        SubnetAllocation storage allocation = subnetAllocations[msg.sender][netuid];
        
        uint256 oldAmount = allocation.allocated;
        
        if (amount > oldAmount) {
            // 增加分配
            uint256 additional = amount - oldAmount;
            require(stakeInfo.availableForAllocation >= additional, "INSUFFICIENT_AVAILABLE_STAKE");
            stakeInfo.availableForAllocation -= additional;
            stakeInfo.totalAllocated += additional;
        } else if (amount < oldAmount) {
            // 减少分配 - 这里不检查神经元门槛，由NeuronManager在外部检查
            uint256 reduction = oldAmount - amount;
            stakeInfo.availableForAllocation += reduction;
            stakeInfo.totalAllocated -= reduction;
        }
        
        // 更新分配
        allocation.allocated = amount;
        allocation.lastUpdateBlock = block.number;
        allocation.isActive = amount > 0;
        
        // 更新子网统计
        subnetTotalStake[netuid] = subnetTotalStake[netuid] - oldAmount + amount;
        subnetUserStake[netuid][msg.sender] = amount;
        
        // 更新分配列表
        if (oldAmount == 0 && amount > 0) {
            userAllocatedSubnets[msg.sender].push(netuid);
        } else if (oldAmount > 0 && amount == 0) {
            _removeFromAllocatedSubnets(msg.sender, netuid);
        }
        
        emit SubnetAllocationChanged(msg.sender, netuid, oldAmount, amount);
    }
    
    /**
     * @dev 受限制的分配质押到子网（由授权合约调用，如NeuronManager）
     * @param user 用户地址
     * @param netuid 子网ID
     * @param amount 分配数量
     * @param minThreshold 最小门槛（由调用者提供）
     */
    function allocateToSubnetWithThreshold(
        address user, 
        uint16 netuid, 
        uint256 amount, 
        uint256 minThreshold
    ) external onlyAuthorizedCaller {
        require(amount >= minThreshold || amount == 0, "BELOW_THRESHOLD");
        
        StakeInfo storage stakeInfo = userStakes[user];
        SubnetAllocation storage allocation = subnetAllocations[user][netuid];
        
        uint256 oldAmount = allocation.allocated;
        
        if (amount > oldAmount) {
            // 增加分配
            uint256 additional = amount - oldAmount;
            require(stakeInfo.availableForAllocation >= additional, "INSUFFICIENT_AVAILABLE_STAKE");
            stakeInfo.availableForAllocation -= additional;
            stakeInfo.totalAllocated += additional;
        } else if (amount < oldAmount) {
            // 减少分配
            uint256 reduction = oldAmount - amount;
            stakeInfo.availableForAllocation += reduction;
            stakeInfo.totalAllocated -= reduction;
        }
        
        // 更新分配
        allocation.allocated = amount;
        allocation.lastUpdateBlock = block.number;
        allocation.isActive = amount > 0;
        
        // 更新子网统计
        subnetTotalStake[netuid] = subnetTotalStake[netuid] - oldAmount + amount;
        subnetUserStake[netuid][user] = amount;
        
        // 更新分配列表
        if (oldAmount == 0 && amount > 0) {
            userAllocatedSubnets[user].push(netuid);
        } else if (oldAmount > 0 && amount == 0) {
            _removeFromAllocatedSubnets(user, netuid);
        }
        
        emit SubnetAllocationChanged(user, netuid, oldAmount, amount);
    }
    
    /**
     * @dev 领取奖励 (暂时为空实现)
     */
    function claimRewards() external nonReentrant {
        StakeInfo storage stakeInfo = userStakes[msg.sender];
        uint256 rewards = stakeInfo.pendingRewards;
        require(rewards > 0, "NO_REWARDS");
        
        stakeInfo.pendingRewards = 0;
        // TODO: 实现奖励分发逻辑
    }
    
    /**
     * @dev 锁定质押（神经元注册时调用）
     */
    function lockSubnetStake(address user, uint16 netuid, uint256 amount) 
        external 
        onlyAuthorizedCaller 
    {
        require(subnetUserStake[netuid][user] >= amount, "INSUFFICIENT_SUBNET_STAKE");
        
        lockedStake[user][netuid] += amount;
        subnetAllocations[user][netuid].locked += amount;
        
        emit StakeLocked(user, netuid, amount);
    }
    
    /**
     * @dev 解锁质押（神经元注销时调用）
     */
    function unlockSubnetStake(address user, uint16 netuid, uint256 amount) 
        external 
        onlyAuthorizedCaller 
    {
        require(lockedStake[user][netuid] >= amount, "INSUFFICIENT_LOCKED_STAKE");
        
        lockedStake[user][netuid] -= amount;
        subnetAllocations[user][netuid].locked -= amount;
        
        emit StakeUnlocked(user, netuid, amount);
    }
    
    /**
     * @dev 检查用户是否有足够质押成为神经元
     */
    function canBecomeNeuron(address user, uint16 netuid, uint256 requiredAmount) 
        external 
        view 
        returns (bool) 
    {
        return subnetUserStake[netuid][user] >= requiredAmount;
    }
    
    /**
     * @dev 获取用户在子网的有效质押
     */
    function getEffectiveStake(address user, uint16 netuid) external view returns (uint256) {
        return subnetUserStake[netuid][user];
    }
    
    /**
     * @dev 获取用户在子网的可用质押（未锁定的）
     */
    function getAvailableStake(address user, uint16 netuid) external view returns (uint256) {
        uint256 total = subnetUserStake[netuid][user];
        uint256 locked = lockedStake[user][netuid];
        return total > locked ? total - locked : 0;
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
     * @dev 获取总质押量
     */
    function getTotalStaked() external view returns (uint256) {
        return totalStaked;
    }
    
    /**
     * @dev 获取用户的质押信息
     */
    function getUserStakeInfo(address user) external view returns (
        uint256 totalStaked_,
        uint256 availableForAllocation,
        uint16[] memory allocatedSubnets
    ) {
        StakeInfo storage stakeInfo = userStakes[user];
        return (
            stakeInfo.totalStaked,
            stakeInfo.availableForAllocation,
            userAllocatedSubnets[user]
        );
    }
    
    /**
     * @dev 获取用户在特定子网的锁定质押
     */
    function getLockedStake(address user, uint16 netuid) external view returns (uint256) {
        return lockedStake[user][netuid];
    }
    
    /**
     * @dev 检查用户是否有参与资格
     */
    function hasParticipationEligibility(address user) external view returns (bool) {
        return totalUserStake[user] >= MIN_STAKE_TO_PARTICIPATE;
    }
    
    // ============ 内部函数 ============
    
    /**
     * @dev 从已分配子网列表中移除
     */
    function _removeFromAllocatedSubnets(address user, uint16 netuid) internal {
        uint16[] storage subnets = userAllocatedSubnets[user];
        for (uint i = 0; i < subnets.length; i++) {
            if (subnets[i] == netuid) {
                subnets[i] = subnets[subnets.length - 1];
                subnets.pop();
                break;
            }
        }
    }
}
