// contracts/subnet/AlphaToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IAlphaToken.sol";
/**
 * @title AlphaToken
 * @dev Alpha token contract for subnets
 * Each subnet has its own unique Alpha token
 */
contract AlphaToken is ERC20, Ownable, IAlphaToken {
    
    // Subnet ID
    uint16 public immutable netuid;
    
    // Minter address (usually SubnetManager)
    address public minter;
    
    // Token creation time
    uint256 public immutable createdAt;
    
    modifier onlyMinter() {
        require(msg.sender == minter, "AlphaToken: ONLY_MINTER");
        _;
    }
    
    constructor(
        string memory name,
        string memory symbol,
        address _minter,
        uint16 _netuid
    ) ERC20(name, symbol) Ownable(_minter){
        require(_minter != address(0), "AlphaToken: ZERO_MINTER");
        
        minter = _minter;
        netuid = _netuid;
        createdAt = block.timestamp;
    }
    
    /**
     * @dev Mint tokens (only minter)
     */
    function mint(address to, uint256 amount) external onlyMinter {
        require(to != address(0), "AlphaToken: ZERO_ADDRESS");
        require(amount > 0, "AlphaToken: ZERO_AMOUNT");
        
        _mint(to, amount);
        emit TokensMinted(to, amount);
    }
    
    /**
     * @dev Burn tokens (only minter)
     */
    function burn(address from, uint256 amount) external onlyMinter {
        require(from != address(0), "AlphaToken: ZERO_ADDRESS");
        require(amount > 0, "AlphaToken: ZERO_AMOUNT");
        require(balanceOf(from) >= amount, "AlphaToken: INSUFFICIENT_BALANCE");
        
        _burn(from, amount);
        emit TokensBurned(from, amount);
    }
    
    /**
     * @dev Change minter (only owner)
     */
    // function changeMinter(address newMinter) external onlyOwner {
    //     require(newMinter != address(0), "AlphaToken: ZERO_MINTER");
        
    //     address oldMinter = minter;
    //     minter = newMinter;
        
    //     emit MinterChanged(oldMinter, newMinter);
    // }
    
    /**
     * @dev Get token information
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
