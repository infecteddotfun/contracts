// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ITransactionType {
    enum TransactionType {
        NORMAL_TRANSFER,
        TOKEN_PURCHASE,
        TOKEN_SELL
    }
} 
