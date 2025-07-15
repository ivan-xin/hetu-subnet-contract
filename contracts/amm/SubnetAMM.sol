// contracts/amm/SubnetAMM.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title SubnetAMM
 * @dev Automated Market Maker contract for HETU and Alpha tokens based on Subtensor mechanism
 * Liquidity can only be injected by the system, creator/owner cannot operate the pool
 */
contract SubnetAMM is ReentrancyGuard {
    using Math for uint256;
    
    // Mechanism type enumeration
    enum MechanismType { 
        Stable,   // 0: Stable mechanism, 1:1 exchange
        Dynamic   // 1: Dynamic mechanism, AMM exchange
    }
    
    // Token contracts
    IERC20 public immutable hetuToken;
    IERC20 public immutable alphaToken;
    uint16 public immutable netuid;
    
    // Mechanism settings (determined at deployment, cannot be changed)
    MechanismType public immutable mechanism;
    
    // Reserves (corresponding to Subtensor storage structure)
    uint256 public subnetTAO;        // Corresponds to SubnetTAO - HETU reserve in pool
    uint256 public subnetAlphaIn;    // Corresponds to SubnetAlphaIn - Alpha reserve in pool
    uint256 public subnetAlphaOut;   // Corresponds to SubnetAlphaOut - Alpha in circulation
    
    // Liquidity protection (set at deployment, cannot be changed)
    uint256 public immutable minimumPoolLiquidity;
    
    // Price tracking
    uint256 public currentAlphaPrice;     // Current Alpha price (HETU/Alpha)
    uint256 public movingAlphaPrice;      // Moving average price
    uint256 public priceUpdateBlock;      // Price update block
    
    // Moving average parameters (constants)
    uint256 public constant HALVING_TIME = 1000;  // Half-life period (blocks)
    
    // Statistics
    uint256 public totalVolume;           // Total trading volume
    mapping(address => uint256) public userVolume;  // User trading volume
    
    // System addresses (set at deployment, cannot be changed)
    address public immutable systemAddress;
    address public immutable subnetContract;
    
    // Creator address (for recording only, no special privileges)
    address public immutable creator;
    uint256 public immutable createdAt;
    
    // Events
    event SwapHETUForAlpha(
        address indexed user,
        uint256 hetuAmountIn,
        uint256 alphaAmountOut,
        uint256 newPrice
    );
    event SwapAlphaForHETU(
        address indexed user,
        uint256 alphaAmountIn,
        uint256 hetuAmountOut,
        uint256 newPrice
    );
    event LiquidityInjected(
        address indexed injector,
        uint256 hetuAmount,
        uint256 alphaAmount
    );
    event LiquidityWithdrawn(
        address indexed withdrawer,
        uint256 hetuAmount,
        uint256 alphaAmount
    );
    event PriceUpdated(uint256 currentPrice, uint256 movingPrice);
    event ReservesUpdated(uint256 subnetTAO, uint256 subnetAlphaIn, uint256 subnetAlphaOut);
    
    modifier onlySystem() {
        require(
            msg.sender == systemAddress || 
            msg.sender == subnetContract,
            "AMM: ONLY_SYSTEM"
        );
        _;
    }
    
    constructor(
        address _hetuToken,
        address _alphaToken,
        uint16 _netuid,
        address _systemAddress,
        address _subnetContract,
        MechanismType _mechanism,
        uint256 _minimumPoolLiquidity
    ) {
        require(_hetuToken != address(0), "AMM: ZERO_HETU_ADDRESS");
        require(_alphaToken != address(0), "AMM: ZERO_ALPHA_ADDRESS");
        require(_systemAddress != address(0), "AMM: ZERO_SYSTEM_ADDRESS");
        require(_subnetContract != address(0), "AMM: ZERO_SUBNET_ADDRESS");
        require(_minimumPoolLiquidity > 0, "AMM: ZERO_MIN_LIQUIDITY");
        
        hetuToken = IERC20(_hetuToken);
        alphaToken = IERC20(_alphaToken);
        netuid = _netuid;
        systemAddress = _systemAddress;
        subnetContract = _subnetContract;
        mechanism = _mechanism;
        minimumPoolLiquidity = _minimumPoolLiquidity;
        
        // Record creator information (for recording only)
        creator = msg.sender;
        createdAt = block.timestamp;
        priceUpdateBlock = block.number;
    }
    
    /**
     * @dev System injects liquidity
     * Only system address can call, creator has no permission
     */
    function injectLiquidity(
        uint256 hetuAmount,
        uint256 alphaAmount
    ) external onlySystem nonReentrant {
        require(hetuAmount > 0 || alphaAmount > 0, "AMM: ZERO_AMOUNTS");
        
        if (hetuAmount > 0) {
            hetuToken.transferFrom(msg.sender, address(this), hetuAmount);
            subnetTAO += hetuAmount;
        }
        
        if (alphaAmount > 0) {
            alphaToken.transferFrom(msg.sender, address(this), alphaAmount);
            subnetAlphaIn += alphaAmount;
        }
        
        _updatePrice();
        emit LiquidityInjected(msg.sender, hetuAmount, alphaAmount);
        emit ReservesUpdated(subnetTAO, subnetAlphaIn, subnetAlphaOut);
    }
    
    /**
     * @dev System withdraws liquidity
     * Only system address can call, creator has no permission
     */
    function withdrawLiquidity(
        uint256 hetuAmount,
        uint256 alphaAmount,
        address to
    ) external onlySystem nonReentrant {
        require(hetuAmount > 0 || alphaAmount > 0, "AMM: ZERO_AMOUNTS");
        require(to != address(0), "AMM: ZERO_ADDRESS");
        
        if (hetuAmount > 0) {
            require(hetuAmount <= subnetTAO, "AMM: INSUFFICIENT_HETU_RESERVE");
            require(subnetTAO - hetuAmount >= minimumPoolLiquidity, "AMM: BELOW_MIN_LIQUIDITY");
            
            hetuToken.transfer(to, hetuAmount);
            subnetTAO -= hetuAmount;
        }
        
        if (alphaAmount > 0) {
            require(alphaAmount <= subnetAlphaIn, "AMM: INSUFFICIENT_ALPHA_RESERVE");
            require(subnetAlphaIn - alphaAmount >= minimumPoolLiquidity, "AMM: BELOW_MIN_LIQUIDITY");
            
            alphaToken.transfer(to, alphaAmount);
            subnetAlphaIn -= alphaAmount;
        }
        
        _updatePrice();
        emit LiquidityWithdrawn(msg.sender, hetuAmount, alphaAmount);
        emit ReservesUpdated(subnetTAO, subnetAlphaIn, subnetAlphaOut);
    }
    
    /**
     * @dev Swap HETU for Alpha
     * Any user can call, including creator (but creator has no special privileges)
     */
    function swapHETUForAlpha(
        uint256 hetuAmountIn,
        uint256 alphaAmountOutMin,
        address to
    ) external nonReentrant returns (uint256 alphaAmountOut) {
        require(hetuAmountIn > 0, "AMM: INSUFFICIENT_INPUT_AMOUNT");
        require(to != address(0), "AMM: ZERO_ADDRESS");
        
        // Simulate swap check
        alphaAmountOut = simSwapHETUForAlpha(hetuAmountIn);
        require(alphaAmountOut > 0, "AMM: INSUFFICIENT_LIQUIDITY");
        require(alphaAmountOut >= alphaAmountOutMin, "AMM: INSUFFICIENT_OUTPUT_AMOUNT");
        
        // Execute swap
        hetuToken.transferFrom(msg.sender, address(this), hetuAmountIn);
        alphaToken.transfer(to, alphaAmountOut);
        
        // Update reserves
        subnetTAO += hetuAmountIn;
        subnetAlphaIn -= alphaAmountOut;
        subnetAlphaOut += alphaAmountOut;
        
        // Update statistics
        totalVolume += hetuAmountIn;
        userVolume[msg.sender] += hetuAmountIn;
        
        _updatePrice();
        
        emit SwapHETUForAlpha(msg.sender, hetuAmountIn, alphaAmountOut, currentAlphaPrice);
        emit ReservesUpdated(subnetTAO, subnetAlphaIn, subnetAlphaOut);
    }
    
    /**
     * @dev Swap Alpha for HETU
     * Any user can call, including creator (but creator has no special privileges)
     */
    function swapAlphaForHETU(
        uint256 alphaAmountIn,
        uint256 hetuAmountOutMin,
        address to
    ) external nonReentrant returns (uint256 hetuAmountOut) {
        require(alphaAmountIn > 0, "AMM: INSUFFICIENT_INPUT_AMOUNT");
        require(to != address(0), "AMM: ZERO_ADDRESS");
        
        // Simulate swap check
        hetuAmountOut = simSwapAlphaForHETU(alphaAmountIn);
        require(hetuAmountOut > 0, "AMM: INSUFFICIENT_LIQUIDITY");
        require(hetuAmountOut >= hetuAmountOutMin, "AMM: INSUFFICIENT_OUTPUT_AMOUNT");
        
        // Execute swap
        alphaToken.transferFrom(msg.sender, address(this), alphaAmountIn);
        hetuToken.transfer(to, hetuAmountOut);
        
        // Update reserves
        subnetAlphaIn += alphaAmountIn;
        subnetAlphaOut -= alphaAmountIn;
        subnetTAO -= hetuAmountOut;
        
        // Update statistics
        uint256 hetuValue = _convertToHETUValue(alphaAmountIn);
        totalVolume += hetuValue;
        userVolume[msg.sender] += hetuValue;
        
        _updatePrice();
        
        emit SwapAlphaForHETU(msg.sender, alphaAmountIn, hetuAmountOut, currentAlphaPrice);
        emit ReservesUpdated(subnetTAO, subnetAlphaIn, subnetAlphaOut);
    }
    
    /**
     * @dev Simulate HETU to Alpha swap
     */
    function simSwapHETUForAlpha(uint256 hetuAmount) public view returns (uint256 alphaAmount) {
        if (mechanism == MechanismType.Stable) {
            // Stable mechanism: 1:1 exchange
            alphaAmount = hetuAmount;
        } else {
            // Dynamic mechanism: AMM calculation
            if (subnetTAO == 0 || subnetAlphaIn == 0) {
                return 0;
            }
            
            // Constant product formula: k = subnetTAO * subnetAlphaIn
            uint256 k = subnetTAO * subnetAlphaIn;
            uint256 newSubnetTAO = subnetTAO + hetuAmount;
            uint256 newSubnetAlphaIn = k / newSubnetTAO;
            
            // Check liquidity protection
            if (newSubnetAlphaIn < minimumPoolLiquidity) {
                return 0;
            }
            
            alphaAmount = subnetAlphaIn - newSubnetAlphaIn;
        }
        
        // Final check
        if (alphaAmount > subnetAlphaIn || subnetAlphaIn - alphaAmount < minimumPoolLiquidity) {
            return 0;
        }
    }
    
    /**
     * @dev Simulate Alpha to HETU swap
     */
    function simSwapAlphaForHETU(uint256 alphaAmount) public view returns (uint256 hetuAmount) {
        if (mechanism == MechanismType.Stable) {
            // Stable mechanism: 1:1 exchange
            hetuAmount = alphaAmount;
        } else {
            // Dynamic mechanism: AMM calculation
            if (subnetTAO == 0 || subnetAlphaIn == 0) {
                return 0;
            }
            
            // Constant product formula: k = subnetTAO * subnetAlphaIn
            uint256 k = subnetTAO * subnetAlphaIn;
            uint256 newSubnetAlphaIn = subnetAlphaIn + alphaAmount;
            uint256 newSubnetTAO = k / newSubnetAlphaIn;
            
            // Check liquidity protection
            if (newSubnetTAO < minimumPoolLiquidity) {
                return 0;
            }
            
            hetuAmount = subnetTAO - newSubnetTAO;
        }
        
        // Final check
        if (hetuAmount > subnetTAO || subnetTAO - hetuAmount < minimumPoolLiquidity) {
            return 0;
        }
    }
    
    /**
     * @dev Get current Alpha price
     */
    function getAlphaPrice() public view returns (uint256 price) {
        if (subnetAlphaIn == 0) {
            return 0;
        }
        return (subnetTAO * 1e18) / subnetAlphaIn;
    }
    
    /**
     * @dev Get moving average price
     */
    function getMovingAlphaPrice() public view returns (uint256) {
        return movingAlphaPrice;
    }
    
    /**
     * @dev Update moving average price
     * Anyone can call to update the price
     */
    function updateMovingPrice() external {
        _updatePrice();
    }
    
    /**
     * @dev Internal price update function
     */
    function _updatePrice() internal {
        uint256 blocksSinceUpdate = block.number - priceUpdateBlock;
        if (blocksSinceUpdate == 0) return;
        
        // Calculate current price
        currentAlphaPrice = getAlphaPrice();
        
        if (movingAlphaPrice == 0) {
            // First time setup
            movingAlphaPrice = currentAlphaPrice;
        } else {
            // Calculate exponential moving average
            uint256 alpha = (blocksSinceUpdate * 1e18) / (blocksSinceUpdate + HALVING_TIME);
            uint256 oneMinusAlpha = 1e18 - alpha;
            
            // Cap current price at 1.0
            uint256 cappedCurrentPrice = currentAlphaPrice > 1e18 ? 1e18 : currentAlphaPrice;
            
            // Update moving average price
            movingAlphaPrice = (alpha * cappedCurrentPrice + oneMinusAlpha * movingAlphaPrice) / 1e18;
        }
        
        priceUpdateBlock = block.number;
        emit PriceUpdated(currentAlphaPrice, movingAlphaPrice);
    }
    
    /**
     * @dev Convert Alpha amount to HETU value
     */
    function _convertToHETUValue(uint256 alphaAmount) internal view returns (uint256) {
        if (currentAlphaPrice == 0) return alphaAmount;
        return (alphaAmount * currentAlphaPrice) / 1e18;
    }
    
    /**
     * @dev Get pool detailed information
     */
    function getPoolInfo() external view returns (
        MechanismType _mechanism,
        uint256 _subnetTAO,
        uint256 _subnetAlphaIn,
        uint256 _subnetAlphaOut,
        uint256 _currentPrice,
        uint256 _movingPrice,
        uint256 _totalVolume,
        uint256 _minimumLiquidity
    ) {
        return (
            mechanism,
            subnetTAO,
            subnetAlphaIn,
            subnetAlphaOut,
            currentAlphaPrice,
            movingAlphaPrice,
            totalVolume,
            minimumPoolLiquidity
        );
    }
    
    /**
     * @dev Get creator information (for record only)
     */
    function getCreatorInfo() external view returns (
        address _creator,
        uint256 _createdAt,
        uint256 _netuid
    ) {
        return (creator, createdAt, netuid);
    }
    
    /**
     * @dev Get system address information
     */
    function getSystemInfo() external view returns (
        address _systemAddress,
        address _subnetContract
    ) {
        return (systemAddress, subnetContract);
    }
    
    /**
     * @dev Get swap preview
     */
    function getSwapPreview(
        uint256 amountIn,
        bool isHETUToAlpha
    ) external view returns (
        uint256 amountOut,
        uint256 priceImpact,
        uint256 newPrice,
        bool isLiquiditySufficient
    ) {
        if (isHETUToAlpha) {
            amountOut = simSwapHETUForAlpha(amountIn);
            isLiquiditySufficient = amountOut > 0;
            
            if (mechanism == MechanismType.Dynamic && subnetAlphaIn > 0) {
                // Calculate price impact
                uint256 oldPrice = getAlphaPrice();
                uint256 newSubnetTAO = subnetTAO + amountIn;
                uint256 newSubnetAlphaIn = subnetAlphaIn - amountOut;
                newPrice = newSubnetAlphaIn > 0 ? (newSubnetTAO * 1e18) / newSubnetAlphaIn : 0;
                
                if (oldPrice > 0) {
                    priceImpact = newPrice > oldPrice ? 
                        ((newPrice - oldPrice) * 10000) / oldPrice : 0;
                }
            } else {
                newPrice = currentAlphaPrice;
                priceImpact = 0;
            }
        } else {
            amountOut = simSwapAlphaForHETU(amountIn);
            isLiquiditySufficient = amountOut > 0;
            
            if (mechanism == MechanismType.Dynamic && subnetAlphaIn > 0) {
                // Calculate price impact
                uint256 oldPrice = getAlphaPrice();
                uint256 newSubnetTAO = subnetTAO - amountOut;
                uint256 newSubnetAlphaIn = subnetAlphaIn + amountIn;
                newPrice = (newSubnetTAO * 1e18) / newSubnetAlphaIn;
                
                if (oldPrice > 0) {
                    priceImpact = oldPrice > newPrice ? 
                        ((oldPrice - newPrice) * 10000) / oldPrice : 0;
                }
            } else {
                newPrice = currentAlphaPrice;
                priceImpact = 0;
            }
        }
    }
    
    /**
     * @dev Check large trade warning
     */
    function checkLargeTradeWarning(
        uint256 amountIn,
        bool isHETUToAlpha
    ) external view returns (
        bool isLargeTrade,
        uint256 percentageOfPool,
        string memory warning
    ) {
        uint256 reserveIn = isHETUToAlpha ? subnetTAO : subnetAlphaIn;
        
        if (reserveIn == 0) {
            return (true, 0, "No liquidity available");
        }
        
        // Calculate trade percentage of pool
        percentageOfPool = (amountIn * 10000) / reserveIn;
        
        if (percentageOfPool >= 2000) { // 20%
            isLargeTrade = true;
            warning = "Very large trade: Extreme price impact expected";
        } else if (percentageOfPool >= 1000) { // 10%
            isLargeTrade = true;
            warning = "Large trade: High price impact expected";
        } else if (percentageOfPool >= 500) { // 5%
            isLargeTrade = true;
            warning = "Medium trade: Moderate price impact expected";
        } else {
            isLargeTrade = false;
            warning = "Normal trade: Low price impact expected";
        }
    }
    
    /**
     * @dev Get constant product K value
     */
    function getK() external view returns (uint256) {
        return subnetTAO * subnetAlphaIn;
    }
    
    /**
     * @dev Check pool health status
     */
    function getPoolHealth() external view returns (
        bool isHealthy,
        string memory status,
        uint256 liquidityRatio
    ) {
        if (subnetTAO == 0 || subnetAlphaIn == 0) {
            return (false, "No liquidity", 0);
        }
        
        uint256 minLiquidity = minimumPoolLiquidity;
        
        if (subnetTAO < minLiquidity || subnetAlphaIn < minLiquidity) {
            liquidityRatio = subnetTAO < subnetAlphaIn ? 
                (subnetTAO * 100) / minLiquidity : 
                (subnetAlphaIn * 100) / minLiquidity;
            return (false, "Low liquidity", liquidityRatio);
        }
        
        liquidityRatio = 100; // Healthy status
        return (true, "Healthy", liquidityRatio);
    }
    
    /**
     * @dev Get historical statistics
     */
    function getStatistics() external view returns (
        uint256 _totalVolume,
        uint256 _currentPrice,
        uint256 _movingPrice,
        uint256 _priceUpdateBlock,
        uint256 _totalLiquidity
    ) {
        return (
            totalVolume,
            currentAlphaPrice,
            movingAlphaPrice,
            priceUpdateBlock,
            subnetTAO + _convertToHETUValue(subnetAlphaIn)
        );
    }
    
    /**
     * @dev Get user trading statistics
     */
    function getUserStats(address user) external view returns (
        uint256 _userVolume,
        uint256 _userVolumePercentage
    ) {
        _userVolume = userVolume[user];
        _userVolumePercentage = totalVolume > 0 ? (_userVolume * 10000) / totalVolume : 0;
    }
    
    /**
     * @dev Check if address is system address
     */
    function isSystemAddress(address addr) external view returns (bool) {
        return addr == systemAddress || addr == subnetContract;
    }
    
    /**
     * @dev Check if address is creator (for query only, no special privileges)
     */
    function isCreator(address addr) external view returns (bool) {
        return addr == creator;
    }
    
    /**
     * @dev Get token balances
     */
    function getTokenBalances() external view returns (
        uint256 hetuBalance,
        uint256 alphaBalance
    ) {
        hetuBalance = hetuToken.balanceOf(address(this));
        alphaBalance = alphaToken.balanceOf(address(this));
    }
    
    /**
     * @dev Verify reserve consistency
     */
    function verifyReserves() external view returns (
        bool isConsistent,
        string memory message
    ) {
        uint256 actualHETU = hetuToken.balanceOf(address(this));
        uint256 actualAlpha = alphaToken.balanceOf(address(this));
        
        if (actualHETU != subnetTAO) {
            return (false, "HETU reserve mismatch");
        }
        
        if (actualAlpha != subnetAlphaIn) {
            return (false, "Alpha reserve mismatch");
        }
        
        return (true, "Reserves are consistent");
    }
    
    /**
     * @dev Calculate theoretical price (without slippage)
     */
    function getTheoreticalPrice() external view returns (uint256) {
        if (subnetAlphaIn == 0) return 0;
        return (subnetTAO * 1e18) / subnetAlphaIn;
    }
    
    /**
     * @dev Calculate slippage
     */
    function calculateSlippage(
        uint256 amountIn,
        bool isHETUToAlpha
    ) external view returns (uint256 slippageRate) {
        if (mechanism == MechanismType.Stable) {
            return 0; // No slippage for stable mechanism
        }
        
        uint256 theoreticalOut;
        uint256 actualOut;
        
        if (isHETUToAlpha) {
            theoreticalOut = (amountIn * subnetAlphaIn) / subnetTAO;
            actualOut = simSwapHETUForAlpha(amountIn);
        } else {
            theoreticalOut = (amountIn * subnetTAO) / subnetAlphaIn;
            actualOut = simSwapAlphaForHETU(amountIn);
        }
        
        if (theoreticalOut > actualOut && theoreticalOut > 0) {
            slippageRate = ((theoreticalOut - actualOut) * 10000) / theoreticalOut;
        }
    }
}
