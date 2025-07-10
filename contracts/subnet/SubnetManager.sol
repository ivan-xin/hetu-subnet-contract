// contracts/subnet/SubnetManagerSimplified.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../tokens/AlphaToken.sol";
import "../amm/SubnetAMM.sol";
import "../factory/SubnetAMMFactory.sol";

/**
 * @title SubnetManagerSimplified
 * @dev 简化版子网管理器，移除hotkey/coldkey复杂性
 */
contract SubnetManagerSimplified is ReentrancyGuard, Ownable {
    
    IERC20 public immutable hetuToken;
    SubnetAMMFactory public immutable ammFactory;
    
    // 简化的子网信息
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
    
    mapping(uint16 => SubnetInfo) public subnets;
    mapping(uint16 => bool) public subnetExists;
    mapping(address => uint16[]) public ownerSubnets; // 一个用户可以拥有多个子网
    
    uint16 public totalNetworks;
    uint16 public nextNetuid = 1;
    
    // 网络参数
    uint256 public networkMinLock = 100 * 1e18;
    uint256 public networkLastLock;
    uint256 public networkLastLockBlock;
    uint256 public networkRateLimit = 1000;
    uint256 public lockReductionInterval = 10000;
    
    event NetworkRegistered(
        uint16 indexed netuid,
        address indexed owner,
        address alphaToken,
        address ammPool,
        uint256 lockedAmount,
        uint256 poolAmount,
        uint256 burnedAmount,
        string name
    );
    
    constructor(address _hetuToken, address _ammFactory) {
        require(_hetuToken != address(0), "ZERO_HETU_ADDRESS");
        require(_ammFactory != address(0), "ZERO_FACTORY_ADDRESS");
        
        hetuToken = IERC20(_hetuToken);
        ammFactory = SubnetAMMFactory(_ammFactory);
        networkLastLockBlock = block.number;
    }
    
    /**
     * @dev 注册新子网 - 简化版本
     */
    function registerNetwork(
        string calldata name,
        string calldata description,
        string calldata tokenName,
        string calldata tokenSymbol
    ) external nonReentrant returns (uint16 netuid) {
        address owner = msg.sender;
        
        // 基本验证
        require(bytes(name).length > 0, "EMPTY_NAME");
        require(bytes(tokenName).length > 0, "EMPTY_TOKEN_NAME");
        require(bytes(tokenSymbol).length > 0, "EMPTY_TOKEN_SYMBOL");
        
        // 速率限制
        require(
            block.number - networkLastLockBlock >= networkRateLimit,
            "RATE_LIMIT_EXCEEDED"
        );
        
        // 计算并锁定成本
        uint256 lockAmount = getNetworkLockCost();
        hetuToken.transferFrom(owner, address(this), lockAmount);
        
        // 获取netuid
        netuid = getNextNetuid();
        
        // 计算池子资金
        uint256 poolInitialTao = networkMinLock;
        uint256 burnedAmount = lockAmount > poolInitialTao ? lockAmount - poolInitialTao : 0;
        
        // 创建Alpha代币和AMM池子
        address alphaTokenAddress = _createAlphaToken(netuid, tokenName, tokenSymbol);
        address ammPoolAddress = _createAMMPool(netuid, alphaTokenAddress, poolInitialTao);
        
        // 燃烧超额代币
        if (burnedAmount > 0) {
            _burnTokens(burnedAmount);
        }
        
        // 记录子网信息
        subnets[netuid] = SubnetInfo({
            netuid: netuid,
            owner: owner,
            alphaToken: alphaTokenAddress,
            ammPool: ammPoolAddress,
            lockedAmount: lockAmount,
            poolInitialTao: poolInitialTao,
            burnedAmount: burnedAmount,
            createdAt: block.timestamp,
            isActive: true,
            name: name,
            description: description
        });
        
        subnetExists[netuid] = true;
        ownerSubnets[owner].push(netuid);
        totalNetworks++;
        
        // 更新参数
        networkLastLock = lockAmount;
        networkLastLockBlock = block.number;
        
        emit NetworkRegistered(
            netuid, owner, alphaTokenAddress, ammPoolAddress,
            lockAmount, poolInitialTao, burnedAmount, name
        );
        
        return netuid;
    }
    
    /**
     * @dev 转移子网所有权
     */
    function transferSubnetOwnership(uint16 netuid, address newOwner) external {
        require(subnetExists[netuid], "SUBNET_NOT_EXISTS");
        require(subnets[netuid].owner == msg.sender, "NOT_OWNER");
        require(newOwner != address(0), "ZERO_ADDRESS");
        require(newOwner != msg.sender, "SAME_OWNER");
        
        address oldOwner = subnets[netuid].owner;
        subnets[netuid].owner = newOwner;
        
        // 更新所有权映射
        _removeFromOwnerSubnets(oldOwner, netuid);
        ownerSubnets[newOwner].push(netuid);
        
        emit SubnetOwnershipTransferred(netuid, oldOwner, newOwner);
    }
    
    /**
     * @dev 更新子网信息
     */
    function updateSubnetInfo(
        uint16 netuid,
        string calldata newName,
        string calldata newDescription
    ) external {
        require(subnetExists[netuid], "SUBNET_NOT_EXISTS");
        require(subnets[netuid].owner == msg.sender, "NOT_OWNER");
        require(bytes(newName).length > 0, "EMPTY_NAME");
        
        subnets[netuid].name = newName;
        subnets[netuid].description = newDescription;
        
        emit SubnetInfoUpdated(netuid, newName, newDescription);
    }
    
    /**
     * @dev 获取用户拥有的所有子网
     */
    function getUserSubnets(address user) external view returns (uint16[] memory) {
        return ownerSubnets[user];
    }
    
    /**
     * @dev 获取子网详细信息
     */
    function getSubnetDetails(uint16 netuid) external view returns (
        SubnetInfo memory subnetInfo,
        uint256 currentPrice,
        uint256 totalVolume,
        uint256 hetuReserve,
        uint256 alphaReserve
    ) {
        require(subnetExists[netuid], "SUBNET_NOT_EXISTS");
        
        subnetInfo = subnets[netuid];
        
        // 获取AMM池子信息
        SubnetAMM pool = SubnetAMM(subnetInfo.ammPool);
        (
            ,
            uint256 _subnetTAO,
            uint256 _subnetAlphaIn,
            ,
            uint256 _currentPrice,
            ,
            uint256 _totalVolume,
        ) = pool.getPoolInfo();
        
        currentPrice = _currentPrice;
        totalVolume = _totalVolume;
        hetuReserve = _subnetTAO;
        alphaReserve = _subnetAlphaIn;
    }
    
    // 内部函数保持不变...
    function _createAlphaToken(uint16 netuid, string calldata name, string calldata symbol) internal returns (address) {
        AlphaToken alphaToken = new AlphaToken(name, symbol, address(this), netuid);
        uint256 initialAlphaAmount = networkMinLock;
        alphaToken.mint(address(this), initialAlphaAmount);
        return address(alphaToken);
    }
    
    function _createAMMPool(uint16 netuid, address alphaTokenAddress, uint256 poolInitialTao) internal returns (address) {
        address poolAddress = ammFactory.createPool(
            address(hetuToken),
            alphaTokenAddress,
            netuid,
            address(this),
            SubnetAMM.MechanismType.Dynamic,
            1000 * 1e18
        );
        
        hetuToken.approve(poolAddress, poolInitialTao);
        IERC20(alphaTokenAddress).approve(poolAddress, poolInitialTao);
        
        SubnetAMM(poolAddress).injectLiquidity(poolInitialTao, poolInitialTao);
        
        return poolAddress;
    }
    
    function _burnTokens(uint256 amount) internal {
        hetuToken.transfer(address(0x000000000000000000000000000000000000dEaD), amount);
    }
    
    function _removeFromOwnerSubnets(address owner, uint16 netuid) internal {
        uint16[] storage subnets = ownerSubnets[owner];
        for (uint256 i = 0; i < subnets.length; i++) {
            if (subnets[i] == netuid) {
                subnets[i] = subnets[subnets.length - 1];
                subnets.pop();
                break;
            }
        }
    }
    
    function getNetworkLockCost() public view returns (uint256) {
        uint256 lastLock = networkLastLock;
        uint256 minLock = networkMinLock;
        uint256 lastLockBlock = networkLastLockBlock;
        uint256 currentBlock = block.number;
        uint256 reductionInterval = lockReductionInterval;
        
        uint256 mult = lastLockBlock == 0 ? 1 : 2;
        uint256 lockCost = lastLock * mult;
        
        if (currentBlock > lastLockBlock && reductionInterval > 0) {
            uint256 blocksPassed = currentBlock - lastLockBlock;
            uint256 reduction = (lastLock * blocksPassed) / reductionInterval;
            lockCost = lockCost > reduction ? lockCost - reduction : minLock;
        }
        
        if (lockCost < minLock) {
            lockCost = minLock;
        }
        
        return lockCost;
    }
    
    function getNextNetuid() public view returns (uint16) {
        uint16 candidateNetuid = nextNetuid;
        while (subnetExists[candidateNetuid]) {
            candidateNetuid++;
            require(candidateNetuid != 0, "NETUID_OVERFLOW");
        }
        return candidateNetuid;
    }
    
    // 事件定义
    event SubnetOwnershipTransferred(uint16 indexed netuid, address indexed oldOwner, address indexed newOwner);
    event SubnetInfoUpdated(uint16 indexed netuid, string name, string description);
}
