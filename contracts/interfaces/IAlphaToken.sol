// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IAlphaToken
 * @dev Alpha Token Interface - Based on AlphaToken.sol implementation
 */
interface IAlphaToken is IERC20 {
    
    // ============ Events ============
    event MinterChanged(address indexed oldMinter, address indexed newMinter);
    event TokensMinted(address indexed to, uint256 amount);
    event TokensBurned(address indexed from, uint256 amount);
    
    // ============ Core Functions ============

    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    // function changeMinter(address newMinter) external;
    
    // ============ View Functions ============
    
    function netuid() external view returns (uint16);
    function minter() external view returns (address);
    function createdAt() external view returns (uint256);
    function getTokenInfo() external view returns (
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        uint16 _netuid,
        address _minter,
        uint256 _createdAt
    );
}
