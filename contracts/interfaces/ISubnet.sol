// contracts/interfaces/ISubnet.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ISubnet {
    function updateStakeAllocation(address user, uint256 amount) external;
    function lockStakeForRegistration(address user, uint256 amount) external;
    function unlockStake(address user, uint256 amount) external;
    function distributeRewards(address user, uint256 amount) external;
    function getMinStakeRequired() external view returns (uint256);
    function isNeuronActive(address user) external view returns (bool);
}