// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./ISubnetTypes.sol";
import "./IGlobalStaking.sol";
import "./ISubnetManager.sol";

/**
 * @title INeuronManager
 * @dev Neuron Manager Interface - Defines standard interfaces for neuron registration, management and queries
 */
interface INeuronManager {
    
    // ============ Events ============
    
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
        bool wasValidator,
        bool isValidator,
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
    
    /**
     * @dev Rewards distribution event
     */
    event RewardsDistributed(
        uint16 indexed netuid,
        address[] accounts,
        uint256[] amounts,
        uint256 blockNumber
    );
    
    // ============ Core Functions ============
    
    /**
     * @dev Register neuron
     * @param netuid Subnet ID
     * @param isValidatorRole Whether to choose validator role
     * @param axonEndpoint Axon service endpoint
     * @param axonPort Axon service port
     * @param prometheusEndpoint Prometheus monitoring endpoint
     * @param prometheusPort Prometheus monitoring port
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
     * @dev Deregister neuron
     * @param netuid Subnet ID
     */
    function deregisterNeuron(uint16 netuid) external;
    
    /**
     * @dev Update stake allocation
     * @param netuid Subnet ID
     * @param account Account address
     * @param newStake New stake amount
     */
    function updateStakeAllocation(
        uint16 netuid,
        address account,
        uint256 newStake
    ) external;
    
    /**
     * @dev Update service information
     * @param netuid Subnet ID
     * @param axonEndpoint New Axon endpoint
     * @param axonPort New Axon port
     * @param prometheusEndpoint New Prometheus endpoint
     * @param prometheusPort New Prometheus port
     */
    function updateService(
        uint16 netuid,
        string calldata axonEndpoint,
        uint32 axonPort,
        string calldata prometheusEndpoint,
        uint32 prometheusPort
    ) external;
    
    /**
     * @dev Distribute rewards (only callable by reward distributor)
     * @param netuid Subnet ID
     * @param accounts Array of accounts receiving rewards
     * @param amounts Array of corresponding reward amounts
     */
    function distributeRewards(
        uint16 netuid,
        address[] calldata accounts,
        uint256[] calldata amounts
    ) external;
    
    /**
     * @dev Batch update neuron stakes
     * @param netuid Subnet ID
     * @param accounts Array of account addresses
     * @param newStakes Array of new stake amounts
     */
    function batchUpdateStakeAllocations(
        uint16 netuid,
        address[] calldata accounts,
        uint256[] calldata newStakes
    ) external;
    
    // ============ Query Functions ============
    
    /**
     * @dev Get neuron information
     * @param netuid Subnet ID
     * @param account Account address
     * @return Neuron information struct
     */
    function getNeuronInfo(uint16 netuid, address account) 
        external view returns (SubnetTypes.NeuronInfo memory);

    
    /**
     * @dev Check if is neuron
     * @param netuid Subnet ID
     * @param account Account address
     * @return Whether is neuron
     */
    function isNeuron(uint16 netuid, address account) external view returns (bool);
    
    /**
     * @dev Check if is validator
     * @param netuid Subnet ID
     * @param account Account address
     * @return Whether is validator
     */
    function isValidator(uint16 netuid, address account) external view returns (bool);
    
    /**
     * @dev Get subnet neuron count
     * @param netuid Subnet ID
     * @return Total number of neurons
     */
    function getSubnetNeuronCount(uint16 netuid) external view returns (uint256);
    
    /**
     * @dev Get subnet validator count
     * @param netuid Subnet ID
     * @return Total number of validators
     */
    function getSubnetValidatorCount(uint16 netuid) external view returns (uint256);
    
    /**
     * @dev Get all subnet validators
     * @param netuid Subnet ID
     * @return Array of validator addresses
     */
    function getSubnetValidators(uint16 netuid) external view returns (address[] memory);
    
    /**
     * @dev Check if user can register as neuron
     * @param user User address
     * @param netuid Subnet ID
     * @param isValidatorRole Whether choosing validator role
     * @return Whether can register
     */
    function canRegisterNeuron(address user, uint16 netuid, bool isValidatorRole) 
        external view returns (bool);
    
    // ============ State Variables Access ============
    
    /**
     * @dev Get subnet manager address
     */
    function subnetManager() external view returns (ISubnetManager);
    
    /**
     * @dev Get global staking contract address
     */
    function globalStaking() external view returns (IGlobalStaking);
    
    /**
     * @dev Get reward distributor address
     */
    function rewardDistributor() external view returns (address);
    
    /**
     * @dev Get neuron information
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
     * @dev Get subnet neuron list
     * @param netuid Subnet ID
     * @param index Index
     * @return Neuron address at corresponding index
     */
    function neuronList(uint16 netuid, uint256 index) external view returns (address);
    
    // ============ Admin Functions ============
    
    /**
     * @dev Set reward distributor address (owner only)
     * @param _rewardDistributor New reward distributor address
     */
    function setRewardDistributor(address _rewardDistributor) external;

}
