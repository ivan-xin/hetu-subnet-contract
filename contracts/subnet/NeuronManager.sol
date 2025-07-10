// contracts/neuron/NeuronManager.sol (移除权重设置版本)
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/ISubnetTypes.sol";

contract NeuronManager is ReentrancyGuard, Ownable {
    using SubnetTypes for *;
    
    ISubnetManager public immutable subnetManager;
    IGlobalStaking public immutable globalStaking;
    address public rewardDistributor; // native code 调用地址
    
    // 核心存储 - 只保留必要的映射
    mapping(uint16 => mapping(address => SubnetTypes.NeuronInfo)) public neurons;
    mapping(uint16 => address[]) public neuronList;
    
    // 事件 - native code 监听这些事件获取所有必要信息
    event NeuronRegistered(
        uint16 indexed netuid, 
        address indexed account, 
        uint256 stake,
        bool isValidator,
        string axonEndpoint,
        uint32 axonPort,
        string prometheusEndpoint,
        uint32 prometheusPort,
        uint256 blockNumber
    );
    
    event NeuronDeregistered(
        uint16 indexed netuid, 
        address indexed account, 
        uint256 blockNumber
    );
    
    event StakeAllocationChanged(
        uint16 indexed netuid,
        address indexed account,
        uint256 oldStake,
        uint256 newStake,
        bool wasValidator,
        bool isValidator,
        uint256 blockNumber
    );
    
    event ServiceUpdated(
        uint16 indexed netuid, 
        address indexed account,
        string axonEndpoint,
        uint32 axonPort,
        string prometheusEndpoint,
        uint32 prometheusPort,
        uint256 blockNumber
    );
    
    modifier onlyRewardDistributor() {
        require(msg.sender == rewardDistributor, "ONLY_REWARD_DISTRIBUTOR");
        _;
    }
    
    constructor(address _subnetManager, address _globalStaking) {
        require(_subnetManager != address(0), "ZERO_SUBNET_MANAGER");
        require(_globalStaking != address(0), "ZERO_GLOBAL_STAKING");
        
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
     * @dev 注册神经元
     */
    function registerNeuron(
        uint16 netuid,
        string calldata axonEndpoint,
        uint32 axonPort,
        string calldata prometheusEndpoint,
        uint32 prometheusPort
    ) external nonReentrant {
        require(subnetManager.subnetExists(netuid), "SUBNET_NOT_EXISTS");
        require(!neurons[netuid][msg.sender].isActive, "ALREADY_REGISTERED");
        
        // 获取子网信息和参数
        SubnetTypes.SubnetInfo memory subnetInfo = subnetManager.getSubnetInfo(netuid);
        SubnetTypes.SubnetHyperparams memory params = subnetManager.getSubnetParams(netuid);
        
        require(subnetInfo.isActive, "SUBNET_NOT_ACTIVE");
        require(subnetInfo.currentNeurons < params.maxValidators, "SUBNET_FULL");
        
        // 检查质押要求
        uint256 userStake = globalStaking.getEffectiveStake(msg.sender, netuid);
        require(userStake >= params.baseBurnCost, "INSUFFICIENT_STAKE");
        
        // 锁定质押
        globalStaking.lockSubnetStake(msg.sender, netuid, params.baseBurnCost);
        
        // 判断是否为验证者
        bool isValidator = userStake >= params.validatorThreshold;
        
        // 创建神经元信息
        neurons[netuid][msg.sender] = SubnetTypes.NeuronInfo({
            account: msg.sender,
            uid: 0, // 不使用 UID 系统
            netuid: netuid,
            isActive: true,
            isValidator: isValidator,
            stake: userStake,
            registrationBlock: block.number,
            lastUpdate: block.timestamp,
            axonEndpoint: axonEndpoint,
            axonPort: axonPort,
            prometheusEndpoint: prometheusEndpoint,
            prometheusPort: prometheusPort
        });
        
        // 添加到神经元列表
        neuronList[netuid].push(msg.sender);
        
        // 更新子网统计
        subnetManager.updateSubnetStats(
            netuid,
            uint16(neuronList[netuid].length),
            subnetInfo.totalStake + userStake
        );
        
        // 发出事件供 native code 监听
        emit NeuronRegistered(
            netuid, 
            msg.sender, 
            userStake, 
            isValidator,
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
        
        SubnetTypes.NeuronInfo storage neuron = neurons[netuid][msg.sender];
        SubnetTypes.SubnetHyperparams memory params = subnetManager.getSubnetParams(netuid);
        
        // 解锁质押
        globalStaking.unlockSubnetStake(msg.sender, netuid, params.baseBurnCost);
        
        // 清除神经元
        delete neurons[netuid][msg.sender];
        
        // 从列表中移除
        _removeFromNeuronList(netuid, msg.sender);
        
        // 更新子网统计
        SubnetTypes.SubnetInfo memory subnetInfo = subnetManager.getSubnetInfo(netuid);
        subnetManager.updateSubnetStats(
            netuid,
            uint16(neuronList[netuid].length),
            subnetInfo.totalStake - neuron.stake
        );
        
        // 发出事件供 native code 监听 - native code 会在当前 epoch 停止为该神经元计算奖励
        emit NeuronDeregistered(netuid, msg.sender, block.number);
    }
    
    /**
     * @dev 更新质押分配（由 GlobalStaking 调用）
     */
    function updateStakeAllocation(
        uint16 netuid,
        address account,
        uint256 newStake
    ) external {
        require(msg.sender == address(globalStaking), "ONLY_GLOBAL_STAKING");
        require(neurons[netuid][account].isActive, "NEURON_NOT_ACTIVE");
        
        SubnetTypes.NeuronInfo storage neuron = neurons[netuid][account];
        SubnetTypes.SubnetHyperparams memory params = subnetManager.getSubnetParams(netuid);
        
        uint256 oldStake = neuron.stake;
        bool wasValidator = neuron.isValidator;
        bool isValidator = newStake >= params.validatorThreshold;
        
        // 更新神经元信息
        neuron.stake = newStake;
        neuron.isValidator = isValidator;
        neuron.lastUpdate = block.timestamp;
        
        // 更新子网统计
        SubnetTypes.SubnetInfo memory subnetInfo = subnetManager.getSubnetInfo(netuid);
        subnetManager.updateSubnetStats(
            netuid,
            uint16(neuronList[netuid].length),
            subnetInfo.totalStake - oldStake + newStake
        );
        
        // 发出事件供 native code 监听 - 质押变化会影响奖励计算
        emit StakeAllocationChanged(
            netuid, 
            account, 
            oldStake, 
            newStake, 
            wasValidator, 
            isValidator, 
            block.number
        );
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
     * @param netuid 子网ID
     * @param accounts 神经元地址数组
     * @param amounts 奖励数量数组（Alpha代币数量）
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
        
        // 批量分发奖励
        for (uint i = 0; i < accounts.length; i++) {
            if (neurons[netuid][accounts[i]].isActive && amounts[i] > 0) {
                // 直接mint Alpha代币给神经元
                alphaToken.mint(accounts[i], amounts[i]);
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
}