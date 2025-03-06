// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IGameManager {
    function isGameActive() external view returns (bool);
    function isGameEnded() external view returns (bool);
}
