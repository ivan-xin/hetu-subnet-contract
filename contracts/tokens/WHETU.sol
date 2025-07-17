// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title WHETU
 * @dev Wrapped HETU Token - Wraps native HETU token into an ERC20 token
 * Similar to WETH, with 1:1 exchange ratio
 */
contract WHETU is ERC20Permit, ReentrancyGuard {
    
    // Events
    event Deposit(address indexed user, uint256 amount);
    event Withdrawal(address indexed user, uint256 amount);
    
    constructor() ERC20("Wrapped HETU", "WHETU") ERC20Permit("Wrapped HETU") {}
    
    /**
     * @dev Receive native HETU and mint equivalent WHETU
     */
    receive() external payable {
        deposit();
    }
    
    /**
     * @dev Deposit native HETU, mint equivalent WHETU
     */
    function deposit() public payable nonReentrant {
        require(msg.value > 0, "WHETU: ZERO_DEPOSIT");
        
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }
    
    /**
     * @dev Burn WHETU, withdraw equivalent native HETU
     * @param amount Amount to withdraw
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
     * @dev Get native HETU balance in contract
     */
    function totalETH() external view returns (uint256) {
        return address(this).balance;
    }
}
