// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./abstracts/GameAware.sol";
import "./InfectionManager.sol";
import "./VirusFactory.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap-v2-core-1.0.1/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap-v2-core-1.0.1/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap-v2-periphery-1.1.0-beta.0/contracts/interfaces/IUniswapV2Router02.sol";
import "./interfaces/IVirus.sol";
import "./interfaces/IWETH.sol";

contract RewardWinnerPot is Ownable, ReentrancyGuard, GameAware {
    using Address for address payable;

    // Constants for fee distribution
    uint256 private constant FIRST_PLACE_SHARE = 170; // 17%
    uint256 private constant SECOND_PLACE_SHARE = 100; // 10%
    uint256 private constant THIRD_PLACE_SHARE = 70; // 7%

    uint256 public constant UNISWAP_SHARE = 660; // 66%
    uint256 public constant TOTAL_SHARES = 1000; // 100%

    address public immutable WETH;
    address private immutable DEAD_ADDRESS;

    uint256 public totalFees;
    address public immutable deployerAddress;
    address public uniswapFactory;
    address public uniswapRouter;
    bool public deployerClaimed;

    mapping(address => uint256) public pendingRewards;
    bool public isDistributed;

    event FeesAccumulated(uint256 amount);
    event RewardsDeposited(address indexed depositor, uint256 amount);
    event RewardsDistributed(address[] winners, uint256[] amounts);
    event RewardClaimed(address indexed user, uint256 amount);
    event UniswapShareTransferred(uint256 amount);
    event DeployerShareTransferred(uint256 amount);
    event UniswapShareBurned(uint256 amount);

    InfectionManager public infectionManager;
    VirusFactory public virusFactory;
    
    bool public contractsInitialized;

    event ContractsInitialized(address virusFactory);

    uint256 public initialSlippage = 950; // 95% (5% initial max slippage)
    uint256 public maxSlippage = 900; // 90% (10% absolute max slippage)
    uint256 public slippageStep = 10; // 1% steps

    constructor(
        address _uniswapFactory,
        address _uniswapRouter,
        address _gameManager,
        address _infectionManager,
        address _weth
    ) Ownable(msg.sender) GameAware(_gameManager) {
        require(
            _uniswapFactory != address(0),
            "Invalid uniswap manager address"
        );
        require(
            _infectionManager != address(0),
            "Invalid infection manager address"
        );
        deployerAddress = msg.sender;
        uniswapFactory = _uniswapFactory;
        uniswapRouter = _uniswapRouter;
        infectionManager = InfectionManager(_infectionManager);
        WETH = _weth;
    }

    function setVirusFactory(
        address _virusFactory
    ) external onlyOwner {
        require(!contractsInitialized, "Contracts are already initialized");
        require(_virusFactory != address(0), "Invalid virus factory address");
        virusFactory = VirusFactory(payable(_virusFactory));
        
        contractsInitialized = true;
        emit ContractsInitialized(_virusFactory);
    }

    receive() external payable {
        require(contractsInitialized, "Contracts not initialized");
        require(msg.value > 0, "Must deposit some ETH");
        totalFees += msg.value;
        emit RewardsDeposited(msg.sender, msg.value);
        emit FeesAccumulated(msg.value);
    }

    function aggregation() external onlyAfterGame {
        require(virusFactory.allTokensUniswapEnabled(), "All viruses are not added to Uniswap V2.");

        uint256 wethBalance = IERC20(WETH).balanceOf(address(this));
        if (wethBalance > 0) {
            IWETH(WETH).withdraw(wethBalance);
        }

        (
            address winningVirusContract,
        ) = _getWinningVirus();
        (
            address[3] memory topInfectors,
        ) = _getTopInfectors(winningVirusContract);
        _distributeWinnerRewards(topInfectors);

        _buyAndBurnWinningVirus(winningVirusContract);
    }

    function _getWinningVirus()
        internal
        view
        returns (address winningVirusContract, uint256 maxInfections)
    {
        (
            address[] memory virusAddresses,
            uint256[] memory counts
        ) = infectionManager.getAllActiveInfectionCounts();

        maxInfections = 0;
        for (uint256 i = 0; i < virusAddresses.length; i++) {
            if (virusAddresses[i] == address(0)) break;
            if (counts[i] > maxInfections) {
                maxInfections = counts[i];
                winningVirusContract = virusAddresses[i];
            }
        }

        require(winningVirusContract != address(0), "No winning virus found");
        return (winningVirusContract, maxInfections);
    }

    function _getTopInfectors(
        address virusContract
    ) internal view returns (address[3] memory, uint256[3] memory) {
        return infectionManager.getTopInfectors(virusContract);
    }

    function _distributeWinnerRewards(address[3] memory topInfectors) internal {
        require(!isDistributed, "Rewards already distributed");

        uint256 totalRewardAmount = totalFees;

        uint256 firstPlaceAmount = (totalRewardAmount * FIRST_PLACE_SHARE) /
            TOTAL_SHARES;
        uint256 secondPlaceAmount = (totalRewardAmount * SECOND_PLACE_SHARE) /
            TOTAL_SHARES;
        uint256 thirdPlaceAmount = (totalRewardAmount * THIRD_PLACE_SHARE) /
            TOTAL_SHARES;

        pendingRewards[topInfectors[0]] += firstPlaceAmount;
        pendingRewards[topInfectors[1]] += secondPlaceAmount;
        pendingRewards[topInfectors[2]] += thirdPlaceAmount;

        isDistributed = true;
    }

    function claimReward() external nonReentrant onlyAfterGame {
        uint256 reward = pendingRewards[msg.sender];
        require(reward > 0, "No rewards to claim");
        pendingRewards[msg.sender] = 0;

        require(address(this).balance >= reward, "Insufficient contract balance");

        payable(msg.sender).sendValue(reward);
        emit RewardClaimed(msg.sender, reward);
    }

    function setSlippageParameters(
        uint256 _initialSlippage,
        uint256 _maxSlippage,
        uint256 _slippageStep
    ) external onlyOwner {
        require(_initialSlippage > _maxSlippage, "Initial slippage must be higher than max");
        require(_initialSlippage <= 1000 && _maxSlippage > 0, "Invalid slippage values");
        require(_slippageStep > 0, "Invalid step value");
        initialSlippage = _initialSlippage;
        maxSlippage = _maxSlippage;
        slippageStep = _slippageStep;
    }

    function _buyAndBurnWinningVirus(address winningVirusContract) internal {
        uint256 uniswapAmount = (totalFees * UNISWAP_SHARE) / TOTAL_SHARES;
        require(uniswapAmount > 0, "No ETH for Uniswap");

        address pair = IUniswapV2Factory(uniswapFactory).getPair(
            winningVirusContract,
            WETH
        );
        require(pair != address(0), "Pair does not exist");

        IUniswapV2Router02 router = IUniswapV2Router02(uniswapRouter);

        // Set swap parameters
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = winningVirusContract;

        uint256[] memory amountsOut = router.getAmountsOut(uniswapAmount, path);
        
        uint256 currentSlippage = initialSlippage;
        bool swapSuccess = false;

        while (currentSlippage >= maxSlippage && !swapSuccess) {
            uint256 minAmountOut = (amountsOut[1] * currentSlippage) / 1000;
            
            try router.swapExactETHForTokens{value: uniswapAmount}(
                minAmountOut,
                path,
                address(this),
                block.timestamp + 15
            ) {
                swapSuccess = true;
            } catch {
                // Reduce acceptance threshold by step
                currentSlippage = currentSlippage - slippageStep;
            }
        }

        require(swapSuccess, "Swap failed at all slippage levels");

        // Continue with token burning
        uint256 tokenBalance = IERC20(winningVirusContract).balanceOf(address(this));
        if (tokenBalance > 0) {
            IVirus(winningVirusContract).burn(tokenBalance);
            emit UniswapShareBurned(tokenBalance);
        }
    }

    function getClaimableReward(address _address) public view returns (uint256) {
        return pendingRewards[_address];
    }

    function getTotalBalance() public view returns (uint256) {
        return address(this).balance + IERC20(WETH).balanceOf(address(this));
    }
}
