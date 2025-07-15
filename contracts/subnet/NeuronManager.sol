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
            if (neurons[netuid][neurons_list[i]].isValidator) {
                count++;
            }
        }
        return count;
    }
    
    /**
     * @dev Register neuron
     */
    function registerNeuron(
        uint16 netuid,
        bool isValidatorRole,
        string calldata axonEndpoint,
        uint32 axonPort,
        string calldata prometheusEndpoint,
        uint32 prometheusPort
    ) external nonReentrant {
        // 1. Basic checks
        require(subnetManager.subnetExists(netuid), "SUBNET_NOT_EXISTS");
        require(!neurons[netuid][msg.sender].isActive, "ALREADY_REGISTERED");
        
        // 2. Check if user has participation eligibility (staked enough HETU)
        require(globalStaking.hasParticipationEligibility(msg.sender), "NO_PARTICIPATION_ELIGIBILITY");
        
        // 3. Get subnet info and parameters
        SubnetTypes.SubnetInfo memory subnetInfo = subnetManager.getSubnetInfo(netuid);
        SubnetTypes.SubnetHyperparams memory params = subnetManager.getSubnetParams(netuid);
        
        require(subnetInfo.isActive, "SUBNET_NOT_ACTIVE");
        
        // 4. Check if subnet neuron count is full
        uint256 currentNeuronCount = neuronList[netuid].length;
        require(currentNeuronCount < params.maxAllowedUids, "SUBNET_NEURONS_FULL");
        
        // 5. If registering as validator, check validator count limit
        if (isValidatorRole) {
            uint256 currentValidatorCount = getSubnetValidatorCount(netuid);
            require(currentValidatorCount < params.maxAllowedValidators, "SUBNET_VALIDATORS_FULL");
        }
        
        // 6. Get user's effective stake in the subnet
        uint256 userStake = globalStaking.getEffectiveStake(msg.sender, netuid);
        
        // 7. Check neuron threshold
        require(userStake >= params.neuronThreshold, "INSUFFICIENT_NEURON_STAKE");
        
        // 8. If registering as validator, check validator threshold
        if (isValidatorRole) {
            require(userStake >= params.validatorThreshold, "INSUFFICIENT_VALIDATOR_STAKE");
        }
        
        // 9. Check subnet stake requirements
        require(
            globalStaking.canBecomeNeuron(msg.sender, netuid, params.baseBurnCost),
            "INSUFFICIENT_SUBNET_STAKE"
        );
        
        // 10. Lock required stake for registration
        globalStaking.lockSubnetStake(msg.sender, netuid, params.baseBurnCost);
        
        // 11. Determine final role (based on user choice and stake amount)
        bool finalIsValidator = isValidatorRole && (userStake >= params.validatorThreshold);
        
        // 12. Create neuron info
        neurons[netuid][msg.sender] = SubnetTypes.NeuronInfo({
            account: msg.sender,
            uid: 0, // UID system not used
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
        
        // 13. Add to neuron list
        neuronList[netuid].push(msg.sender);
        
        // 14. Emit event for native code to monitor
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
     * @dev Deregister neuron
     */
    function deregisterNeuron(uint16 netuid) external nonReentrant {
        require(neurons[netuid][msg.sender].isActive, "NOT_REGISTERED");
        
        // SubnetTypes.NeuronInfo storage neuron = neurons[netuid][msg.sender];
        SubnetTypes.SubnetHyperparams memory params = subnetManager.getSubnetParams(netuid);
        
        // Unlock stake
        globalStaking.unlockSubnetStake(msg.sender, netuid, params.baseBurnCost);
        
        // Clear neuron
        delete neurons[netuid][msg.sender];
        
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
        require(
            msg.sender == address(globalStaking) || msg.sender == account,
            "UNAUTHORIZED_UPDATE"
        );
        require(neurons[netuid][account].isActive, "NEURON_NOT_ACTIVE");
        
        // New: check threshold limits
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
     * @dev Update service information
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
    
    /**
     * @dev Distribute rewards (called by native code)
     */
    function distributeRewards(
        uint16 netuid,
        address[] calldata accounts,
        uint256[] calldata amounts
    ) external onlyRewardDistributor {
        require(accounts.length == amounts.length, "LENGTH_MISMATCH");
        require(subnetManager.subnetExists(netuid), "SUBNET_NOT_EXISTS");
        
        // Get subnet's Alpha token address
        SubnetTypes.SubnetInfo memory subnetInfo = subnetManager.getSubnetInfo(netuid);
        IAlphaToken alphaToken = IAlphaToken(subnetInfo.alphaToken);
        
        // Batch distribute rewards - mint Alpha tokens to neurons
        for (uint i = 0; i < accounts.length; i++) {
            if (neurons[netuid][accounts[i]].isActive && amounts[i] > 0) {
                // Directly mint Alpha tokens to neurons as rewards
                alphaToken.mint(accounts[i], amounts[i]);
            }
        }
        
        // Emit event to record reward distribution
        emit RewardsDistributed(netuid, accounts, amounts, block.number);
    }
    
    /**
     * @dev Batch update neuron stakes (optimize gas consumption)
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
    
    // ============ Query Functions ============
    
    /**
     * @dev Get neuron information
     */
    function getNeuronInfo(uint16 netuid, address account) 
        external view returns (SubnetTypes.NeuronInfo memory) {
        return neurons[netuid][account];
    }
    
    /**
     * @dev Get all neuron addresses in subnet
     */
    function getSubnetNeurons(uint16 netuid) 
        external view returns (address[] memory) {
        return neuronList[netuid];
    }
    
    /**
     * @dev Check if address is a neuron
     */
    function isNeuron(uint16 netuid, address account) external view returns (bool) {
        return neurons[netuid][account].isActive;
    }
    
    /**
     * @dev Check if address is a validator
     */
    function isValidator(uint16 netuid, address account) external view returns (bool) {
        return neurons[netuid][account].isActive && neurons[netuid][account].isValidator;
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
            if (neurons[netuid][neurons_list[i]].isValidator) {
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
    
    /**
     * @dev Check if user can register as neuron
     */
    function canRegisterNeuron(address user, uint16 netuid, bool isValidatorRole) external view returns (bool) {
        if (neurons[netuid][user].isActive) return false;
        if (!globalStaking.hasParticipationEligibility(user)) return false;
        
        SubnetTypes.SubnetInfo memory subnetInfo = subnetManager.getSubnetInfo(netuid);
        SubnetTypes.SubnetHyperparams memory params = subnetManager.getSubnetParams(netuid);
        
        if (!subnetInfo.isActive) return false;
        
        // Check neuron count limit
        uint256 currentNeuronCount = neuronList[netuid].length;
        if (currentNeuronCount >= params.maxAllowedUids) return false;
        
        // Check user stake
        uint256 userStake = globalStaking.getEffectiveStake(user, netuid);
        if (userStake < params.neuronThreshold) return false;
        
        // If validator role, check validator count limit and stake threshold
        if (isValidatorRole) {
            uint256 currentValidatorCount = getSubnetValidatorCount(netuid);
            if (currentValidatorCount >= params.maxAllowedValidators) return false;
            if (userStake < params.validatorThreshold) return false;
        }
        
        return globalStaking.canBecomeNeuron(user, netuid, params.baseBurnCost);
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
    
    /**
     * @dev Update single neuron stake allocation
     */
    function _updateSingleStakeAllocation(
        uint16 netuid,
        address account,
        uint256 newStake
    ) internal {
        SubnetTypes.NeuronInfo storage neuron = neurons[netuid][account];
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
            neuron.isValidator, 
            neuron.isValidator, // Role remains unchanged
            block.number
        );
    }
}

