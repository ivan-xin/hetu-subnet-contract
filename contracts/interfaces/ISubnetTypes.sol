// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library SubnetTypes {
        struct SubnetHyperparams {
        // Core network parameters
        uint16 rho;                    // Consensus parameter
        uint16 kappa;                  // Incentive parameter
        uint16 immunityPeriod;         // Immunity period
        uint16 tempo;                  // Network tempo
        uint16 maxValidators;          // Maximum validators
        uint16 activityCutoff;         // Activity threshold
        uint16 maxAllowedUids;         // Maximum allowed neurons
        uint16 maxAllowedValidators;   // Maximum allowed validators
        uint16 minAllowedWeights;      // Minimum number of non-zero weights in validator's weight vector
        uint16 maxWeightsLimit;        // Maximum weight limit

        // Economic parameters
        uint256 baseNeuronCost;          // Base burn cost for neuron registration
        uint64 currentDifficulty;      // Current mining difficulty ？
        uint16 targetRegsPerInterval;  // Target registration rate  ？
        uint16 maxRegsPerBlock;        // Maximum registrations per block ？
        uint64 weightsRateLimit;       // Weight setting rate limit ？
        
        // Governance parameters
        bool registrationAllowed;      // Whether registration is allowed ？
        bool commitRevealEnabled;      // Commit-reveal mechanism ？
        uint64 commitRevealPeriod;     // Commit-reveal period ？ 
        uint64 servingRateLimit;       // Service rate limit   ？
        uint256 validatorThreshold;     // Validator threshold
        uint256 neuronThreshold;        // Neuron threshold
    }
    
    struct SubnetInfo {
        uint16 netuid;
        address owner;          // Subnet owner (single address)
        address alphaToken;     // Alpha token address
        address ammPool;        // AMM pool address
        uint256 lockedAmount;   // Locked HETU amount
        uint256 poolInitialTao; // HETU amount injected into pool
        uint256 burnedAmount;   // Burned HETU amount
        uint256 createdAt;      // Creation time
        bool isActive;          // Whether active
        string name;            // Subnet name
        string description;     // Subnet description
    }
    // ============ Neuron Types ============

    struct NeuronInfo {
        address account;              // Account address
        uint16 netuid;                // Subnet ID
        bool isActive;                // Whether active
        bool isValidator;             // Whether validator
        uint256 stake;                // Stake amount
        uint64 registrationBlock;     // Registration block
        uint256 lastUpdate;           // Last update time
        string axonEndpoint;          // Axon endpoint
        uint32 axonPort;              // Axon port
        string prometheusEndpoint;    // Prometheus endpoint
        uint32 prometheusPort;        // Prometheus port
    }
}
