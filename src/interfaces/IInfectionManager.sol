// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IInfectionManager {
    enum TransactionType {
        NORMAL_TRANSFER,
        TOKEN_PURCHASE,
        TOKEN_SELL
    }

    /// @notice Attempts to infect a target address
    /// @param infector The address attempting to infect
    /// @param victim The address being infected
    /// @param newAmount The amount of tokens involved in the infection
    /// @param txType The type of transaction causing the infection
    /// @return success Whether the infection was successful
    function tryInfect(
        address infector,
        address victim,
        uint256 newAmount,
        TransactionType txType
    ) external returns (bool);
} 
