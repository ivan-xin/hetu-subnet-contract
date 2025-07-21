// contracts/subnet/SubnetManagerSimplified.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "../tokens/AlphaToken.sol";
import "../amm/SubnetAMM.sol";
import "../factory/SubnetAMMFactory.sol";
import "../interfaces/ISubnetManager.sol";
import "../interfaces/ISubnetTypes.sol";
import "./DefaultHyperparams.sol";

/**
 * @title SubnetManager
 * @dev Subnet Manager
 */
contract SubnetManager is ReentrancyGuard, Ownable, ISubnetManager {
    using DefaultHyperparams for SubnetTypes.SubnetHyperparams;

    IERC20 public immutable  hetuToken;
    SubnetAMMFactory public immutable ammFactory;
    
    mapping(uint16 => SubnetTypes.SubnetInfo) public subnets;
    mapping(uint16 => SubnetTypes.SubnetHyperparams) public subnetHyperparams;
    mapping(uint16 => bool) public subnetExists;
    mapping(address => uint16[]) public ownerSubnets; // A user can own multiple subnets
    
    uint16 public totalNetworks;
    uint16 public nextNetuid = 1;
    
    // Network parameters
    uint256 public networkMinLock = 100 * 1e18;
    uint256 public networkLastLock;
    uint256 public networkLastLockBlock;
    uint256 public networkRateLimit = 1000;
    uint256 public lockReductionInterval = 10000;
    
    
    constructor(address _hetuToken, address _ammFactory)Ownable(msg.sender) {
        require(_hetuToken != address(0), "ZERO_HETU_ADDRESS");
        require(_ammFactory != address(0), "ZERO_FACTORY_ADDRESS");
        
        hetuToken = IERC20(_hetuToken);
        ammFactory = SubnetAMMFactory(_ammFactory);
        networkLastLockBlock = block.number;
    }
    
    /**
     * @dev Register new subnet - Simplified version
     */
    function registerNetwork(
        string calldata name,
        string calldata description,
        string calldata tokenName,
        string calldata tokenSymbol
    ) external nonReentrant returns (uint16 netuid) {
        SubnetTypes.SubnetHyperparams memory defaultParams = DefaultHyperparams.getDefaultHyperparams();
        return _registerNetworkWithHyperparams(
            name,
            description,
            tokenName,
            tokenSymbol,
            defaultParams
        );
    }
    
    /**
     * @dev Register subnet with partial custom hyperparameters (rest use default values)
     */
    function registerNetworkWithPartialCustom(
        string calldata name,
        string calldata description,
        string calldata tokenName,
        string calldata tokenSymbol,
        SubnetTypes.SubnetHyperparams calldata customHyperparams,
        bool[21] calldata useCustomFlags
    ) external nonReentrant returns (uint16 netuid) {
        // Merge custom parameters with defaults
        SubnetTypes.SubnetHyperparams memory mergedParams = DefaultHyperparams.mergeWithDefaults(
            customHyperparams,
            useCustomFlags
        );
        
        // Validate merged hyperparameters
        require(DefaultHyperparams.validateHyperparams(mergedParams), "INVALID_MERGED_HYPERPARAMS");
        
        return _registerNetworkWithHyperparams(
            name,
            description,
            tokenName,
            tokenSymbol,
            mergedParams
        );
    }
    
    /**
     * @dev Register new subnet with permit authorization in single transaction
     */
    function registerNetworkWithPermit(
        string calldata name,
        string calldata description,
        string calldata tokenName,
        string calldata tokenSymbol,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant returns (uint16 netuid) {
        uint256 lockAmount = getNetworkLockCost();
        
        // Use permit for authorization
        IERC20Permit(address(hetuToken)).permit(
            msg.sender,
            address(this),
            lockAmount,
            deadline,
            v, r, s
        );
        
        // Execute normal registration flow
        SubnetTypes.SubnetHyperparams memory defaultParams = DefaultHyperparams.getDefaultHyperparams();
        return _registerNetworkWithHyperparams(
            name,
            description,
            tokenName,
            tokenSymbol,
            defaultParams
        );
    }

    /**
     * @dev Register subnet with partial custom hyperparameters and permit authorization
     */
    function registerNetworkWithPartialCustomAndPermit(
        string calldata name,
        string calldata description,
        string calldata tokenName,
        string calldata tokenSymbol,
        SubnetTypes.SubnetHyperparams calldata customHyperparams,
        bool[21] calldata useCustomFlags,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant returns (uint16 netuid) {
        uint256 lockAmount = getNetworkLockCost();
        
        // Use permit for authorization
        IERC20Permit(address(hetuToken)).permit(
            msg.sender,
            address(this),
            lockAmount,
            deadline,
            v, r, s
        );
        
        // Merge custom parameters with defaults
        SubnetTypes.SubnetHyperparams memory mergedParams = DefaultHyperparams.mergeWithDefaults(
            customHyperparams,
            useCustomFlags
        );
        
        // Validate merged hyperparameters
        require(DefaultHyperparams.validateHyperparams(mergedParams), "INVALID_MERGED_HYPERPARAMS");
        
        return _registerNetworkWithHyperparams(
            name,
            description,
            tokenName,
            tokenSymbol,
            mergedParams
        );
    }
    /**
     * @dev Internal network registration function
     */
    function _registerNetworkWithHyperparams(
        string calldata name,
        string calldata description,
        string calldata tokenName,
        string calldata tokenSymbol,
        SubnetTypes.SubnetHyperparams memory hyperparams
    ) internal returns (uint16 netuid) {
        address owner = msg.sender;
        
        // Basic validation
        require(bytes(name).length > 0, "EMPTY_NAME");
        require(bytes(tokenName).length > 0, "EMPTY_TOKEN_NAME");
        require(bytes(tokenSymbol).length > 0, "EMPTY_TOKEN_SYMBOL");
        
        // Rate limit
        require(
            block.number - networkLastLockBlock >= networkRateLimit,
            "RATE_LIMIT_EXCEEDED"
        );
        
        // Calculate and lock cost
        uint256 lockAmount = getNetworkLockCost();
        hetuToken.transferFrom(owner, address(this), lockAmount);
        
        // Get netuid
        netuid = getNextNetuid();
        
        // Calculate pool funds
        uint256 poolInitialTao = networkMinLock;
        uint256 burnedAmount = lockAmount > poolInitialTao ? lockAmount - poolInitialTao : 0;
        
        // Create Alpha token and AMM pool
        address alphaTokenAddress = _createAlphaToken(netuid, tokenName, tokenSymbol);
        address ammPoolAddress = _createAMMPool(netuid, alphaTokenAddress, poolInitialTao);
        
        // Burn excess tokens
        if (burnedAmount > 0) {
            _burnTokens(burnedAmount);
        }
        
        // Record subnet information
        subnets[netuid] = SubnetTypes.SubnetInfo({
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
        
        // Set subnet hyperparameters
        subnetHyperparams[netuid] = hyperparams;
        
        subnetExists[netuid] = true;
        ownerSubnets[owner].push(netuid);
        totalNetworks++;
        
        // Update parameters
        networkLastLock = lockAmount;
        networkLastLockBlock = block.number;
        
        emit NetworkRegistered(
            netuid, owner, alphaTokenAddress, ammPoolAddress,
            lockAmount, poolInitialTao, burnedAmount, name,hyperparams
        );
        
        return netuid;
    }
    
        /**
     * @dev Activate subnet (subnet owner only)
     */
    function activateSubnet(uint16 netuid) external nonReentrant {
        require(subnetExists[netuid], "SUBNET_NOT_EXISTS");
        require(subnets[netuid].owner == msg.sender, "NOT_OWNER");
        require(!subnets[netuid].isActive, "SUBNET_ALREADY_ACTIVE");
        
        // Activate subnet
        subnets[netuid].isActive = true;
        
        // Emit activation event
        emit SubnetActivated(
            netuid,
            msg.sender,
            block.timestamp,
            block.number
        );
    }
    

    /**
     * @dev Transfer subnet ownership
     */
    // function transferSubnetOwnership(uint16 netuid, address newOwner) external {
    //     require(subnetExists[netuid], "SUBNET_NOT_EXISTS");
    //     require(subnets[netuid].owner == msg.sender, "NOT_OWNER");
    //     require(newOwner != address(0), "ZERO_ADDRESS");
    //     require(newOwner != msg.sender, "SAME_OWNER");
        
    //     address oldOwner = subnets[netuid].owner;
    //     subnets[netuid].owner = newOwner;
        
    //     // Update ownership mapping
    //     _removeFromOwnerSubnets(oldOwner, netuid);
    //     ownerSubnets[newOwner].push(netuid);
        
    //     emit SubnetOwnershipTransferred(netuid, oldOwner, newOwner);
    // }
    
    /**
     * @dev Update subnet information
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
     * @dev Get subnet hyperparameters
     */
    function getSubnetHyperparams(uint16 netuid) external view returns (SubnetTypes.SubnetHyperparams memory) {
        require(subnetExists[netuid], "SUBNET_NOT_EXISTS");
        return subnetHyperparams[netuid];
    }

    /**
     * @dev Get all subnets owned by user
     */
    function getUserSubnets(address user) external view returns (uint16[] memory) {
        return ownerSubnets[user];
    }
    
    /**
     * @dev Get subnet info struct
     */
    function getSubnetInfo(uint16 netuid) external view override returns (SubnetTypes.SubnetInfo memory) {
        require(subnetExists[netuid], "SUBNET_NOT_EXISTS");
        return subnets[netuid];
    }
    
    /**
     * @dev Get subnet hyperparameters
     */
    function getSubnetParams(uint16 netuid) external view override returns (SubnetTypes.SubnetHyperparams memory) {
        require(subnetExists[netuid], "SUBNET_NOT_EXISTS");
        return subnetHyperparams[netuid];
    }

    /**
     * @dev Get subnet detailed information
     */
    function getSubnetDetails(uint16 netuid) external view returns (
        SubnetTypes.SubnetInfo memory subnetInfo,
        uint256 currentPrice,
        uint256 totalVolume,
        uint256 hetuReserve,
        uint256 alphaReserve
    ) {
        require(subnetExists[netuid], "SUBNET_NOT_EXISTS");
        
        subnetInfo = subnets[netuid];
        
        // Get AMM pool information
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
    
    // Internal functions remain unchanged...
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
        uint16[] storage userSubnets = ownerSubnets[owner];
        for (uint256 i = 0; i < userSubnets.length; i++) {
            if (userSubnets[i] == netuid) {
                userSubnets[i] = userSubnets[userSubnets.length - 1];
                userSubnets.pop();
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

    // Add the following functions in SubnetManager contract

    /**
     * @dev Update network parameters (owner only, for testing phase)
     * @param _networkMinLock New minimum lock amount
     * @param _networkRateLimit New rate limit
     * @param _lockReductionInterval New lock reduction interval
     */
    function updateNetworkParams(
        uint256 _networkMinLock,
        uint256 _networkRateLimit,
        uint256 _lockReductionInterval
    ) external onlyOwner {
        require(_networkMinLock > 0, "MIN_LOCK_ZERO");
        require(_networkRateLimit > 0, "RATE_LIMIT_ZERO");
        require(_lockReductionInterval > 0, "REDUCTION_INTERVAL_ZERO");
        
        networkMinLock = _networkMinLock;
        networkRateLimit = _networkRateLimit;
        lockReductionInterval = _lockReductionInterval;
    }

    /**
     * @dev Reset network lock state (owner only, for testing phase)
     */
    function resetNetworkLockState() external onlyOwner {
        networkLastLock = 0;
        networkLastLockBlock = block.number;
    }

    /**
     * @dev Get current network parameters
     */
    function getNetworkParams() external view returns (
        uint256 minLock,
        uint256 lastLock,
        uint256 lastLockBlock,
        uint256 rateLimit,
        uint256 reductionInterval,
        uint16 totalNets,
        uint16 nextId
    ) {
        return (
            networkMinLock,
            networkLastLock,
            networkLastLockBlock,
            networkRateLimit,
            lockReductionInterval,
            totalNetworks,
            nextNetuid
        );
    }

    /**
     * @dev Update subnet hyperparameters (owner only, for testing purposes)
     * @param netuid Subnet ID
     * @param newHyperparams New hyperparameters
     */
    function updateSubnetHyperparams(
        uint16 netuid,
        SubnetTypes.SubnetHyperparams calldata newHyperparams
    ) external onlyOwner {
        require(subnetExists[netuid], "SUBNET_NOT_EXISTS");
        require(DefaultHyperparams.validateHyperparams(newHyperparams), "INVALID_HYPERPARAMS");
        
        // Update hyperparameters
        subnetHyperparams[netuid] = newHyperparams;
        
    }

}
