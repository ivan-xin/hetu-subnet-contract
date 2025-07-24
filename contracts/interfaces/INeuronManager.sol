// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./ISubnetTypes.sol";

interface INeuronManager {

    // ============ Events ============
    
    /**
     * @dev Authorized caller update event
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
     * @dev Register neuron
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
     * @dev Deregister neuron
     */
    // function deregisterNeuron(uint16 netuid) external;

    /**
     * @dev Update neuron service information
     */
    function updateNeuronService(
        uint16 netuid,
        string calldata axonEndpoint,
        uint32 axonPort,
        string calldata prometheusEndpoint,
        uint32 prometheusPort
    ) external;

    /**
     * @dev Update stake allocation
     */
    function updateStakeAllocation(
        uint16 netuid,
        address account,
        uint256 newStake
    ) external;

    // ============ View Functions ============
    
    /**
     * @dev Check if it's a neuron
     */
    function isNeuron(uint16 netuid, address account) external view returns (bool);
    
    /**
     * @dev Check if it's a validator
     */
    function isValidator(uint16 netuid, address account) external view returns (bool);
    
    /**
     * @dev Get neuron information
     */
    function getNeuronInfo(uint16 netuid, address account) 
        external 
        view 
        returns (SubnetTypes.NeuronInfo memory);
    
    /**
     * @dev Get subnet neuron list
     */
    function getNeuronList(uint16 netuid) external view returns (address[] memory);
    
    /**
     * @dev Get subnet neuron count
     */
    function getNeuronCount(uint16 netuid) external view returns (uint256);


    /**
     * @dev Get subnet validator count (internal use)
     */
    function getSubnetValidatorCount(uint16 netuid) external view returns (uint256);

    // ============ Admin Functions ============
    
    /**
     * @dev Set GlobalStaking contract address
     */
    // function setGlobalStaking(address _globalStaking) external;
    
    /**
     * @dev Set SubnetManager contract address
     */
    // function setSubnetManager(address _subnetManager) external;

    /**
     * @dev Set authorized caller
     */
    // function setAuthorizedCaller(address caller, bool authorized) external;

}