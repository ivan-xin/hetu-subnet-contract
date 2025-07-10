// contracts/subnet/AlphaToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AlphaToken
 * @dev 子网的Alpha代币合约
 * 每个子网都有自己独特的Alpha代币
 */
contract AlphaToken is ERC20, Ownable {
    
    // 子网ID
    uint16 public immutable netuid;
    
    // 铸造者地址（通常是SubnetManager）
    address public minter;
    
    // 代币创建时间
    uint256 public immutable createdAt;
    
    // 事件
    event MinterChanged(address indexed oldMinter, address indexed newMinter);
    event TokensMinted(address indexed to, uint256 amount);
    event TokensBurned(address indexed from, uint256 amount);
    
    modifier onlyMinter() {
        require(msg.sender == minter, "AlphaToken: ONLY_MINTER");
        _;
    }
    
    constructor(
        string memory name,
        string memory symbol,
        address _minter,
        uint16 _netuid
    ) ERC20(name, symbol) {
        require(_minter != address(0), "AlphaToken: ZERO_MINTER");
        
        minter = _minter;
        netuid = _netuid;
        createdAt = block.timestamp;
        
        // 将所有权转移给minter
        _transferOwnership(_minter);
    }
    
    /**
     * @dev 铸造代币（仅铸造者）
     */
    function mint(address to, uint256 amount) external onlyMinter {
        require(to != address(0), "AlphaToken: ZERO_ADDRESS");
        require(amount > 0, "AlphaToken: ZERO_AMOUNT");
        
        _mint(to, amount);
        emit TokensMinted(to, amount);
    }
    
    /**
     * @dev 燃烧代币（仅铸造者）
     */
    function burn(address from, uint256 amount) external onlyMinter {
        require(from != address(0), "AlphaToken: ZERO_ADDRESS");
        require(amount > 0, "AlphaToken: ZERO_AMOUNT");
        require(balanceOf(from) >= amount, "AlphaToken: INSUFFICIENT_BALANCE");
        
        _burn(from, amount);
        emit TokensBurned(from, amount);
    }
    
    /**
     * @dev 更改铸造者（仅所有者）
     */
    function changeMinter(address newMinter) external onlyOwner {
        require(newMinter != address(0), "AlphaToken: ZERO_MINTER");
        
        address oldMinter = minter;
        minter = newMinter;
        
        emit MinterChanged(oldMinter, newMinter);
    }
    
    /**
     * @dev 获取代币信息
     */
    function getTokenInfo() external view returns (
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        uint16 _netuid,
        address _minter,
        uint256 _createdAt
    ) {
        return (
            name(),
            symbol(),
            totalSupply(),
            netuid,
            minter,
            createdAt
        );
    }
}
