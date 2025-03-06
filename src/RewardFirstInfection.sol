// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./abstracts/GameAware.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IVirusFactory.sol";

contract RewardFirstInfection is GameAware, ReentrancyGuard {
    IVirusFactory public virusFactory;
    bool public isVirusFactorySet;
    address public immutable deployer;
    mapping(address => uint256) private rewards;
    mapping(address => mapping(address => uint256)) private tokenRewardsVirus;
    
    event RewardDeposited(address indexed infector, uint256 amount);
    event RewardWithdrawn(address indexed infector, uint256 amount);
    event VirusRewardDeposited(address indexed infector, uint256 amount, address token);
    event VirusRewardWithdrawn(address indexed infector, uint256 amount, address token);

    modifier onlyDeployer() {
        require(msg.sender == deployer, "Only deployer can call");
        _;
    }

    constructor(address _gameManager) GameAware(_gameManager) {
        deployer = msg.sender;
    }

    function setVirusFactory(address _virusFactory) external onlyDeployer {
        require(!isVirusFactorySet, "Virus factory already set");
        require(_virusFactory != address(0), "Invalid virus factory address");
        virusFactory = IVirusFactory(_virusFactory);
        isVirusFactorySet = true;
    }

    function deposit(address infector) external payable {
        require(msg.value > 0, "Deposit amount must be greater than 0");
        require(infector != address(0), "Invalid infector address");
        
        rewards[infector] += msg.value;
        emit RewardDeposited(infector, msg.value);
    }

    function recordVirusDeposit(address infector, uint256 amount) external {
        require(isVirusFactorySet, "Virus factory not set");
        require(infector != address(0), "Invalid infector address");
        require(amount > 0, "Amount must be greater than 0");
        require(virusFactory.isVirusToken(msg.sender), "Not a valid virus token");
        
        address token = msg.sender;
        tokenRewardsVirus[token][infector] += amount;
        
        emit VirusRewardDeposited(infector, amount, token);
    }

    function withdraw() external onlyAfterGame nonReentrant {
        uint256 ethAmount = rewards[msg.sender];
        require(ethAmount > 0, "No rewards available");
        if (ethAmount > 0) {
            rewards[msg.sender] = 0;
            (bool success, ) = payable(msg.sender).call{value: ethAmount}("");
            require(success, "ETH transfer failed");
            emit RewardWithdrawn(msg.sender, ethAmount);
        }
    }

    function withdrawVirus(address virus) external onlyAfterGame nonReentrant {
        uint256 tokenAmount = tokenRewardsVirus[virus][msg.sender];
        require(tokenAmount > 0, "No rewards available");
        tokenRewardsVirus[virus][msg.sender] = 0;
        IERC20(virus).transfer(msg.sender, tokenAmount);
        emit VirusRewardWithdrawn(msg.sender, tokenAmount, virus);
    }

    function getRewardAmount(address infector) external view returns (uint256) {
        return rewards[infector];
    }

    function getVirusRewardAmount(address infector, address virus) external view returns (uint256) {
        return tokenRewardsVirus[virus][infector];
    }
    receive() external payable {}
}
