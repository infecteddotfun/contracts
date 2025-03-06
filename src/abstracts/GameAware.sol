// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../interfaces/IGameManager.sol";

abstract contract GameAware {
    IGameManager public gameManager;

    constructor(address _gameManager) {
        require(
            _gameManager != address(0),
            "GameManager address cannot be zero"
        );
        gameManager = IGameManager(_gameManager);
    }

    modifier onlyDuringGame() {
        require(gameManager.isGameActive(), "Game is not active");
        _;
    }

    modifier onlyBeforeGame() {
        require(
            !gameManager.isGameActive() && !gameManager.isGameEnded(),
            "Game already started or ended"
        );
        _;
    }

    modifier onlyAfterGame() {
        require(gameManager.isGameEnded(), "Game is not ended yet");
        _;
    }
}
