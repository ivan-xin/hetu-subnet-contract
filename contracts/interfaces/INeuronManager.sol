// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./ISubnetTypes.sol";

interface INeuronManager {

    // ============ Events ============
    
    /**
     * @dev 授权调用者更新事件
     */
    event AuthorizedCallerUpdated(address indexed caller, bool authorized);
    /**
     * @dev Neuron registration event
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
     * @dev Neuron deregistration event
     */
    event NeuronDeregistered(
        uint16 indexed netuid, 
        address indexed account, 
        uint256 blockNumber
    );
    
    /**
     * @dev Stake allocation change event
     */
    event StakeAllocationChanged(
        uint16 indexed netuid,
        address indexed account,
        uint256 oldStake,
        uint256 newStake,
        uint256 blockNumber
    );
    
    /**
     * @dev Service information update event
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

    // ============ Core Functions ============
    
    /**
     * @dev 注册神经元
     */
    function registerNeuronWithStakeAllocation(
        uint16 netuid,
        uint256 stakeAmount,
        bool isValidatorRole,
        string calldata axonEndpoint,
        uint32 axonPort,
        string calldata prometheusEndpoint,
        uint32 prometheusPort
    ) external;

    /**
     * @dev 注销神经元
     */
    // function deregisterNeuron(uint16 netuid) external;

    /**
     * @dev 更新神经元服务信息
     */
    function updateNeuronService(
        uint16 netuid,
        string calldata axonEndpoint,
        uint32 axonPort,
        string calldata prometheusEndpoint,
        uint32 prometheusPort
    ) external;

    /**
     * @dev 更新质押分配
     */
    function updateStakeAllocation(
        uint16 netuid,
        address account,
        uint256 newStake
    ) external;

    // ============ View Functions ============
    
    /**
     * @dev 检查是否为神经元
     */
    function isNeuron(uint16 netuid, address account) external view returns (bool);
    
    /**
     * @dev 检查是否为验证者
     */
    function isValidator(uint16 netuid, address account) external view returns (bool);
    
    /**
     * @dev 获取神经元信息
     */
    function getNeuronInfo(uint16 netuid, address account) 
        external 
        view 
        returns (SubnetTypes.NeuronInfo memory);
    
    /**
     * @dev 获取子网神经元列表
     */
    function getNeuronList(uint16 netuid) external view returns (address[] memory);
    
    /**
     * @dev 获取子网神经元数量
     */
    function getNeuronCount(uint16 netuid) external view returns (uint256);


    /**
     * @dev 获取子网验证者数量（内部使用）
     */
    function getSubnetValidatorCount(uint16 netuid) external view returns (uint256);

    // ============ Admin Functions ============
    
    /**
     * @dev 设置 GlobalStaking 合约地址
     */
    // function setGlobalStaking(address _globalStaking) external;
    
    /**
     * @dev 设置 SubnetManager 合约地址
     */
    // function setSubnetManager(address _subnetManager) external;

    /**
     * @dev 设置授权调用者
     */
    // function setAuthorizedCaller(address caller, bool authorized) external;

}