// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./ISubnetTypes.sol";
import "./IGlobalStaking.sol";
import "./ISubnetManager.sol";

/**
 * @title INeuronManager
 * @dev 神经元管理器接口 - 定义神经元注册、管理和查询的标准接口
 */
interface INeuronManager {
    
    // ============ Events ============
    
    /**
     * @dev 神经元注册事件
     */
    event NeuronRegistered(
        uint16 indexed netuid, 
        address indexed account, 
        uint256 stake,
        bool isValidator,
        bool requestedValidatorRole,
        string axonEndpoint,
        uint32 axonPort,
        string prometheusEndpoint,
        uint32 prometheusPort,
        uint256 blockNumber
    );
    
    /**
     * @dev 神经元注销事件
     */
    event NeuronDeregistered(
        uint16 indexed netuid, 
        address indexed account, 
        uint256 blockNumber
    );
    
    /**
     * @dev 质押分配变更事件
     */
    event StakeAllocationChanged(
        uint16 indexed netuid,
        address indexed account,
        uint256 oldStake,
        uint256 newStake,
        bool wasValidator,
        bool isValidator,
        uint256 blockNumber
    );
    
    /**
     * @dev 服务信息更新事件
     */
    event ServiceUpdated(
        uint16 indexed netuid, 
        address indexed account,
        string axonEndpoint,
        uint32 axonPort,
        string prometheusEndpoint,
        uint32 prometheusPort,
        uint256 blockNumber
    );
    
    /**
     * @dev 奖励分发事件
     */
    event RewardsDistributed(
        uint16 indexed netuid,
        address[] accounts,
        uint256[] amounts,
        uint256 blockNumber
    );
    
    // ============ Core Functions ============
    
    /**
     * @dev 注册神经元
     * @param netuid 子网ID
     * @param isValidatorRole 是否选择验证者角色
     * @param axonEndpoint Axon服务端点
     * @param axonPort Axon服务端口
     * @param prometheusEndpoint Prometheus监控端点
     * @param prometheusPort Prometheus监控端口
     */
    function registerNeuron(
        uint16 netuid,
        bool isValidatorRole,
        string calldata axonEndpoint,
        uint32 axonPort,
        string calldata prometheusEndpoint,
        uint32 prometheusPort
    ) external;
    
    /**
     * @dev 注销神经元
     * @param netuid 子网ID
     */
    function deregisterNeuron(uint16 netuid) external;
    
    /**
     * @dev 更新质押分配
     * @param netuid 子网ID
     * @param account 账户地址
     * @param newStake 新的质押量
     */
    function updateStakeAllocation(
        uint16 netuid,
        address account,
        uint256 newStake
    ) external;
    
    /**
     * @dev 更新服务信息
     * @param netuid 子网ID
     * @param axonEndpoint 新的Axon端点
     * @param axonPort 新的Axon端口
     * @param prometheusEndpoint 新的Prometheus端点
     * @param prometheusPort 新的Prometheus端口
     */
    function updateService(
        uint16 netuid,
        string calldata axonEndpoint,
        uint32 axonPort,
        string calldata prometheusEndpoint,
        uint32 prometheusPort
    ) external;
    
    /**
     * @dev 分发奖励（仅奖励分发者可调用）
     * @param netuid 子网ID
     * @param accounts 接收奖励的账户数组
     * @param amounts 对应的奖励数量数组
     */
    function distributeRewards(
        uint16 netuid,
        address[] calldata accounts,
        uint256[] calldata amounts
    ) external;
    
    /**
     * @dev 批量更新神经元质押
     * @param netuid 子网ID
     * @param accounts 账户地址数组
     * @param newStakes 新质押量数组
     */
    function batchUpdateStakeAllocations(
        uint16 netuid,
        address[] calldata accounts,
        uint256[] calldata newStakes
    ) external;
    
    // ============ Query Functions ============
    
    /**
     * @dev 获取神经元信息
     * @param netuid 子网ID 
     * @param account 账户地址
     * @return 神经元信息结构体
     */
    function getNeuronInfo(uint16 netuid, address account) 
        external view returns (SubnetTypes.NeuronInfo memory);

    
    /**
     * @dev 检查是否为神经元
     * @param netuid 子网ID
     * @param account 账户地址
     * @return 是否为神经元
     */
    function isNeuron(uint16 netuid, address account) external view returns (bool);
    
    /**
     * @dev 检查是否为验证者
     * @param netuid 子网ID
     * @param account 账户地址
     * @return 是否为验证者
     */
    function isValidator(uint16 netuid, address account) external view returns (bool);
    
    /**
     * @dev 获取子网神经元数量
     * @param netuid 子网ID
     * @return 神经元总数
     */
    function getSubnetNeuronCount(uint16 netuid) external view returns (uint256);
    
    /**
     * @dev 获取子网验证者数量
     * @param netuid 子网ID
     * @return 验证者总数
     */
    function getSubnetValidatorCount(uint16 netuid) external view returns (uint256);
    
    /**
     * @dev 获取子网所有验证者
     * @param netuid 子网ID
     * @return 验证者地址数组
     */
    function getSubnetValidators(uint16 netuid) external view returns (address[] memory);
    
    /**
     * @dev 检查用户是否可以注册为神经元
     * @param user 用户地址
     * @param netuid 子网ID
     * @param isValidatorRole 是否选择验证者角色
     * @return 是否可以注册
     */
    function canRegisterNeuron(address user, uint16 netuid, bool isValidatorRole) 
        external view returns (bool);
    
    // ============ State Variables Access ============
    
    /**
     * @dev 获取子网管理器地址
     */
    function subnetManager() external view returns (ISubnetManager);
    
    /**
     * @dev 获取全局质押合约地址
     */
    function globalStaking() external view returns (IGlobalStaking);
    
    /**
     * @dev 获取奖励分发者地址
     */
    function rewardDistributor() external view returns (address);
    
    /**
     * @dev 获取神经元信息
     */
    function neurons(uint16 netuid, address account) external view returns (
        address account_,
        uint16 uid,
        uint16 netuid_,
        bool isActive,
        bool isValidator,
        uint256 stake,
        uint64 registrationBlock,
        uint256 lastUpdate,
        string memory axonEndpoint,
        uint32 axonPort,
        string memory prometheusEndpoint,
        uint32 prometheusPort
    );
    
    /**
     * @dev 获取子网神经元列表
     * @param netuid 子网ID
     * @param index 索引
     * @return 对应索引的神经元地址
     */
    function neuronList(uint16 netuid, uint256 index) external view returns (address);
    
    // ============ Admin Functions ============
    
    /**
     * @dev 设置奖励分发者地址（仅所有者）
     * @param _rewardDistributor 新的奖励分发者地址
     */
    function setRewardDistributor(address _rewardDistributor) external;

}
