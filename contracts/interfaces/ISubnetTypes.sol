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
        uint64 currentDifficulty;      // Current mining difficulty
        uint16 targetRegsPerInterval;  // Target registration rate
        uint16 maxRegsPerBlock;        // Maximum registrations per block
        uint64 weightsRateLimit;       // Weight setting rate limit
        
        // Governance parameters
        bool registrationAllowed;      // Whether registration is allowed
        bool commitRevealEnabled;      // Commit-reveal mechanism
        uint64 commitRevealPeriod;     // Commit-reveal period
        uint64 servingRateLimit;       // Service rate limit
        uint16 validatorThreshold;     // Validator threshold
        uint16 neuronThreshold;        // Neuron threshold
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
    
    // Simplified Axon information - based on actual network needs
    struct AxonInfo {
        uint128 ip;          // IPv4/IPv6 address, compressed storage
        uint16 port;         // Port
        uint8 ipType;        // 4=IPv4, 6=IPv6
        uint8 protocol;      // Protocol type (TCP=0, UDP=1, etc.)
        uint32 version;      // Version number
        uint64 blockNumber;  // Registration block number
    }
    
    // Simplified Prometheus information
    struct PrometheusInfo {
        uint128 ip;          // IPv4/IPv6 address
        uint16 port;         // Port
        uint8 ipType;        // IP type
        uint32 version;      // Version number
        uint64 blockNumber;  // Registration block number
    }
    
    // Core neuron information - only stores essential data
    struct NeuronCore {
        address account;              // Unified account address (no hot/cold distinction)
        uint16 uid;                   // UID
        bool isActive;                // Whether active
        bool isValidator;             // Whether validator
        uint64 registrationBlock;     // Registration block
        uint64 lastActivityBlock;     // Last activity block
        uint256 totalStake;           // Total stake
    }
    
    // Network metrics - separate storage to save gas
    struct NeuronMetrics {
        uint16 rank;                  // Rank
        uint16 trust;                 // Trust value
        uint16 validatorTrust;        // Validator trust
        uint16 consensus;             // Consensus value
        uint16 incentive;             // Incentive value
        uint16 dividends;             // Dividends value
        uint16 emission;              // Emission (compressed)
        uint64 lastUpdate;            // Last update
    }
    
    // Complete neuron information - for queries only, not stored
    struct DetailedNeuronInfo {
        NeuronCore core;
        NeuronMetrics metrics;
        AxonInfo axon;
        PrometheusInfo prometheus;
        uint256[] stakeAmounts;       // Stake amounts array
        address[] stakers;            // Staker addresses array
        uint16[] weightUids;          // Weight target UIDs
        uint16[] weightValues;        // Weight values
    }

    struct NeuronInfo {
        address account;              // Account address
        // uint16 uid;                   // UID
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
    
    struct WeightCommit {
        bytes32 commitHash;
        uint256 commitBlock;
        bool revealed;
    }
}
