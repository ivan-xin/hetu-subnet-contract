// contracts/staking/GlobalStaking.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/ISubnetTypes.sol";

/**
 * @title GlobalStaking
 * @dev 全局质押合约 - 类似Subtensor的根网络质押
 */
contract GlobalStaking is ReentrancyGuard {
    IERC20 public immutable hetuToken;
    address public immutable factory;
    
    // 全局质押信息
    struct GlobalStakeInfo {
        uint256 totalStaked;           // 总质押量
        uint256 availableForAllocation; // 可分配量
        mapping(uint16 => uint256) subnetAllocations; // 子网分配
        uint16[] allocatedSubnets;     // 已分配的子网列表
        uint256 lastUpdateBlock;       // 最后更新区块
    }
    
    // 用户质押映射
    mapping(address => GlobalStakeInfo) public userStakes;
    mapping(address => uint256) public totalUserStake;
    
    // 子网质押统计
    mapping(uint16 => uint256) public subnetTotalStake;
    mapping(uint16 => mapping(address => uint256)) public subnetUserStake;
    
    // 最小质押要求
    uint256 public constant MIN_STAKE_TO_PARTICIPATE = 100 ether; // 100 HETU
    uint256 public constant MIN_SUBNET_ALLOCATION = 10 ether;     // 10 HETU
    
    event GlobalStakeAdded(address indexed user, uint256 amount);
    event GlobalStakeRemoved(address indexed user, uint256 amount);
    event SubnetAllocationChanged(
        address indexed user,
        uint16 indexed netuid,
        uint256 oldAmount,
        uint256 newAmount
    );
    
    constructor(address _hetuToken, address _factory) {
        hetuToken = IERC20(_hetuToken);
        factory = _factory;
    }
    
    /**
     * @dev 添加全局质押
     */
    function addGlobalStake(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be positive");
        
        hetuToken.transferFrom(msg.sender, address(this), amount);
        
        GlobalStakeInfo storage stakeInfo = userStakes[msg.sender];
        stakeInfo.totalStaked += amount;
        stakeInfo.availableForAllocation += amount;
        stakeInfo.lastUpdateBlock = block.number;
        
        totalUserStake[msg.sender] += amount;
        
        emit GlobalStakeAdded(msg.sender, amount);
    }
    
    /**
     * @dev 分配质押到子网
     */
    function allocateToSubnet(uint16 netuid, uint256 amount) external nonReentrant {
        require(amount >= MIN_SUBNET_ALLOCATION, "Below minimum allocation");
        
        GlobalStakeInfo storage stakeInfo = userStakes[msg.sender];
        require(stakeInfo.availableForAllocation >= amount, "Insufficient available stake");
        
        // 检查子网是否存在
        require(_subnetExists(netuid), "Subnet does not exist");
        
        uint256 oldAmount = stakeInfo.subnetAllocations[netuid];
        
        // 更新分配
        stakeInfo.subnetAllocations[netuid] = amount;
        stakeInfo.availableForAllocation = stakeInfo.availableForAllocation - amount + oldAmount;
        
        // 更新子网统计
        subnetTotalStake[netuid] = subnetTotalStake[netuid] - oldAmount + amount;
        subnetUserStake[netuid][msg.sender] = amount;
        
        // 更新分配列表
        if (oldAmount == 0 && amount > 0) {
            stakeInfo.allocatedSubnets.push(netuid);
        } else if (oldAmount > 0 && amount == 0) {
            _removeFromAllocatedSubnets(msg.sender, netuid);
        }
        
        // 通知子网合约更新
        _notifySubnetStakeChange(netuid, msg.sender, oldAmount, amount);
        
        emit SubnetAllocationChanged(msg.sender, netuid, oldAmount, amount);
    }
    
    /**
     * @dev 检查用户是否可以成为特定子网的神经元
     */
    function canBecomeNeuron(address user, uint16 netuid) external view returns (bool) {
        return subnetUserStake[netuid][user] >= MIN_STAKE_TO_PARTICIPATE;
    }
    
    /**
     * @dev 获取用户在子网的有效质押
     */
    function getEffectiveStake(address user, uint16 netuid) external view returns (uint256) {
        return subnetUserStake[netuid][user];
    }
}
