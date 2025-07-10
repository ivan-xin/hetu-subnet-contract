// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library SubnetTypes {
        struct SubnetHyperparams {
        // 核心网络参数
        uint16 rho;                    // 共识参数
        uint16 kappa;                  // 激励参数  
        uint16 immunityPeriod;         // 免疫期
        uint16 tempo;                  // 网络节拍
        uint16 maxValidators;          // 最大验证者数
        uint16 activityCutoff;         // 活跃度阈值
        uint16 maxAllowedUids;         // 最大允许的神经元数量
        uint16 maxAllowedValidators;   // 最大允许的验证者数量
        uint16 minAllowedWeights;      // 验证者设置的权重向量中至少要有多少个非零权重值
        uint16 maxWeightsLimit;        // 最大权重限制

        // 经济参数
        uint256 baseBurnCost;          // 基础燃烧成本
        uint64 currentDifficulty;      // 当前挖矿难度
        uint16 targetRegsPerInterval;  // 目标注册频率
        uint16 maxRegsPerBlock;        // 每区块最大注册数
        uint64 weightsRateLimit;       // 权重设置频率限制
        
        // 治理参数
        bool registrationAllowed;      // 是否允许注册
        bool commitRevealEnabled;      // 提交-揭示机制
        uint64 commitRevealPeriod;     // 提交-揭示周期
        uint64 servingRateLimit;       // 服务频率限制
        uint16 validatorThreshold;     // 验证者门槛
        uint16 neuronThreshold;        // 神经元门槛
    }
    
    struct SubnetInfo {
        uint16 netuid;
        address owner;          // 子网所有者（单一地址）
        address alphaToken;     // Alpha代币地址
        address ammPool;        // AMM池子地址
        uint256 lockedAmount;   // 锁定的HETU数量
        uint256 poolInitialTao; // 注入池子的HETU数量
        uint256 burnedAmount;   // 燃烧的HETU数量
        uint256 createdAt;      // 创建时间
        bool isActive;          // 是否激活
        string name;            // 子网名称
        string description;     // 子网描述
    }
    
    // 简化的Axon信息 - 基于实际网络需求
    struct AxonInfo {
        uint128 ip;          // IPv4/IPv6地址，压缩存储
        uint16 port;         // 端口
        uint8 ipType;        // 4=IPv4, 6=IPv6
        uint8 protocol;      // 协议类型 (TCP=0, UDP=1, etc.)
        uint32 version;      // 版本号
        uint64 blockNumber;  // 注册区块号
    }
    
    // 简化的Prometheus信息
    struct PrometheusInfo {
        uint128 ip;          // IPv4/IPv6地址
        uint16 port;         // 端口
        uint8 ipType;        // IP类型
        uint32 version;      // 版本号
        uint64 blockNumber;  // 注册区块号
    }
    
    // 核心神经元信息 - 只存储必要数据
    struct NeuronCore {
        address account;              // 统一账户地址（不分hot/cold）
        uint16 uid;                   // UID
        bool isActive;                // 是否活跃
        bool isValidator;             // 是否为验证者
        uint64 registrationBlock;     // 注册区块
        uint64 lastActivityBlock;     // 最后活跃区块
        uint256 totalStake;           // 总质押量
    }
    
    // 网络指标 - 分离存储以节省gas
    struct NeuronMetrics {
        uint16 rank;                  // 排名
        uint16 trust;                 // 信任值
        uint16 validatorTrust;        // 验证者信任值 
        uint16 consensus;             // 共识值
        uint16 incentive;             // 激励值
        uint16 dividends;             // 分红值
        uint16 emission;              // 发行量（压缩）
        uint64 lastUpdate;            // 最后更新
    }
    
    // 完整神经元信息 - 仅用于查询，不存储
    struct DetailedNeuronInfo {
        NeuronCore core;
        NeuronMetrics metrics;
        AxonInfo axon;
        PrometheusInfo prometheus;
        uint256[] stakeAmounts;       // 质押金额数组
        address[] stakers;            // 质押者地址数组
        uint16[] weightUids;          // 权重目标UID
        uint16[] weightValues;        // 权重值
    }

    struct NeuronInfo {
        address account;              // 账户地址
        uint16 uid;                   // UID
        uint16 netuid;                // 子网ID
        bool isActive;                // 是否活跃
        bool isValidator;             // 是否为验证者
        uint256 stake;                // 质押量
        uint64 registrationBlock;     // 注册区块
        uint256 lastUpdate;           // 最后更新时间
        string axonEndpoint;          // Axon端点
        uint32 axonPort;              // Axon端口
        string prometheusEndpoint;    // Prometheus端点
        uint32 prometheusPort;        // Prometheus端口
    }
    
    struct WeightCommit {
        bytes32 commitHash;
        uint256 commitBlock;
        bool revealed;
    }
}
