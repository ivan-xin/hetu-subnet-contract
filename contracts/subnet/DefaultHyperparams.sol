// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/ISubnetTypes.sol";

/**
 * @title DefaultHyperparams
 * @dev 默认超参数库，提供子网的默认配置和验证功能
 */
library DefaultHyperparams {
    
    /**
     * @dev 返回新子网的默认超参数
     */
    function getDefaultHyperparams() internal pure returns (SubnetTypes.SubnetHyperparams memory) {
        return SubnetTypes.SubnetHyperparams({
            // 核心网络参数
            rho: 10,                           // 共识参数
            kappa: 32767,                      // 激励参数 (uint16最大值的一半)
            immunityPeriod: 7200,              // 免疫期 (约1天，假设12秒一个区块)
            tempo: 99,                         // 网络节拍 (区块)
            maxValidators: 64,                 // 最大验证者数量
            activityCutoff: 5000,              // 活跃度阈值
            maxAllowedUids: 4096,              // 最大允许的神经元数量
            maxAllowedValidators: 128,         // 最大允许的验证者数量
            minAllowedWeights: 8,              // 验证者必须设置的最小非零权重数
            maxWeightsLimit: 1000,             // 最大权重限制
            
            // 经济参数
            baseBurnCost: 1 * 1e18,            // 注册神经元的基本燃烧成本 (1 HETU)
            currentDifficulty: 10000000,       // 当前挖矿难度
            targetRegsPerInterval: 2,          // 目标注册频率 (每个间隔期望注册数)
            maxRegsPerBlock: 1,                // 每区块最大注册数
            weightsRateLimit: 15000,             // 权重设置频率限制 (区块数)
            
            // 治理参数
            registrationAllowed: true,         // 是否允许新神经元注册
            commitRevealEnabled: false,        // 提交-揭示机制 (初始关闭)
            commitRevealPeriod: 1000,          // 提交-揭示周期 (区块数)
            servingRateLimit: 50,              // 服务频率限制 (区块数)
            validatorThreshold: 1000,          // 成为验证者的最小质押门槛
            neuronThreshold: 100               // 成为神经元的最小质押门槛
        });
    }
    
    /**
     * @dev 验证超参数是否在可接受的范围内
     */
    function validateHyperparams(SubnetTypes.SubnetHyperparams memory params) internal pure returns (bool) {
        // 验证核心参数
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
        
        // 关键约束：weightsRateLimit 必须大于 immunityPeriod
        if (params.weightsRateLimit <= params.immunityPeriod) return false;

        // 验证经济参数
        if (params.baseBurnCost == 0) return false;
        if (params.currentDifficulty == 0) return false;
        if (params.targetRegsPerInterval == 0 || params.targetRegsPerInterval > 100) return false;
        if (params.maxRegsPerBlock == 0 || params.maxRegsPerBlock > 10) return false;
        if (params.weightsRateLimit == 0 || params.weightsRateLimit > 10000) return false;
        
        // 验证治理参数
        if (params.commitRevealPeriod == 0 || params.commitRevealPeriod > 10000) return false;
        if (params.servingRateLimit == 0 || params.servingRateLimit > 1000) return false;
        if (params.validatorThreshold < params.neuronThreshold) return false;
        if (params.neuronThreshold == 0) return false;
        
        return true;
    }
    
    /**
     * @dev 获取测试网络的超参数 (更宽松的设置)
     */
    function getTestnetHyperparams() internal pure returns (SubnetTypes.SubnetHyperparams memory) {
        SubnetTypes.SubnetHyperparams memory testParams = getDefaultHyperparams();
        
        // 测试网络的调整
        testParams.baseBurnCost = 0.1 * 1e18;      // 降低燃烧成本
        testParams.validatorThreshold = 10;        // 降低验证者门槛
        testParams.neuronThreshold = 1;            // 降低神经元门槛
        testParams.immunityPeriod = 100;           // 缩短免疫期
        testParams.maxValidators = 16;             // 减少最大验证者数
        testParams.tempo = 50;                     // 加快网络节拍
        
        return testParams;
    }
    
    /**
     * @dev 获取高性能网络的超参数
     */
    function getHighPerformanceHyperparams() internal pure returns (SubnetTypes.SubnetHyperparams memory) {
        SubnetTypes.SubnetHyperparams memory perfParams = getDefaultHyperparams();
        
        // 高性能网络的调整
        perfParams.maxValidators = 128;            // 增加验证者数量
        perfParams.maxAllowedUids = 8192;          // 增加神经元数量
        perfParams.validatorThreshold = 5000;     // 提高验证者门槛
        perfParams.neuronThreshold = 500;         // 提高神经元门槛
        perfParams.tempo = 200;                   // 放慢网络节拍以提高稳定性
        perfParams.weightsRateLimit = 200;        // 增加权重设置间隔
        
        return perfParams;
    }
    
    /**
     * @dev 合并自定义参数与默认参数
     * @param customParams 自定义参数
     * @param useCustomFlags 标记数组，指示哪些参数使用自定义值
     */
    function mergeWithDefaults(
        SubnetTypes.SubnetHyperparams memory customParams,
        bool[21] memory useCustomFlags  // 对应21个参数的标记数组
    ) internal pure returns (SubnetTypes.SubnetHyperparams memory) {
        SubnetTypes.SubnetHyperparams memory defaults = getDefaultHyperparams();
        SubnetTypes.SubnetHyperparams memory merged = defaults;
        
        // 根据标记数组选择性合并参数
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
     * @dev 检查两个超参数配置是否相等
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
