// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/ISubnetTypes.sol";

/**
 * @title DefaultHyperparams
 * @dev Default hyperparameter library, providing default configuration and validation functions for subnets
 */
library DefaultHyperparams {
    
    /**
     * @dev Returns default hyperparameters for a new subnet
     */
    function getDefaultHyperparams() internal pure returns (SubnetTypes.SubnetHyperparams memory) {
        return SubnetTypes.SubnetHyperparams({
            // Core Network Parameters
            rho: 10,                           // Consensus parameter
            kappa: 32767,                      // Incentive parameter (half of uint16 max value)
            immunityPeriod: 7200,              // Immunity period (about 1 day, assuming 12s per block)
            tempo: 99,                         // Network tempo (blocks)
            maxValidators: 64,                 // Maximum number of validators
            activityCutoff: 5000,              // Activity threshold
            maxAllowedUids: 4096,              // Maximum allowed number of neurons
            maxAllowedValidators: 128,         // Maximum allowed number of validators
            minAllowedWeights: 8,              // Minimum number of non-zero weights required for validators
            maxWeightsLimit: 1000,             // Maximum weight limit
            
            // Economic Parameters
            baseBurnCost: 1 * 1e18,            // Base burn cost for registering neurons (1 HETU)
            currentDifficulty: 10000000,       // Current mining difficulty
            targetRegsPerInterval: 2,          // Target registration rate (expected registrations per interval)
            maxRegsPerBlock: 1,                // Maximum registrations per block
            weightsRateLimit: 15000,             // Weight setting rate limit (in blocks)
            
            // Governance Parameters
            registrationAllowed: true,         // Whether new neuron registration is allowed
            commitRevealEnabled: false,        // Commit-reveal mechanism (initially disabled)
            commitRevealPeriod: 1000,          // Commit-reveal period (in blocks)
            servingRateLimit: 50,              // Service rate limit (in blocks)
            validatorThreshold: 1000,          // Minimum stake threshold for becoming a validator
            neuronThreshold: 100               // Minimum stake threshold for becoming a neuron
        });
    }
    
    /**
     * @dev Validates if hyperparameters are within acceptable ranges
     */
    function validateHyperparams(SubnetTypes.SubnetHyperparams memory params) internal pure returns (bool) {
        // Validate core parameters
        if (params.rho == 0 || params.rho > 1000) return false;
        if (params.kappa == 0) return false;
        if (params.immunityPeriod == 0 || params.immunityPeriod > 100000) return false;
        if (params.tempo == 0 || params.tempo > 10000) return false;
        if (params.maxValidators == 0 || params.maxValidators > params.maxAllowedValidators) return false;
        if (params.activityCutoff == 0 || params.activityCutoff > 50000) return false;
        if (params.maxAllowedUids == 0 || params.maxAllowedUids > 65535) return false;
        if (params.maxAllowedValidators == 0 || params.maxAllowedValidators > 1000) return false;
        if (params.minAllowedWeights == 0 || params.minAllowedWeights > params.maxWeightsLimit) return false;
        if (params.maxWeightsLimit == 0 || params.maxWeightsLimit > 10000) return false;
        
        // Critical constraint: weightsRateLimit must be greater than immunityPeriod
        if (params.weightsRateLimit <= params.immunityPeriod) return false;

        // Validate economic parameters
        if (params.baseBurnCost == 0) return false;
        if (params.currentDifficulty == 0) return false;
        if (params.targetRegsPerInterval == 0 || params.targetRegsPerInterval > 100) return false;
        if (params.maxRegsPerBlock == 0 || params.maxRegsPerBlock > 10) return false;
        if (params.weightsRateLimit == 0 || params.weightsRateLimit > 10000) return false;
        
        // Validate governance parameters
        if (params.commitRevealPeriod == 0 || params.commitRevealPeriod > 10000) return false;
        if (params.servingRateLimit == 0 || params.servingRateLimit > 1000) return false;
        if (params.validatorThreshold < params.neuronThreshold) return false;
        if (params.neuronThreshold == 0) return false;
        
        return true;
    }
    
    /**
     * @dev Get hyperparameters for test network (more relaxed settings)
     */
    function getTestnetHyperparams() internal pure returns (SubnetTypes.SubnetHyperparams memory) {
        SubnetTypes.SubnetHyperparams memory testParams = getDefaultHyperparams();
        
        // Testnet adjustments
        testParams.baseBurnCost = 0.1 * 1e18;      // Lower burn cost
        testParams.validatorThreshold = 10;        // Lower validator threshold
        testParams.neuronThreshold = 1;            // Lower neuron threshold
        testParams.immunityPeriod = 100;           // Shorter immunity period
        testParams.maxValidators = 16;             // Fewer maximum validators
        testParams.tempo = 50;                     // Faster network tempo
        
        return testParams;
    }
    
    /**
     * @dev Get hyperparameters for high-performance network
     */
    function getHighPerformanceHyperparams() internal pure returns (SubnetTypes.SubnetHyperparams memory) {
        SubnetTypes.SubnetHyperparams memory perfParams = getDefaultHyperparams();
        
        // High-performance network adjustments
        perfParams.maxValidators = 128;            // Increase validator count
        perfParams.maxAllowedUids = 8192;          // Increase neuron count
        perfParams.validatorThreshold = 5000;     // Higher validator threshold
        perfParams.neuronThreshold = 500;         // Higher neuron threshold
        perfParams.tempo = 200;                   // Slower network tempo for better stability
        perfParams.weightsRateLimit = 200;        // Increase weight setting interval
        
        return perfParams;
    }
    
    /**
     * @dev Merge custom parameters with default parameters
     * @param customParams Custom parameters
     * @param useCustomFlags Flag array indicating which parameters to use custom values
     */
    function mergeWithDefaults(
        SubnetTypes.SubnetHyperparams memory customParams,
        bool[21] memory useCustomFlags  // Flag array corresponding to 21 parameters
    ) internal pure returns (SubnetTypes.SubnetHyperparams memory) {
        SubnetTypes.SubnetHyperparams memory defaults = getDefaultHyperparams();
        SubnetTypes.SubnetHyperparams memory merged = defaults;
        
        // Selectively merge parameters based on flag array
        if (useCustomFlags[0]) merged.rho = customParams.rho;
        if (useCustomFlags[1]) merged.kappa = customParams.kappa;
        if (useCustomFlags[2]) merged.immunityPeriod = customParams.immunityPeriod;
        if (useCustomFlags[3]) merged.tempo = customParams.tempo;
        if (useCustomFlags[4]) merged.maxValidators = customParams.maxValidators;
        if (useCustomFlags[5]) merged.activityCutoff = customParams.activityCutoff;
        if (useCustomFlags[6]) merged.maxAllowedUids = customParams.maxAllowedUids;
        if (useCustomFlags[7]) merged.maxAllowedValidators = customParams.maxAllowedValidators;
        if (useCustomFlags[8]) merged.minAllowedWeights = customParams.minAllowedWeights;
        if (useCustomFlags[9]) merged.maxWeightsLimit = customParams.maxWeightsLimit;
        if (useCustomFlags[10]) merged.baseBurnCost = customParams.baseBurnCost;
        if (useCustomFlags[11]) merged.currentDifficulty = customParams.currentDifficulty;
        if (useCustomFlags[12]) merged.targetRegsPerInterval = customParams.targetRegsPerInterval;
        if (useCustomFlags[13]) merged.maxRegsPerBlock = customParams.maxRegsPerBlock;
        if (useCustomFlags[14]) merged.weightsRateLimit = customParams.weightsRateLimit;
        if (useCustomFlags[15]) merged.registrationAllowed = customParams.registrationAllowed;
        if (useCustomFlags[16]) merged.commitRevealEnabled = customParams.commitRevealEnabled;
        if (useCustomFlags[17]) merged.commitRevealPeriod = customParams.commitRevealPeriod;
        if (useCustomFlags[18]) merged.servingRateLimit = customParams.servingRateLimit;
        if (useCustomFlags[19]) merged.validatorThreshold = customParams.validatorThreshold;
        if (useCustomFlags[20]) merged.neuronThreshold = customParams.neuronThreshold;
        
        return merged;
    }
    
    /**
     * @dev Check if two hyperparameter configurations are equal
     */
    function isEqual(
        SubnetTypes.SubnetHyperparams memory a,
        SubnetTypes.SubnetHyperparams memory b
    ) internal pure returns (bool) {
        return (
            a.rho == b.rho &&
            a.kappa == b.kappa &&
            a.immunityPeriod == b.immunityPeriod &&
            a.tempo == b.tempo &&
            a.maxValidators == b.maxValidators &&
            a.activityCutoff == b.activityCutoff &&
            a.maxAllowedUids == b.maxAllowedUids &&
            a.maxAllowedValidators == b.maxAllowedValidators &&
            a.minAllowedWeights == b.minAllowedWeights &&
            a.maxWeightsLimit == b.maxWeightsLimit &&
            a.baseBurnCost == b.baseBurnCost &&
            a.currentDifficulty == b.currentDifficulty &&
            a.targetRegsPerInterval == b.targetRegsPerInterval &&
            a.maxRegsPerBlock == b.maxRegsPerBlock &&
            a.weightsRateLimit == b.weightsRateLimit &&
            a.registrationAllowed == b.registrationAllowed &&
            a.commitRevealEnabled == b.commitRevealEnabled &&
            a.commitRevealPeriod == b.commitRevealPeriod &&
            a.servingRateLimit == b.servingRateLimit &&
            a.validatorThreshold == b.validatorThreshold &&
            a.neuronThreshold == b.neuronThreshold
        );
    }
}
