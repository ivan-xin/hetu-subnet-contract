// contracts/factory/SubnetAMMFactory.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../amm/SubnetAMM.sol";

/**
 * @title SubnetAMMFactory
 * @dev 创建和管理SubnetAMM池子的工厂合约
 * 工厂创建者也无法操作具体的池子
 */
contract SubnetAMMFactory {
    // 池子映射
    mapping(uint16 => address) public getPool; // netuid => pool address
    mapping(address => bool) public isPool;
    address[] public allPools;
    
    // 系统地址
    address public immutable systemAddress;
    
    // 创建者（仅记录，无特殊权限）
    address public immutable creator;
    uint256 public immutable createdAt;
    
    event PoolCreated(
        uint16 indexed netuid,
        address indexed hetuToken,
        address indexed alphaToken,
        address pool,
        uint256 poolsLength
    );
    
    constructor(address _systemAddress) {
        require(_systemAddress != address(0), "Factory: ZERO_SYSTEM_ADDRESS");
        systemAddress = _systemAddress;
        creator = msg.sender;
        createdAt = block.timestamp;
    }
    
    /**
     * @dev 创建新的AMM池子
     * 任何人都可以创建，但创建者无法操作池子
     */
    function createPool(
        address hetuToken,
        address alphaToken,
        uint16 netuid,
        address subnetContract,
        SubnetAMM.MechanismType mechanism,
        uint256 minimumPoolLiquidity
    ) external returns (address pool) {
        require(hetuToken != address(0), "Factory: ZERO_HETU_ADDRESS");
        require(alphaToken != address(0), "Factory: ZERO_ALPHA_ADDRESS");
        require(hetuToken != alphaToken, "Factory: IDENTICAL_ADDRESSES");
        require(subnetContract != address(0), "Factory: ZERO_SUBNET_ADDRESS");
        require(getPool[netuid] == address(0), "Factory: POOL_EXISTS");
        require(minimumPoolLiquidity > 0, "Factory: ZERO_MIN_LIQUIDITY");
        
        // 创建新的AMM池子
        pool = address(new SubnetAMM(
            hetuToken,
            alphaToken,
            netuid,
            systemAddress,
            subnetContract,
            mechanism,
            minimumPoolLiquidity
        ));
        
        // 记录池子信息
        getPool[netuid] = pool;
        isPool[pool] = true;
        allPools.push(pool);
        
        emit PoolCreated(netuid, hetuToken, alphaToken, pool, allPools.length);
    }
    
    /**
     * @dev 获取所有池子数量
     */
    function allPoolsLength() external view returns (uint256) {
        return allPools.length;
    }
    
    /**
     * @dev 获取工厂信息
     */
    function getFactoryInfo() external view returns (
        address _creator,
        address _systemAddress,
        uint256 _createdAt,
        uint256 _totalPools
    ) {
        return (creator, systemAddress, createdAt, allPools.length);
    }
    
    /**
     * @dev 批量获取池子信息
     */
    function getPoolsInfo(uint256 start, uint256 end) external view returns (
        address[] memory pools,
        uint16[] memory netuids,
        SubnetAMM.MechanismType[] memory mechanisms,
        uint256[] memory totalVolumes
    ) {
        require(start <= end && end < allPools.length, "Factory: INVALID_RANGE");
        
        uint256 length = end - start + 1;
        pools = new address[](length);
        netuids = new uint16[](length);
        mechanisms = new SubnetAMM.MechanismType[](length);
        totalVolumes = new uint256[](length);
        
        for (uint256 i = 0; i < length; i++) {
            address pool = allPools[start + i];
            pools[i] = pool;
            
            SubnetAMM amm = SubnetAMM(pool);
            netuids[i] = amm.netuid();
            
            (
                SubnetAMM.MechanismType mechanism,
                ,,,,,
                uint256 totalVolume,
            ) = amm.getPoolInfo();
            
            mechanisms[i] = mechanism;
            totalVolumes[i] = totalVolume;
        }
    }
}

