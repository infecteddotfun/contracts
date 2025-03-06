// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IVirusFactory {
    function isVirusToken(address token) external view returns (bool);
} 
