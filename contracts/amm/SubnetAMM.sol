// contracts/amm/SubnetAMM.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title SubnetAMM
 * @dev 基于Subtensor机制的HETU和Alpha代币自动做市商合约
 * 流动性只能由系统注入，创建者/所有者无法操作池子
 */
contract SubnetAMM is ReentrancyGuard {
    using Math for uint256;
    
    // 机制类型枚举
    enum MechanismType { 
        Stable,   // 0: 稳定机制，1:1兑换
        Dynamic   // 1: 动态机制，AMM兑换
    }
    
    // 代币合约
    IERC20 public immutable hetuToken;
    IERC20 public immutable alphaToken;
    uint16 public immutable netuid;
    
    // 机制设置（部署时确定，不可更改）
    MechanismType public immutable mechanism;
    
    // 储备量 (对应Subtensor的存储结构)
    uint256 public subnetTAO;        // 对应SubnetTAO - 池中HETU储备
    uint256 public subnetAlphaIn;    // 对应SubnetAlphaIn - 池中Alpha储备
    uint256 public subnetAlphaOut;   // 对应SubnetAlphaOut - 流通中的Alpha
    
    // 流动性保护（部署时设定，不可更改）
    uint256 public immutable minimumPoolLiquidity;
    
    // 价格追踪
    uint256 public currentAlphaPrice;     // 当前Alpha价格 (HETU/Alpha)
    uint256 public movingAlphaPrice;      // 移动平均价格
    uint256 public priceUpdateBlock;      // 价格更新区块
    
    // 移动平均参数（常量）
    uint256 public constant HALVING_TIME = 1000;  // 半衰期(区块数)
    
    // 统计数据
    uint256 public totalVolume;           // 总交易量
    mapping(address => uint256) public userVolume;  // 用户交易量
    
    // 系统地址（部署时设定，不可更改）
    address public immutable systemAddress;
    address public immutable subnetContract;
    
    // 创建者地址（仅用于记录，无特殊权限）
    address public immutable creator;
    uint256 public immutable createdAt;
    
    // 事件
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
        
        // 记录创建者信息（仅用于记录）
        creator = msg.sender;
        createdAt = block.timestamp;
        priceUpdateBlock = block.number;
    }
    
    /**
     * @dev 系统注入流动性
     * 只有系统地址可以调用，创建者无权限
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
     * @dev 系统提取流动性
     * 只有系统地址可以调用，创建者无权限
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
     * @dev HETU换Alpha
     * 任何用户都可以调用，包括创建者（但创建者没有特殊权限）
     */
    function swapHETUForAlpha(
        uint256 hetuAmountIn,
        uint256 alphaAmountOutMin,
        address to
    ) external nonReentrant returns (uint256 alphaAmountOut) {
        require(hetuAmountIn > 0, "AMM: INSUFFICIENT_INPUT_AMOUNT");
        require(to != address(0), "AMM: ZERO_ADDRESS");
        
        // 模拟兑换检查
        alphaAmountOut = simSwapHETUForAlpha(hetuAmountIn);
        require(alphaAmountOut > 0, "AMM: INSUFFICIENT_LIQUIDITY");
        require(alphaAmountOut >= alphaAmountOutMin, "AMM: INSUFFICIENT_OUTPUT_AMOUNT");
        
        // 执行兑换
        hetuToken.transferFrom(msg.sender, address(this), hetuAmountIn);
        alphaToken.transfer(to, alphaAmountOut);
        
        // 更新储备量
        subnetTAO += hetuAmountIn;
        subnetAlphaIn -= alphaAmountOut;
        subnetAlphaOut += alphaAmountOut;
        
        // 更新统计
        totalVolume += hetuAmountIn;
        userVolume[msg.sender] += hetuAmountIn;
        
        _updatePrice();
        
        emit SwapHETUForAlpha(msg.sender, hetuAmountIn, alphaAmountOut, currentAlphaPrice);
        emit ReservesUpdated(subnetTAO, subnetAlphaIn, subnetAlphaOut);
    }
    
    /**
     * @dev Alpha换HETU
     * 任何用户都可以调用，包括创建者（但创建者没有特殊权限）
     */
    function swapAlphaForHETU(
        uint256 alphaAmountIn,
        uint256 hetuAmountOutMin,
        address to
    ) external nonReentrant returns (uint256 hetuAmountOut) {
        require(alphaAmountIn > 0, "AMM: INSUFFICIENT_INPUT_AMOUNT");
        require(to != address(0), "AMM: ZERO_ADDRESS");
        
        // 模拟兑换检查
        hetuAmountOut = simSwapAlphaForHETU(alphaAmountIn);
        require(hetuAmountOut > 0, "AMM: INSUFFICIENT_LIQUIDITY");
        require(hetuAmountOut >= hetuAmountOutMin, "AMM: INSUFFICIENT_OUTPUT_AMOUNT");
        
        // 执行兑换
        alphaToken.transferFrom(msg.sender, address(this), alphaAmountIn);
        hetuToken.transfer(to, hetuAmountOut);
        
        // 更新储备量
        subnetAlphaIn += alphaAmountIn;
        subnetAlphaOut -= alphaAmountIn;
        subnetTAO -= hetuAmountOut;
        
        // 更新统计
        uint256 hetuValue = _convertToHETUValue(alphaAmountIn);
        totalVolume += hetuValue;
        userVolume[msg.sender] += hetuValue;
        
        _updatePrice();
        
        emit SwapAlphaForHETU(msg.sender, alphaAmountIn, hetuAmountOut, currentAlphaPrice);
        emit ReservesUpdated(subnetTAO, subnetAlphaIn, subnetAlphaOut);
    }
    
    /**
     * @dev 模拟HETU换Alpha
     */
    function simSwapHETUForAlpha(uint256 hetuAmount) public view returns (uint256 alphaAmount) {
        if (mechanism == MechanismType.Stable) {
            // 稳定机制：1:1兑换
            alphaAmount = hetuAmount;
        } else {
            // 动态机制：AMM计算
            if (subnetTAO == 0 || subnetAlphaIn == 0) {
                return 0;
            }
            
            // 恒定乘积公式: k = subnetTAO * subnetAlphaIn
            uint256 k = subnetTAO * subnetAlphaIn;
            uint256 newSubnetTAO = subnetTAO + hetuAmount;
            uint256 newSubnetAlphaIn = k / newSubnetTAO;
            
            // 检查流动性保护
            if (newSubnetAlphaIn < minimumPoolLiquidity) {
                return 0;
            }
            
            alphaAmount = subnetAlphaIn - newSubnetAlphaIn;
        }
        
        // 最终检查
        if (alphaAmount > subnetAlphaIn || subnetAlphaIn - alphaAmount < minimumPoolLiquidity) {
            return 0;
        }
    }
    
    /**
     * @dev 模拟Alpha换HETU
     */
    function simSwapAlphaForHETU(uint256 alphaAmount) public view returns (uint256 hetuAmount) {
        if (mechanism == MechanismType.Stable) {
            // 稳定机制：1:1兑换
            hetuAmount = alphaAmount;
        } else {
            // 动态机制：AMM计算
            if (subnetTAO == 0 || subnetAlphaIn == 0) {
                return 0;
            }
            
            // 恒定乘积公式: k = subnetTAO * subnetAlphaIn
            uint256 k = subnetTAO * subnetAlphaIn;
            uint256 newSubnetAlphaIn = subnetAlphaIn + alphaAmount;
            uint256 newSubnetTAO = k / newSubnetAlphaIn;
            
            // 检查流动性保护
            if (newSubnetTAO < minimumPoolLiquidity) {
                return 0;
            }
            
            hetuAmount = subnetTAO - newSubnetTAO;
        }
        
        // 最终检查
        if (hetuAmount > subnetTAO || subnetTAO - hetuAmount < minimumPoolLiquidity) {
            return 0;
        }
    }
    
    /**
     * @dev 获取当前Alpha价格
     */
    function getAlphaPrice() public view returns (uint256 price) {
        if (subnetAlphaIn == 0) {
            return 0;
        }
        return (subnetTAO * 1e18) / subnetAlphaIn;
    }
    
    /**
     * @dev 获取移动平均价格
     */
    function getMovingAlphaPrice() public view returns (uint256) {
        return movingAlphaPrice;
    }
    
    /**
     * @dev 更新移动平均价格
     * 任何人都可以调用，用于更新价格
     */
    function updateMovingPrice() external {
        _updatePrice();
    }
    
    /**
     * @dev 内部价格更新函数
     */
    function _updatePrice() internal {
        uint256 blocksSinceUpdate = block.number - priceUpdateBlock;
        if (blocksSinceUpdate == 0) return;
        
        // 计算当前价格
        currentAlphaPrice = getAlphaPrice();
        
        if (movingAlphaPrice == 0) {
            // 首次设置
            movingAlphaPrice = currentAlphaPrice;
        } else {
            // 计算指数移动平均
            uint256 alpha = (blocksSinceUpdate * 1e18) / (blocksSinceUpdate + HALVING_TIME);
            uint256 oneMinusAlpha = 1e18 - alpha;
            
            // 限制当前价格最大为1.0
            uint256 cappedCurrentPrice = currentAlphaPrice > 1e18 ? 1e18 : currentAlphaPrice;
            
            // 更新移动平均价格
            movingAlphaPrice = (alpha * cappedCurrentPrice + oneMinusAlpha * movingAlphaPrice) / 1e18;
        }
        
        priceUpdateBlock = block.number;
        emit PriceUpdated(currentAlphaPrice, movingAlphaPrice);
    }
    
    /**
     * @dev 将Alpha金额转换为HETU价值
     */
    function _convertToHETUValue(uint256 alphaAmount) internal view returns (uint256) {
        if (currentAlphaPrice == 0) return alphaAmount;
        return (alphaAmount * currentAlphaPrice) / 1e18;
    }
    
    /**
     * @dev 获取池子详细信息
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
     * @dev 获取创建者信息（仅用于记录）
     */
    function getCreatorInfo() external view returns (
        address _creator,
        uint256 _createdAt,
        uint256 _netuid
    ) {
        return (creator, createdAt, netuid);
    }
    
    /**
     * @dev 获取系统地址信息
     */
    function getSystemInfo() external view returns (
        address _systemAddress,
        address _subnetContract
    ) {
        return (systemAddress, subnetContract);
    }
    
    /**
     * @dev 获取兑换预览
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
                // 计算价格影响
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
                // 计算价格影响
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
     * @dev 检查大额交易警告
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
        
        // 计算交易占池子的百分比
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
     * @dev 批量兑换接口（兼容Uniswap接口）
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "AMM: EXPIRED");
        require(path.length == 2, "AMM: INVALID_PATH");
        require(path[0] != path[1], "AMM: IDENTICAL_ADDRESSES");
        
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        
        if (path[0] == address(hetuToken) && path[1] == address(alphaToken)) {
            amounts[1] = swapHETUForAlpha(amountIn, amountOutMin, to);
        } else if (path[0] == address(alphaToken) && path[1] == address(hetuToken)) {
            amounts[1] = swapAlphaForHETU(amountIn, amountOutMin, to);
        } else {
            revert("AMM: INVALID_PATH");
        }
    }
    
    /**
     * @dev 获取恒定乘积K值
     */
    function getK() external view returns (uint256) {
        return subnetTAO * subnetAlphaIn;
    }
    
    /**
     * @dev 检查池子健康状态
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
        
        liquidityRatio = 100; // 健康状态
        return (true, "Healthy", liquidityRatio);
    }
    
    /**
     * @dev 获取历史统计数据
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
     * @dev 获取用户交易统计
     */
    function getUserStats(address user) external view returns (
        uint256 _userVolume,
        uint256 _userVolumePercentage
    ) {
        _userVolume = userVolume[user];
        _userVolumePercentage = totalVolume > 0 ? (_userVolume * 10000) / totalVolume : 0;
    }
    
    /**
     * @dev 检查地址是否为系统地址
     */
    function isSystemAddress(address addr) external view returns (bool) {
        return addr == systemAddress || addr == subnetContract;
    }
    
    /**
     * @dev 检查地址是否为创建者（仅用于查询，无特殊权限）
     */
    function isCreator(address addr) external view returns (bool) {
        return addr == creator;
    }
    
    /**
     * @dev 获取代币余额
     */
    function getTokenBalances() external view returns (
        uint256 hetuBalance,
        uint256 alphaBalance
    ) {
        hetuBalance = hetuToken.balanceOf(address(this));
        alphaBalance = alphaToken.balanceOf(address(this));
    }
    
    /**
     * @dev 验证储备量一致性
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
     * @dev 计算理论价格（不考虑滑点）
     */
    function getTheoreticalPrice() external view returns (uint256) {
        if (subnetAlphaIn == 0) return 0;
        return (subnetTAO * 1e18) / subnetAlphaIn;
    }
    
    /**
     * @dev 计算滑点
     */
    function calculateSlippage(
        uint256 amountIn,
        bool isHETUToAlpha
    ) external view returns (uint256 slippageRate) {
        if (mechanism == MechanismType.Stable) {
            return 0; // 稳定机制无滑点
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

