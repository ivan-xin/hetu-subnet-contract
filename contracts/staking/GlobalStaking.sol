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
    
    // Authorized contract addresses (NeuronManager, etc.)
    mapping(address => bool) public authorizedCallers;
    
    // User staking mapping
    mapping(address => StakeInfo) private userStakes;
    mapping(address => uint256) public totalUserStake;
    
    // Subnet staking statistics
    mapping(uint16 => uint256) public subnetTotalStake;
    mapping(uint16 => mapping(address => uint256)) public subnetUserStake;
    
    // Locked stakes (for neuron registration)
    mapping(address => mapping(uint16 => uint256)) public lockedStake;
    
    // Subnet allocation information
    mapping(address => mapping(uint16 => SubnetAllocation)) private subnetAllocations;
    mapping(address => uint16[]) private userAllocatedSubnets;
    uint256 private totalStaked;

    // Minimum staking requirements
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
     * @dev Authorize caller (such as NeuronManager)
     */
    function setAuthorizedCaller(address caller, bool authorized) external onlyOwner {
        require(caller != address(0), "ZERO_ADDRESS");
        authorizedCallers[caller] = authorized;
        emit AuthorizedCallerUpdated(caller, authorized);
    }
    
    /**
     * @dev Add global stake - Users stake HETU to gain participation eligibility
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
     * @dev Remove global stake
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
     * @dev Allocate stake to subnet
     * @param netuid Subnet ID
     * @param amount Allocation amount
     */
    function allocateToSubnet(uint16 netuid, uint256 amount) external nonReentrant {
        require(amount >= MIN_SUBNET_ALLOCATION || amount == 0, "BELOW_MIN_ALLOCATION");
        
        StakeInfo storage stakeInfo = userStakes[msg.sender];
        SubnetAllocation storage allocation = subnetAllocations[msg.sender][netuid];
        
        uint256 oldAmount = allocation.allocated;
        
        if (amount > oldAmount) {
            // Increase allocation
            uint256 additional = amount - oldAmount;
            require(stakeInfo.availableForAllocation >= additional, "INSUFFICIENT_AVAILABLE_STAKE");
            stakeInfo.availableForAllocation -= additional;
            stakeInfo.totalAllocated += additional;
        } else if (amount < oldAmount) {
            // Decrease allocation - neuron threshold not checked here, checked externally by NeuronManager
            uint256 reduction = oldAmount - amount;
            stakeInfo.availableForAllocation += reduction;
            stakeInfo.totalAllocated -= reduction;
        }
        
        // Update allocation
        allocation.allocated = amount;
        allocation.lastUpdateBlock = block.number;
        allocation.isActive = amount > 0;
        
        // Update subnet statistics
        subnetTotalStake[netuid] = subnetTotalStake[netuid] - oldAmount + amount;
        subnetUserStake[netuid][msg.sender] = amount;
        
        // Update allocation list
        if (oldAmount == 0 && amount > 0) {
            userAllocatedSubnets[msg.sender].push(netuid);
        } else if (oldAmount > 0 && amount == 0) {
            _removeFromAllocatedSubnets(msg.sender, netuid);
        }
        
        emit SubnetAllocationChanged(msg.sender, netuid, oldAmount, amount);
    }
    
    /**
     * @dev Restricted allocation of stake to subnet (called by authorized contracts like NeuronManager)
     * @param user User address
     * @param netuid Subnet ID
     * @param amount Allocation amount
     * @param minThreshold Minimum threshold (provided by caller)
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
            // Increase allocation
            uint256 additional = amount - oldAmount;
            require(stakeInfo.availableForAllocation >= additional, "INSUFFICIENT_AVAILABLE_STAKE");
            stakeInfo.availableForAllocation -= additional;
            stakeInfo.totalAllocated += additional;
        } else if (amount < oldAmount) {
            // Decrease allocation
            uint256 reduction = oldAmount - amount;
            stakeInfo.availableForAllocation += reduction;
            stakeInfo.totalAllocated -= reduction;
        }
        
        // Update allocation
        allocation.allocated = amount;
        allocation.lastUpdateBlock = block.number;
        allocation.isActive = amount > 0;
        
        // Update subnet statistics
        subnetTotalStake[netuid] = subnetTotalStake[netuid] - oldAmount + amount;
        subnetUserStake[netuid][user] = amount;
        
        // Update allocation list
        if (oldAmount == 0 && amount > 0) {
            userAllocatedSubnets[user].push(netuid);
        } else if (oldAmount > 0 && amount == 0) {
            _removeFromAllocatedSubnets(user, netuid);
        }
        
        emit SubnetAllocationChanged(user, netuid, oldAmount, amount);
    }
    
    /**
     * @dev Claim rewards (empty implementation for now)
     */
    function claimRewards() external nonReentrant {
        StakeInfo storage stakeInfo = userStakes[msg.sender];
        uint256 rewards = stakeInfo.pendingRewards;
        require(rewards > 0, "NO_REWARDS");
        
        stakeInfo.pendingRewards = 0;
        // TODO: Implement reward distribution logic
    }
    
    /**
     * @dev Lock stake (called during neuron registration)
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
     * @dev Unlock stake (called during neuron deregistration)
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
     * @dev Check if user has sufficient stake to become a neuron
     */
    function canBecomeNeuron(address user, uint16 netuid, uint256 requiredAmount) 
        external 
        view 
        returns (bool) 
    {
        return subnetUserStake[netuid][user] >= requiredAmount;
    }
    
    /**
     * @dev Get user's effective stake in subnet
     */
    function getEffectiveStake(address user, uint16 netuid) external view returns (uint256) {
        return subnetUserStake[netuid][user];
    }
    
    /**
     * @dev Get user's available stake in subnet (unlocked)
     */
    function getAvailableStake(address user, uint16 netuid) external view returns (uint256) {
        uint256 total = subnetUserStake[netuid][user];
        uint256 locked = lockedStake[user][netuid];
        return total > locked ? total - locked : 0;
    }
    
    /**
     * @dev Get user's stake information
     */
    function getStakeInfo(address user) external view returns (StakeInfo memory) {
        return userStakes[user];
    }
    
    /**
     * @dev Get subnet allocation information
     */
    function getSubnetAllocation(address user, uint16 netuid) external view returns (SubnetAllocation memory) {
        return subnetAllocations[user][netuid];
    }
    
    /**
     * @dev Get total staked amount
     */
    function getTotalStaked() external view returns (uint256) {
        return totalStaked;
    }
    
    /**
     * @dev Get user's staking information
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
     * @dev Get user's locked stake in specific subnet
     */
    function getLockedStake(address user, uint16 netuid) external view returns (uint256) {
        return lockedStake[user][netuid];
    }
    
    /**
     * @dev Check if user has participation eligibility
     */
    function hasParticipationEligibility(address user) external view returns (bool) {
        return totalUserStake[user] >= MIN_STAKE_TO_PARTICIPATE;
    }
    
    // ============ Internal Functions ============
    
    /**
     * @dev Remove from allocated subnets list
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
