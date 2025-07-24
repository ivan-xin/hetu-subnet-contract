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
    address public rewardDistributor; // Address called by native code
    
    // Core storage
    mapping(uint16 => mapping(address => SubnetTypes.NeuronInfo)) internal _neurons;
    mapping(uint16 => address[]) public neuronList;
    
    // mapping(address => bool) public authorizedCallers;
    

    // modifier onlyAuthorizedCaller() {
    //     require(authorizedCallers[msg.sender], "UNAUTHORIZED_CALLER");
    //     _;
    // }

    // modifier onlyAuthorizedCallerOrSelf() {
    //     require(authorizedCallers[msg.sender] || msg.sender == address(this), "UNAUTHORIZED_CALLER");
    //     _;
    // }

    
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
     * @dev Set reward distributor address (native code address)
     */
    function setRewardDistributor(address _rewardDistributor) external onlyOwner {
        require(_rewardDistributor != address(0), "ZERO_ADDRESS");
        rewardDistributor = _rewardDistributor;
    }
    
    /**
     * @dev Get subnet validator count
     */
    function getSubnetValidatorCount(uint16 netuid) public view returns (uint256) {
        uint256 count = 0;
        address[] memory neurons_list = neuronList[netuid];
        for (uint i = 0; i < neurons_list.length; i++) {
            if (_neurons[netuid][neurons_list[i]].isValidator) {
                count++;
            }
        }
        return count;
    }
    
    /**
     * @dev Register neuron with custom stake allocation
     */
    function registerNeuronWithStakeAllocation(
        uint16 netuid,
        uint256 stakeAmount,
        bool isValidatorRole,
        string calldata axonEndpoint,
        uint32 axonPort,
        string calldata prometheusEndpoint,
        uint32 prometheusPort
    ) external nonReentrant {
        require(stakeAmount > 0, "STAKE_AMOUNT_ZERO");
                
        // Call internal registration logic (no reallocation needed)
        _registerNeuronInternal(
            netuid,
            stakeAmount,
            isValidatorRole,
            axonEndpoint,
            axonPort,
            prometheusEndpoint,
            prometheusPort
        );
    }
    
    /**
     * @dev Internal function to handle neuron registration logic
     */
    function _registerNeuronInternal(
        uint16 netuid,
        uint256 stakeAmount,
        bool isValidatorRole,
        string calldata axonEndpoint,
        uint32 axonPort,
        string calldata prometheusEndpoint,
        uint32 prometheusPort
    ) internal {
        // 1. Basic checks
        require(subnetManager.subnetExists(netuid), "SUBNET_NOT_EXISTS");
        require(!_neurons[netuid][msg.sender].isActive, "ALREADY_REGISTERED");


        // 2. Get subnet info and parameters
        SubnetTypes.SubnetInfo memory subnetInfo = subnetManager.getSubnetInfo(netuid);
        SubnetTypes.SubnetHyperparams memory params = subnetManager.getSubnetParams(netuid);
        
        require(subnetInfo.isActive, "SUBNET_NOT_ACTIVE");

        // Pre-check: ensure user has enough available stake
        uint256 availableStake = globalStaking.getAvailableStake(msg.sender);
        uint256 totalRequired = stakeAmount + params.baseNeuronCost;
        require(availableStake >= totalRequired, "INSUFFICIENT_AVAILABLE_STAKE");
        
        // 3. Check neuron count limits
        uint256 currentNeuronCount = neuronList[netuid].length;
        require(currentNeuronCount < params.maxAllowedUids, "SUBNET_NEURONS_FULL");
        
        // 4. If registering as validator, check validator count limit
        if (isValidatorRole) {
            uint256 currentValidatorCount = getSubnetValidatorCount(netuid);
            require(currentValidatorCount < params.maxAllowedValidators, "SUBNET_VALIDATORS_FULL");
        }
        
        // 5. Validate stake amount
        require(stakeAmount >= params.neuronThreshold, "INSUFFICIENT_NEURON_STAKE");
        if (isValidatorRole) {
            require(stakeAmount >= params.validatorThreshold, "INSUFFICIENT_VALIDATOR_STAKE");
        }
        
        // 7. Allocate stake to subnet
        uint256 minThreshold = isValidatorRole ? params.validatorThreshold : params.neuronThreshold;
        globalStaking.allocateToSubnetWithMinThreshold(netuid, stakeAmount, minThreshold);

        // 7. Charge registration costs
        globalStaking.chargeRegistrationCost(msg.sender, netuid, params.baseNeuronCost);
        
        // 8. Determine final role
        bool finalIsValidator = isValidatorRole && (stakeAmount >= params.validatorThreshold);
        
        // 9. Create neuron info
        _neurons[netuid][msg.sender] = SubnetTypes.NeuronInfo({
            account: msg.sender,
            // uid: 0,
            netuid: netuid,
            isActive: true,
            isValidator: finalIsValidator,
            stake: stakeAmount,
            registrationBlock: uint64(block.number),
            lastUpdate: block.timestamp,
            axonEndpoint: axonEndpoint,
            axonPort: axonPort,
            prometheusEndpoint: prometheusEndpoint,
            prometheusPort: prometheusPort
        });
        
        // 11. Add to neuron list
        neuronList[netuid].push(msg.sender);
        
        // 12. Emit event
        emit NeuronRegistered(
            netuid, 
            msg.sender, 
            stakeAmount, 
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
     * @dev Deregister neuron
     */
    function deregisterNeuron(uint16 netuid) external nonReentrant {
            require(_neurons[netuid][msg.sender].isActive, "NOT_REGISTERED");
            // Clear neuron
            delete _neurons[netuid][msg.sender];
            
            // Remove from list
            _removeFromNeuronList(netuid, msg.sender);
            
            // Emit event for native code to monitor
            emit NeuronDeregistered(netuid, msg.sender, block.number);
    }
    
    /**
     * @dev Update stake allocation (New: check threshold limits)
     */
    function updateStakeAllocation(
        uint16 netuid,
        address account,
        uint256 newStake
    ) external {
        require(_neurons[netuid][account].isActive, "NEURON_NOT_ACTIVE");
        
        // New: check threshold limits
        SubnetTypes.SubnetHyperparams memory params = subnetManager.getSubnetParams(netuid);
        SubnetTypes.NeuronInfo storage neuron = _neurons[netuid][account];
        
        if (neuron.isValidator) {
            require(newStake >= params.validatorThreshold, "VALIDATOR_STAKE_BELOW_THRESHOLD");
        } else {
            require(newStake >= params.neuronThreshold, "NEURON_STAKE_BELOW_THRESHOLD");
        }
        
        uint256 oldStake = neuron.stake;
        
        // Update neuron info
        neuron.stake = newStake;
        neuron.lastUpdate = block.timestamp;

        // Emit event
        emit StakeAllocationChanged(
            netuid, 
            account, 
            oldStake, 
            newStake, 
            block.number
        );
    }
    
    /**
     * @dev Update service information
     */
    function updateNeuronService(
        uint16 netuid,
        string calldata axonEndpoint,
        uint32 axonPort,
        string calldata prometheusEndpoint,
        uint32 prometheusPort
    ) external {
        require(_neurons[netuid][msg.sender].isActive, "NOT_REGISTERED");
        
        SubnetTypes.NeuronInfo storage neuron = _neurons[netuid][msg.sender];
        neuron.axonEndpoint = axonEndpoint;
        neuron.axonPort = axonPort;
        neuron.prometheusEndpoint = prometheusEndpoint;
        neuron.prometheusPort = prometheusPort;
        neuron.lastUpdate = block.timestamp;
        
        // Emit event for native code to monitor
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
    
    // ============ Query Functions ============
    
    /**
     * @dev Get neuron information
     */
    function getNeuronInfo(uint16 netuid, address account) 
        external view returns (SubnetTypes.NeuronInfo memory) {
        return _neurons[netuid][account];
    }
    
    /**
     * @dev Get all neuron addresses in subnet
     */
    function getNeuronList(uint16 netuid) 
        external view returns (address[] memory) {
        return neuronList[netuid];
    }
    /**
     * @dev Get subnet neuron count
     */
    function getNeuronCount(uint16 netuid) 
        external view returns (uint256) {
        return neuronList[netuid].length;
    }

    /**
     * @dev Check if address is a neuron
     */
    function isNeuron(uint16 netuid, address account) external view returns (bool) {
        return _neurons[netuid][account].isActive;
    }
    
    /**
     * @dev Check if address is a validator
     */
    function isValidator(uint16 netuid, address account) external view returns (bool) {
        return _neurons[netuid][account].isActive && _neurons[netuid][account].isValidator;
    }
    
    /**
     * @dev Get subnet neuron count
     */
    function getSubnetNeuronCount(uint16 netuid) external view returns (uint256) {
        return neuronList[netuid].length;
    }
    
    /**
     * @dev Get all validators in subnet
     */
    function getSubnetValidators(uint16 netuid) external view returns (address[] memory) {
        address[] memory neurons_list = neuronList[netuid];
        address[] memory validators = new address[](neurons_list.length);
        uint256 validatorCount = 0;
        
        for (uint i = 0; i < neurons_list.length; i++) {
            if (_neurons[netuid][neurons_list[i]].isValidator) {
                validators[validatorCount] = neurons_list[i];
                validatorCount++;
            }
        }
        
        // Resize array
        address[] memory result = new address[](validatorCount);
        for (uint i = 0; i < validatorCount; i++) {
            result[i] = validators[i];
        }
        
        return result;
    }
    
    // ============ Internal Functions ============
    
    /**
     * @dev Remove address from neuron list
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

    // function setAuthorizedCaller(address caller, bool authorized) external 
    //     onlyRole(DEFAULT_ADMIN_ROLE) 
    // {
    //     require(caller != address(0), "ZERO_ADDRESS");
        
    //     bool oldStatus = authorizedCallers[caller];
    //     authorizedCallers[caller] = authorized;
        
    //     if (oldStatus != authorized) {
    //         emit AuthorizedCallerUpdated(caller, authorized);
    //     }
    // }
}

