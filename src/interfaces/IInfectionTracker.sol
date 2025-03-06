// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IInfectionTracker {
    function canBeInfected(address user) external view returns (bool);
    function updateInfection(address from, address to, uint256 virusId, uint256 amount) external;
    function getDominantVirus(address user) external view returns (uint256);
    function getInfectionCount(address user) external view returns (uint256);
}
