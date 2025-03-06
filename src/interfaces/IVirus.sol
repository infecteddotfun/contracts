// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IVirus Interface
/// @notice Interface for the Virus contract's airdrop functionality
interface IVirus {
    /// @notice Records infection tracking for airdrop transfers
    /// @param from The original sender of the tokens
    /// @param to The recipient of the tokens
    /// @param amount The amount of tokens being transferred
    function airdropTransfer(address from, address to, uint256 amount) external;

    /// @notice Burns tokens, reducing the total supply
    /// @param amount The amount of tokens to burn
    function burn(uint256 amount) external;
} 
