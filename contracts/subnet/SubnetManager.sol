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
    address public immutable systemAddress;

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
    uint256 public lockReductionInterval = 14400; // 14400 blocks (approx. 1 day)
    
    
    constructor(address _hetuToken, address _systemAddress)Ownable(msg.sender) {
        require(_hetuToken != address(0), "ZERO_HETU_ADDRESS");
        require(_systemAddress != address(0), "ZERO_SYSTEM_ADDRESS");
        ammFactory = new SubnetAMMFactory(_systemAddress);
        systemAddress = _systemAddress;
        
        hetuToken = IERC20(_hetuToken);
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
        uint256 currentBlock = block.number;
        uint256 lastBlock = networkLastLockBlock;

        // Basic validation
        require(bytes(name).length > 0, "EMPTY_NAME");
        require(bytes(tokenName).length > 0, "EMPTY_TOKEN_NAME");
        require(bytes(tokenSymbol).length > 0, "EMPTY_TOKEN_SYMBOL");
        
        // Rate limit
        require(
            currentBlock > lastBlock + networkRateLimit,
            "RATE_LIMIT_EXCEEDED"
        );
        
        // Calculate and lock cost
        uint256 lockAmount = _getExactLockCost(currentBlock);
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
            isActive: false,
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

    function _getExactLockCost(uint256 atBlock) internal view returns (uint256) {
        // Calculates exact lock cost based on specified block
        uint256 lastLock = networkLastLock;
        uint256 minLock = networkMinLock;
        uint256 lastLockBlock = networkLastLockBlock;
        
        if (lastLockBlock == 0) {
            return minLock;
        }
        
        uint256 mult = 2;
        uint256 lockCost = lastLock * mult;
        
        if (atBlock > lastLockBlock && lockReductionInterval > 0) {
            uint256 blocksPassed = atBlock - lastLockBlock;
            uint256 reduction = (lastLock * blocksPassed) / lockReductionInterval;
            lockCost = lockCost > reduction ? lockCost - reduction : minLock;
        }
        
        return lockCost < minLock ? minLock : lockCost;
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
     * @dev Check if subnet active
     * @param netuid Subnet ID
     * @return isActive True if subnet is active
     */
    function isSubnetActive(uint16 netuid) external view returns (bool) {
        require(subnetExists[netuid], "SUBNET_NOT_EXISTS");
        return subnets[netuid].isActive;
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
            uint256 _subnetHetu,
            uint256 _subnetAlphaIn,
            ,
            uint256 _currentPrice,
            ,
            uint256 _totalVolume,
        ) = pool.getPoolInfo();
        
        currentPrice = _currentPrice;
        totalVolume = _totalVolume;
        hetuReserve = _subnetHetu;
        alphaReserve = _subnetAlphaIn;
    }
    
    // Internal functions remain unchanged...
    function _createAlphaToken(uint16 netuid, string calldata name, string calldata symbol) internal returns (address) {
        AlphaToken alphaToken = new AlphaToken(name, symbol, address(this), netuid, systemAddress);
        uint256 initialAlphaAmount = networkMinLock;
        alphaToken.mint(address(this), initialAlphaAmount);
        return address(alphaToken);
    }

    function addSubnetMinter(uint16 netuid, address minter) external {
        require(subnetExists[netuid], "SUBNET_NOT_EXISTS");
        require(subnets[netuid].owner == msg.sender, "NOT_SUBNET_OWNER");
        require(minter != address(0), "ZERO_MINTER_ADDRESS");
        require(minter != address(this), "CANNOT_ADD_SELF");
        
        AlphaToken alphaToken = AlphaToken(subnets[netuid].alphaToken);
        alphaToken.addMinter(minter);
    }

    function removeSubnetMinter(uint16 netuid, address minter) external {
        require(subnetExists[netuid], "SUBNET_NOT_EXISTS");
        require(subnets[netuid].owner == msg.sender, "NOT_SUBNET_OWNER");
        require(minter != address(0), "ZERO_MINTER_ADDRESS");
        
        AlphaToken alphaToken = AlphaToken(subnets[netuid].alphaToken);
        alphaToken.removeMinter(minter);
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
     * @dev Batch update network configuration (atomic operation)
     * @param newMinLock New minimum lock amount
     * @param newRateLimit New rate limit
     * @param newInterval New reduction interval
     */
    function updateNetworkConfig(
        uint256 newMinLock,
        uint256 newRateLimit,
        uint256 newInterval
    ) external onlyOwner {
        // Verify all parameters
        require(newMinLock > 0 && newMinLock >= 1e18 && newMinLock <= 10000 * 1e18, "INVALID_MIN_LOCK");
        require(newRateLimit >= 100 && newRateLimit <= 50000, "INVALID_RATE_LIMIT");
        require(newInterval >= 1000 && newInterval <= 100000, "INVALID_INTERVAL");
        
        // Save old values
        uint256 oldMinLock = networkMinLock;
        uint256 oldRateLimit = networkRateLimit;
        uint256 oldInterval = lockReductionInterval;

        // Update all values
        networkMinLock = newMinLock;
        networkRateLimit = newRateLimit;
        lockReductionInterval = newInterval;

        // Emit events
        emit NetworkConfigUpdated("networkMinLock", oldMinLock, newMinLock, msg.sender);
        emit NetworkConfigUpdated("networkRateLimit", oldRateLimit, newRateLimit, msg.sender);
        emit NetworkConfigUpdated("lockReductionInterval", oldInterval, newInterval, msg.sender);
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
