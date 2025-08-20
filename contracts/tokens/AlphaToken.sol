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
    address public immutable subnetManager;
    
    // System address for protocol-level operations
    address public immutable systemAddress;
    
    mapping(address => bool) public authorized_minters;

    // Token creation time
    uint256 public immutable createdAt;
    
    modifier onlySubnetManager(){
        require(msg.sender == subnetManager, "AlphaToken: ONLY_SUBNET_MANAGER");
        _;
    }

    modifier onlySystem() {
        require(
            msg.sender == systemAddress || msg.sender == subnetManager, 
            "AlphaToken: ONLY_SYSTEM"
        );
        _;
    }

    modifier onlyAuthorizedMinter() {
        require(authorized_minters[msg.sender], "AlphaToken: NOT_AUTHORIZED_MINTER");
        _;
    }
    
    constructor(
        string memory name,
        string memory symbol,
        address _minter,
        uint16 _netuid,
        address _systemAddress
    ) ERC20(name, symbol) Ownable(_minter){
        require(_minter != address(0), "AlphaToken: ZERO_MINTER");
        require(_systemAddress != address(0), "AlphaToken: ZERO_SYSTEM_ADDRESS");

        subnetManager = _minter;
        systemAddress = _systemAddress;
        netuid = _netuid;
        createdAt = block.timestamp;
        authorized_minters[subnetManager] = true;
    }
    
    /**
     * @dev Add minter address (only subnetManager)
     */
    function addMinter(address minter) external onlySubnetManager {
        require(minter != address(0), "AlphaToken: ZERO_ADDRESS");
        require(!authorized_minters[minter], "AlphaToken: ALREADY_MINTER");

        authorized_minters[minter] = true;
        emit MinterAdded(minter);
    }

    /**
     * @dev Remove minter address (only subnetManager)
     */
    function removeMinter(address minter) external onlySubnetManager {
        require(minter != address(0), "AlphaToken: ZERO_ADDRESS");
        require(minter != subnetManager, "AlphaToken: CANNOT_REMOVE_SUBNET_MANAGER");
        require(authorized_minters[minter], "AlphaToken: NOT_AUTHORIZED_MINTER");

        authorized_minters[minter] = false;
        emit MinterRemoved(minter);
    }

    /**
     * @dev Mint tokens (only minter)
     */
    function mint(address to, uint256 amount) external onlyAuthorizedMinter {
        require(to != address(0), "AlphaToken: ZERO_ADDRESS");
        require(amount > 0, "AlphaToken: ZERO_AMOUNT");
        
        _mint(to, amount);
        emit TokensMinted(to, amount);
    }
    
    /**
     * @dev Burn tokens (only minter)
     */
    function burn(address from, uint256 amount) external onlyAuthorizedMinter {
        require(from != address(0), "AlphaToken: ZERO_ADDRESS");
        require(amount > 0, "AlphaToken: ZERO_AMOUNT");
        require(balanceOf(from) >= amount, "AlphaToken: INSUFFICIENT_BALANCE");
        
        _burn(from, amount);
        emit TokensBurned(from, amount);
    }
    
    
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
            subnetManager,
            createdAt
        );
    }

    /**
     * @dev Get system address
     */
    function getSystemAddress() external view returns (address) {
        return systemAddress;
    }

    /**
     * @dev Check if address has system privileges
     */
    function isSystemAddress(address addr) external view returns (bool) {
        return addr == systemAddress || addr == subnetManager;
    }

    /**
     * @dev Check if address is authorized minter
     */
    function isAuthorizedMinter(address addr) external view returns (bool) {
        return authorized_minters[addr];
    }
}
