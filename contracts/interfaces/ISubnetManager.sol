// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./ISubnetTypes.sol";

/**
 * @title ISubnetManager
 * @dev 子网管理器接口
 */
interface ISubnetManager {
    
    // ============ Events ============
    
    /**
     * @dev 子网注册事件
     */
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
    
    /**
     * @dev 子网所有权转移事件
     */
    event SubnetOwnershipTransferred(
        uint16 indexed netuid, 
        address indexed oldOwner, 
        address indexed newOwner
    );
    
    /**
     * @dev 子网信息更新事件
     */
    event SubnetInfoUpdated(
        uint16 indexed netuid, 
        string name, 
        string description
    );
    
    // ============ Core Functions ============
    
    /**
     * @dev 注册新子网
     * @param name 子网名称
     * @param description 子网描述
     * @param tokenName Alpha代币名称
     * @param tokenSymbol Alpha代币符号
     * @return netuid 分配的子网ID
     */
    function registerNetwork(
        string calldata name,
        string calldata description,
        string calldata tokenName,
        string calldata tokenSymbol
    ) external returns (uint16 netuid);
    
    /**
     * @dev 转移子网所有权
     * @param netuid 子网ID
     * @param newOwner 新所有者地址
     */
    function transferSubnetOwnership(uint16 netuid, address newOwner) external;
    
    /**
     * @dev 更新子网信息
     * @param netuid 子网ID
     * @param newName 新名称
     * @param newDescription 新描述
     */
    function updateSubnetInfo(
        uint16 netuid,
        string calldata newName,
        string calldata newDescription
    ) external;
    
    // ============ View Functions ============
    
    /**
     * @dev 获取用户拥有的所有子网
     * @param user 用户地址
     * @return 子网ID数组
     */
    function getUserSubnets(address user) external view returns (uint16[] memory);
    
    /**
     * @dev 获取子网详细信息
     * @param netuid 子网ID
     * @return subnetInfo 子网基本信息
     * @return currentPrice 当前价格
     * @return totalVolume 总交易量
     * @return hetuReserve HETU储备量
     * @return alphaReserve Alpha储备量
     */
    function getSubnetDetails(uint16 netuid) external view returns (
        SubnetTypes.SubnetInfo memory subnetInfo,
        uint256 currentPrice,
        uint256 totalVolume,
        uint256 hetuReserve,
        uint256 alphaReserve
    );
    
    /**
     * @dev 获取网络锁定成本
     * @return 当前注册子网需要的锁定成本
     */
    function getNetworkLockCost() external view returns (uint256);
    
    /**
     * @dev 获取下一个可用的子网ID
     * @return 下一个可用的netuid
     */
    function getNextNetuid() external view returns (uint16);
    
    /**
     * @dev 检查子网是否存在
     * @param netuid 子网ID
     * @return 是否存在
     */
    function subnetExists(uint16 netuid) external view returns (bool);
    
    //**
    //* @dev 获取子网基本信息
    //* @param netuid 子网ID
    //* @return 子网信息结构体
    //**
    function subnets(uint16 netuid) external view returns (
        uint16 netuid_,
        address owner,
        address alphaToken,
        address ammPool,
        uint256 lockedAmount,
        uint256 poolInitialTao,
        uint256 burnedAmount,
        uint256 createdAt,
        bool isActive,
        string memory name,
        string memory description
    );
    
    // ============ Network Parameters ============
    
    /**
     * @dev 获取网络参数
     */
    function networkMinLock() external view returns (uint256);
    function networkLastLock() external view returns (uint256);
    function networkLastLockBlock() external view returns (uint256);
    function networkRateLimit() external view returns (uint256);
    function lockReductionInterval() external view returns (uint256);
    function totalNetworks() external view returns (uint16);
    function nextNetuid() external view returns (uint16);
    
    // ============ Token and Factory References ============
    
    /**
     * @dev 获取HETU代币地址
     */
    function hetuToken() external view returns (address);
    
    /**
     * @dev 获取AMM工厂地址
     */
    function ammFactory() external view returns (address);
    
    // ============ Admin Functions (if needed) ============
    
    /**
     * @dev 更新网络参数（仅所有者）
     * @param newMinLock 新的最小锁定量
     * @param newRateLimit 新的速率限制
     * @param newReductionInterval 新的减少间隔
     */
    function updateNetworkParams(
        uint256 newMinLock,
        uint256 newRateLimit,
        uint256 newReductionInterval
    ) external;
    
    /**
     * @dev 紧急暂停子网（仅所有者）
     * @param netuid 子网ID
     */
    function pauseSubnet(uint16 netuid) external;
    
    /**
     * @dev 恢复子网（仅所有者）
     * @param netuid 子网ID
     */
    function resumeSubnet(uint16 netuid) external;
}
