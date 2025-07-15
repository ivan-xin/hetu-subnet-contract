// contracts/factory/SubnetAMMFactory.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../amm/SubnetAMM.sol";

/**
 * @title SubnetAMMFactory
 * @dev Factory contract for creating and managing SubnetAMM pools
 * Even factory creators cannot operate specific pools
 */
contract SubnetAMMFactory {
    // Pool mappings
    mapping(uint16 => address) public getPool; // netuid => pool address
    mapping(address => bool) public isPool;
    address[] public allPools;
    
    // System address
    address public immutable systemAddress;
    
    // Creator (only recorded, no special permissions)
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
     * @dev Create new AMM pool
     * Anyone can create, but creators cannot operate the pool
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
        
        // Create new AMM pool
        pool = address(new SubnetAMM(
            hetuToken,
            alphaToken,
            netuid,
            systemAddress,
            subnetContract,
            mechanism,
            minimumPoolLiquidity
        ));
        
        // Record pool information
        getPool[netuid] = pool;
        isPool[pool] = true;
        allPools.push(pool);
        
        emit PoolCreated(netuid, hetuToken, alphaToken, pool, allPools.length);
    }
    
    /**
     * @dev Get total number of pools
     */
    function allPoolsLength() external view returns (uint256) {
        return allPools.length;
    }
    
    /**
     * @dev Get factory information
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
     * @dev Batch get pool information
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
