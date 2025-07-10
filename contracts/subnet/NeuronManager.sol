// contracts/subnet/NeuronManager.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/ISubnetTypes.sol";
import "../interfaces/IGlobalStaking.sol";
import "../interfaces/ISubnetManager.sol";
import "../interfaces/IAlphaToken.sol";
import "../interfaces/INeuronManager.sol";

contract NeuronManager is ReentrancyGuard, Ownable, INeuronManager {
    using SubnetTypes for *;
    
    ISubnetManager public immutable subnetManager;
    IGlobalStaking public immutable globalStaking;
    address public rewardDistributor; // native code 调用地址
    
    // 核心存储
    mapping(uint16 => mapping(address => SubnetTypes.NeuronInfo)) public neurons;
    mapping(uint16 => address[]) public neuronList;
    
    modifier onlyRewardDistributor() {
        require(msg.sender == rewardDistributor, "ONLY_REWARD_DISTRIBUTOR");
        _;
    }
    
    constructor(
        address _subnetManager, 
        address _globalStaking, 
        address _initialOwner
    ) Ownable(_initialOwner) {
        require(_subnetManager != address(0), "ZERO_SUBNET_MANAGER");
        require(_globalStaking != address(0), "ZERO_GLOBAL_STAKING");
        require(_initialOwner != address(0), "ZERO_INITIAL_OWNER");
        
        subnetManager = ISubnetManager(_subnetManager);
        globalStaking = IGlobalStaking(_globalStaking);
    }
    
    /**
     * @dev 设置奖励分发地址（native code 地址）
     */
    function setRewardDistributor(address _rewardDistributor) external onlyOwner {
        require(_rewardDistributor != address(0), "ZERO_ADDRESS");
        rewardDistributor = _rewardDistributor;
    }
    
    /**
     * @dev 获取子网验证者数量
     */
    function getSubnetValidatorCount(uint16 netuid) public view returns (uint256) {
        uint256 count = 0;
        address[] memory neurons_list = neuronList[netuid];
        for (uint i = 0; i < neurons_list.length; i++) {
            if (neurons[netuid][neurons_list[i]].isValidator) {
                count++;
            }
        }
        return count;
    }
    
    /**
     * @dev 注册神经元
     */
    function registerNeuron(
        uint16 netuid,
        bool isValidatorRole,
        string calldata axonEndpoint,
        uint32 axonPort,
        string calldata prometheusEndpoint,
        uint32 prometheusPort
    ) external nonReentrant {
        // 1. 基础检查
        require(subnetManager.subnetExists(netuid), "SUBNET_NOT_EXISTS");
        require(!neurons[netuid][msg.sender].isActive, "ALREADY_REGISTERED");
        
        // 2. 检查用户是否有参与资格（质押了足够的HETU）
        require(globalStaking.hasParticipationEligibility(msg.sender), "NO_PARTICIPATION_ELIGIBILITY");
        
        // 3. 获取子网信息和参数
        SubnetTypes.SubnetInfo memory subnetInfo = subnetManager.getSubnetInfo(netuid);
        SubnetTypes.SubnetHyperparams memory params = subnetManager.getSubnetParams(netuid);
        
        require(subnetInfo.isActive, "SUBNET_NOT_ACTIVE");
        
        // 4. 检查子网神经元总数是否已满
        uint256 currentNeuronCount = neuronList[netuid].length;
        require(currentNeuronCount < params.maxAllowedUids, "SUBNET_NEURONS_FULL");
        
        // 5. 如果选择注册为验证者，检查验证者数量限制
        if (isValidatorRole) {
            uint256 currentValidatorCount = getSubnetValidatorCount(netuid);
            require(currentValidatorCount < params.maxAllowedValidators, "SUBNET_VALIDATORS_FULL");
        }
        
        // 6. 获取用户在该子网的有效质押
        uint256 userStake = globalStaking.getEffectiveStake(msg.sender, netuid);
        
        // 7. 检查神经元门槛
        require(userStake >= params.neuronThreshold, "INSUFFICIENT_NEURON_STAKE");
        
        // 8. 如果选择注册为验证者，检查验证者门槛
        if (isValidatorRole) {
            require(userStake >= params.validatorThreshold, "INSUFFICIENT_VALIDATOR_STAKE");
        }
        
        // 9. 检查子网质押要求
        require(
            globalStaking.canBecomeNeuron(msg.sender, netuid, params.baseBurnCost),
            "INSUFFICIENT_SUBNET_STAKE"
        );
        
        // 10. 锁定注册所需的质押
        globalStaking.lockSubnetStake(msg.sender, netuid, params.baseBurnCost);
        
        // 11. 确定最终角色（基于用户选择和质押量）
        bool finalIsValidator = isValidatorRole && (userStake >= params.validatorThreshold);
        
        // 12. 创建神经元信息
        neurons[netuid][msg.sender] = SubnetTypes.NeuronInfo({
            account: msg.sender,
            uid: 0, // 不使用 UID 系统
            netuid: netuid,
            isActive: true,
            isValidator: finalIsValidator,
            stake: userStake,
            registrationBlock: uint64(block.number),
            lastUpdate: block.timestamp,
            axonEndpoint: axonEndpoint,
            axonPort: axonPort,
            prometheusEndpoint: prometheusEndpoint,
            prometheusPort: prometheusPort
        });
        
        // 13. 添加到神经元列表
        neuronList[netuid].push(msg.sender);
        
        // 14. 发出事件供 native code 监听
        emit NeuronRegistered(
            netuid, 
            msg.sender, 
            userStake, 
            finalIsValidator,
            isValidatorRole,
            axonEndpoint,
            axonPort,
            prometheusEndpoint,
            prometheusPort,
            block.number
        );
    }
    
    /**
     * @dev 注销神经元
     */
    function deregisterNeuron(uint16 netuid) external nonReentrant {
        require(neurons[netuid][msg.sender].isActive, "NOT_REGISTERED");
        
        // SubnetTypes.NeuronInfo storage neuron = neurons[netuid][msg.sender];
        SubnetTypes.SubnetHyperparams memory params = subnetManager.getSubnetParams(netuid);
        
        // 解锁质押
        globalStaking.unlockSubnetStake(msg.sender, netuid, params.baseBurnCost);
        
        // 清除神经元
        delete neurons[netuid][msg.sender];
        
        // 从列表中移除
        _removeFromNeuronList(netuid, msg.sender);
        
        // 发出事件供 native code 监听
        emit NeuronDeregistered(netuid, msg.sender, block.number);
    }
    
    /**
     * @dev 更新质押分配（新增：检查门槛限制）
     */
    function updateStakeAllocation(
        uint16 netuid,
        address account,
        uint256 newStake
    ) external {
        require(
            msg.sender == address(globalStaking) || msg.sender == account,
            "UNAUTHORIZED_UPDATE"
        );
        require(neurons[netuid][account].isActive, "NEURON_NOT_ACTIVE");
        
        // 新增：检查门槛限制
        SubnetTypes.SubnetHyperparams memory params = subnetManager.getSubnetParams(netuid);
        SubnetTypes.NeuronInfo storage neuron = neurons[netuid][account];
        
        if (neuron.isValidator) {
            require(newStake >= params.validatorThreshold, "VALIDATOR_STAKE_BELOW_THRESHOLD");
        } else {
            require(newStake >= params.neuronThreshold, "NEURON_STAKE_BELOW_THRESHOLD");
        }
        
        _updateSingleStakeAllocation(netuid, account, newStake);
    }
    
    /**
     * @dev 更新服务信息
     */
    function updateService(
        uint16 netuid,
        string calldata axonEndpoint,
        uint32 axonPort,
        string calldata prometheusEndpoint,
        uint32 prometheusPort
    ) external {
        require(neurons[netuid][msg.sender].isActive, "NOT_REGISTERED");
        
        SubnetTypes.NeuronInfo storage neuron = neurons[netuid][msg.sender];
        neuron.axonEndpoint = axonEndpoint;
        neuron.axonPort = axonPort;
        neuron.prometheusEndpoint = prometheusEndpoint;
        neuron.prometheusPort = prometheusPort;
        neuron.lastUpdate = block.timestamp;
        
        // 发出事件供 native code 监听
        emit ServiceUpdated(
            netuid, 
            msg.sender, 
            axonEndpoint, 
            axonPort,
            prometheusEndpoint, 
            prometheusPort,
            block.number
        );
    }
    
    /**
     * @dev 分发奖励（由 native code 调用）
     */
    function distributeRewards(
        uint16 netuid,
        address[] calldata accounts,
        uint256[] calldata amounts
    ) external onlyRewardDistributor {
        require(accounts.length == amounts.length, "LENGTH_MISMATCH");
        require(subnetManager.subnetExists(netuid), "SUBNET_NOT_EXISTS");
        
        // 获取子网的Alpha代币地址
        SubnetTypes.SubnetInfo memory subnetInfo = subnetManager.getSubnetInfo(netuid);
        IAlphaToken alphaToken = IAlphaToken(subnetInfo.alphaToken);
        
        // 批量分发奖励 - mint Alpha代币给神经元
        for (uint i = 0; i < accounts.length; i++) {
            if (neurons[netuid][accounts[i]].isActive && amounts[i] > 0) {
                // 直接mint Alpha代币给神经元作为奖励
                alphaToken.mint(accounts[i], amounts[i]);
            }
        }
        
        // 发出事件记录奖励分发
        emit RewardsDistributed(netuid, accounts, amounts, block.number);
    }
    
    /**
     * @dev 批量更新神经元质押（优化gas消耗）
     */
    function batchUpdateStakeAllocations(
        uint16 netuid,
        address[] calldata accounts,
        uint256[] calldata newStakes
    ) external {
        require(msg.sender == address(globalStaking), "ONLY_GLOBAL_STAKING");
        require(accounts.length == newStakes.length, "LENGTH_MISMATCH");
        
        for (uint i = 0; i < accounts.length; i++) {
            if (neurons[netuid][accounts[i]].isActive) {
                _updateSingleStakeAllocation(netuid, accounts[i], newStakes[i]);
            }
        }
    }
    
    // ============ 查询函数 ============
    
    /**
     * @dev 获取神经元信息
     */
    function getNeuronInfo(uint16 netuid, address account) 
        external view returns (SubnetTypes.NeuronInfo memory) {
        return neurons[netuid][account];
    }
    
    /**
     * @dev 获取子网所有神经元地址
     */
    function getSubnetNeurons(uint16 netuid) 
        external view returns (address[] memory) {
        return neuronList[netuid];
    }
    
    /**
     * @dev 检查是否为神经元
     */
    function isNeuron(uint16 netuid, address account) external view returns (bool) {
        return neurons[netuid][account].isActive;
    }
    
    /**
     * @dev 检查是否为验证者
     */
    function isValidator(uint16 netuid, address account) external view returns (bool) {
        return neurons[netuid][account].isActive && neurons[netuid][account].isValidator;
    }
    
    /**
     * @dev 获取子网神经元数量
     */
    function getSubnetNeuronCount(uint16 netuid) external view returns (uint256) {
        return neuronList[netuid].length;
    }
    
    /**
     * @dev 获取子网所有验证者
     */
    function getSubnetValidators(uint16 netuid) external view returns (address[] memory) {
        address[] memory neurons_list = neuronList[netuid];
        address[] memory validators = new address[](neurons_list.length);
        uint256 validatorCount = 0;
        
        for (uint i = 0; i < neurons_list.length; i++) {
            if (neurons[netuid][neurons_list[i]].isValidator) {
                validators[validatorCount] = neurons_list[i];
                validatorCount++;
            }
        }
        
        // 调整数组大小
        address[] memory result = new address[](validatorCount);
        for (uint i = 0; i < validatorCount; i++) {
            result[i] = validators[i];
        }
        
        return result;
    }
    
    /**
     * @dev 检查用户是否可以注册为神经元
     */
    function canRegisterNeuron(address user, uint16 netuid, bool isValidatorRole) external view returns (bool) {
        if (neurons[netuid][user].isActive) return false;
        if (!globalStaking.hasParticipationEligibility(user)) return false;
        
        SubnetTypes.SubnetInfo memory subnetInfo = subnetManager.getSubnetInfo(netuid);
        SubnetTypes.SubnetHyperparams memory params = subnetManager.getSubnetParams(netuid);
        
        if (!subnetInfo.isActive) return false;
        
        // 检查神经元总数限制
        uint256 currentNeuronCount = neuronList[netuid].length;
        if (currentNeuronCount >= params.maxAllowedUids) return false;
        
        // 检查用户质押
        uint256 userStake = globalStaking.getEffectiveStake(user, netuid);
        if (userStake < params.neuronThreshold) return false;
        
        // 如果选择验证者角色，检查验证者数量限制和质押门槛
        if (isValidatorRole) {
            uint256 currentValidatorCount = getSubnetValidatorCount(netuid);
            if (currentValidatorCount >= params.maxAllowedValidators) return false;
            if (userStake < params.validatorThreshold) return false;
        }
        
        return globalStaking.canBecomeNeuron(user, netuid, params.baseBurnCost);
    }
    
    // ============ 内部函数 ============
    
    /**
     * @dev 从神经元列表中移除地址
     */
    function _removeFromNeuronList(uint16 netuid, address account) internal {
        address[] storage list = neuronList[netuid];
        for (uint i = 0; i < list.length; i++) {
            if (list[i] == account) {
                list[i] = list[list.length - 1];
                list.pop();
                break;
            }
        }
    }
    
    /**
     * @dev 更新单个神经元质押分配
     */
    function _updateSingleStakeAllocation(
        uint16 netuid,
        address account,
        uint256 newStake
    ) internal {
        SubnetTypes.NeuronInfo storage neuron = neurons[netuid][account];
        uint256 oldStake = neuron.stake;
        
        // 更新神经元信息
        neuron.stake = newStake;
        neuron.lastUpdate = block.timestamp;
        
        // 发出事件
        emit StakeAllocationChanged(
            netuid, 
            account, 
            oldStake, 
            newStake, 
            neuron.isValidator, 
            neuron.isValidator, // 角色不变
            block.number
        );
    }
}

