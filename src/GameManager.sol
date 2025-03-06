// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract GameManager {
    uint public immutable gameStartTime;
    uint public constant GAME_DURATION = 7 days;

    event GameStarted(uint startTime);

    constructor(uint _startTime) {
        require(
            _startTime >= block.timestamp,
            "Start time must be in the future"
        );
        gameStartTime = _startTime;
        emit GameStarted(_startTime);
    }

    function isGameActive() public view returns (bool) {
        return
            block.timestamp >= gameStartTime &&
            block.timestamp < gameStartTime + GAME_DURATION;
    }

    function isGamePending() public view returns (bool) {
        return block.timestamp < gameStartTime;
    }

    function isGameEnded() public view returns (bool) {
        return block.timestamp >= gameStartTime + GAME_DURATION;
    }

    function getRemainingTime() public view returns (uint) {
        if (isGamePending()) {
            return gameStartTime - block.timestamp;
        } else if (isGameActive()) {
            return (gameStartTime + GAME_DURATION) - block.timestamp;
        } else {
            return 0;
        }
    }
}
