// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title WHETU
 * @dev Wrapped HETU Token - 将原生HETU代币包装成ERC20代币
 * 类似于WETH，1:1兑换比例
 */
contract WHETU is ERC20, ReentrancyGuard {
    
    // 事件
    event Deposit(address indexed user, uint256 amount);
    event Withdrawal(address indexed user, uint256 amount);
    
    constructor() ERC20("Wrapped HETU", "WHETU") {}
    
    /**
     * @dev 接收原生HETU并铸造等量WHETU
     */
    receive() external payable {
        deposit();
    }
    
    /**
     * @dev 存入原生HETU，铸造等量WHETU
     */
    function deposit() public payable nonReentrant {
        require(msg.value > 0, "WHETU: ZERO_DEPOSIT");
        
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }
    
    /**
     * @dev 销毁WHETU，提取等量原生HETU
     * @param amount 要提取的数量
     */
    function withdraw(uint256 amount) public nonReentrant {
        require(amount > 0, "WHETU: ZERO_WITHDRAWAL");
        require(balanceOf(msg.sender) >= amount, "WHETU: INSUFFICIENT_BALANCE");
        
        _burn(msg.sender, amount);
        
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "WHETU: TRANSFER_FAILED");
        
        emit Withdrawal(msg.sender, amount);
    }
    
    /**
     * @dev 获取合约中的原生HETU余额
     */
    function totalETH() external view returns (uint256) {
        return address(this).balance;
    }
}
