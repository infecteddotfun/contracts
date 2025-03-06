// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./interfaces/ITransactionType.sol";
import "./InfectionManager.sol";
import "./RewardFirstInfection.sol";
import "./RewardWinnerPot.sol";
import "./abstracts/GameAware.sol";
import "./VirusFactory.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@uniswap-v2-core-1.0.1/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap-v2-core-1.0.1/contracts/interfaces/IUniswapV2Pair.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Virus is ERC20, GameAware, ITransactionType, ReentrancyGuard {
    IUniswapV2Router02 public immutable uniswap_router;
    address payable public virusFactory;
    address public immutable uniswap_factory;
    address public immutable pairAddressWithWeth;
    address public immutable WETH;
    address public devAddress;
    address public winnerPot;
    address public virusDrop;
    InfectionManager public immutable infectionManager;
    RewardWinnerPot public immutable rewardWinnerPot;
    RewardFirstInfection public immutable rewardFirstInfection;
    
    uint256 public DEV_FEE_PERCENTAGE = 10; // 1% = 10/1000
    uint256 public WINNER_POT_FEE_PERCENTAGE = 15; //1.5% = 15/1000
    uint256 public AFTER_GAME_DEV_FEE_PERCENTAGE = 5; // 0.5% = 5/1000
    uint256 public constant FIRST_INFECTED_FEE_PERCENTAGE = 10; // 1.0% = 10/1000
    uint public constant FEE_DENOMINATOR = 1000;

    uint256 public accumulatedWinnerPotFeeVirus;
    uint256 public accumulatedDevFeeVirus;

    uint256 public slippagePercentage = 50;

    event FeesCollected(
        uint256 winnerPotFee,
        uint256 devFee,
        uint256 firstInfectedFee,
        address firstInfector
    );
    
    event TaxesProcessed(
        uint256 winnerPotAmount,
        uint256 devAmount
    );

    event UniswapStateChanged(
        bool enabled
    );

    constructor(
        string memory name,
        string memory symbol,
        uint initialMint,
        address _rewardWinnerPot,
        address _uniswapFactory,
        address _uniswapRouter,
        address _infectionManager,
        address _rewardFirstInfection,
        address _gameManager,
        address _devAddress,
        address _winnerPot,
        address _weth,
        address _virusDrop
    ) ERC20(name, symbol) GameAware(_gameManager) {
        _mint(msg.sender, initialMint);
        virusFactory = payable(msg.sender);
        rewardWinnerPot = RewardWinnerPot(payable(_rewardWinnerPot));
        uniswap_router = IUniswapV2Router02(_uniswapRouter);
        uniswap_factory = _uniswapFactory;
        rewardFirstInfection = RewardFirstInfection(payable(_rewardFirstInfection));
        infectionManager = InfectionManager(_infectionManager);
        devAddress = _devAddress;
        winnerPot = _winnerPot;
        WETH = _weth;
        pairAddressWithWeth = IUniswapV2Factory(uniswap_factory).createPair(address(this), WETH);
        virusDrop = _virusDrop;
    }

    function _calculateFees(
        address from,
        address to,
        uint256 amount
    ) private returns (uint256 winnerPotFee, uint devFee, address firstInfectorAddress, uint256 firstInfectedFee) {
        bool isActive = gameManager.isGameActive();
        if (isActive) {
            winnerPotFee = amount * WINNER_POT_FEE_PERCENTAGE / FEE_DENOMINATOR;
            devFee = amount * DEV_FEE_PERCENTAGE / FEE_DENOMINATOR;
        } else {
            winnerPotFee = 0;
            devFee = amount * AFTER_GAME_DEV_FEE_PERCENTAGE / FEE_DENOMINATOR;
        }
        if (from == pairAddressWithWeth) {
            (address firstInfector,,bool isFirstInfectionActive) = infectionManager.getFirstInfection(to);
                if (isFirstInfectionActive && firstInfector != address(0)) {
                    firstInfectedFee = (amount * FIRST_INFECTED_FEE_PERCENTAGE) / FEE_DENOMINATOR;
                        firstInfectorAddress = firstInfector;
                }
        }
        emit FeesCollected(winnerPotFee, devFee, firstInfectedFee, firstInfectorAddress);
        return (winnerPotFee, devFee, firstInfectorAddress, firstInfectedFee);
    }

    function processTaxes() external nonReentrant {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WETH;

        require(accumulatedWinnerPotFeeVirus > 0 || accumulatedDevFeeVirus > 0, "No fees to process");
        
        if (IERC20(address(this)).allowance(address(this), address(uniswap_router)) == 0) {
            _approve(address(this), address(uniswap_router), type(uint256).max);
        }
        
        if (accumulatedWinnerPotFeeVirus > 0) {
            uint256 amountToSwap = accumulatedWinnerPotFeeVirus;
            accumulatedWinnerPotFeeVirus = 0;
            
            uint256[] memory amountsOut = uniswap_router.getAmountsOut(amountToSwap, path);
            uint256 minAmountOut = amountsOut[1] * (1000 - slippagePercentage) / 1000;
            
            uniswap_router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                amountToSwap,
                minAmountOut,
                path,
                address(rewardWinnerPot),
                block.timestamp
            );
        }

        if (accumulatedDevFeeVirus > 0) {
            uint256 amountToSwap = accumulatedDevFeeVirus;
            accumulatedDevFeeVirus = 0;
            
            uint256[] memory amountsOut = uniswap_router.getAmountsOut(amountToSwap, path);
            uint256 minAmountOut = amountsOut[1] * (1000 - slippagePercentage) / 1000;
            
            uniswap_router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                amountToSwap,
                minAmountOut,
                path,
                address(devAddress),
                block.timestamp
            );
        }
    }

    function _isUniswapEnabled() private view returns (bool) {
        VirusFactory factory = VirusFactory(virusFactory);
        return factory.tokens(address(this)) == VirusFactory.TokenState.UNISWAP_ENABLED;
    }

    function _update(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        if (from == address(virusDrop)) {
            super._update(from, to, amount);
            return;
        }

        if (from == address(0) || to == address(0)) {
            super._update(from, to, amount);
            return;
        }
        
        bool _isTaxable = true;
        if (_excludedFromTaxes(from) || _excludedFromTaxes(to)) {
            _isTaxable = false;
        }

        if (_isTaxable) {        
            bool isUniswapTrade = from == pairAddressWithWeth ||
            to == pairAddressWithWeth;
            if (isUniswapTrade) {
                if (!_isUniswapEnabled()) {
                    revert("Direct transfers with Uniswap pairs are not allowed until bonding curve is ended");
                }
                TransactionType txType;
                if (from == pairAddressWithWeth) {
                    txType = TransactionType.TOKEN_PURCHASE;
                } else {
                    txType = TransactionType.TOKEN_SELL;
                }
                (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(
                    pairAddressWithWeth
                ).getReserves();
                bool uniswapEnabled = reserve0 > 0 && reserve1 > 0;

                if ((to != address(this)) && uniswapEnabled) {
                    infectionManager.tryInfect(tx.origin, tx.origin, amount, InfectionManager.TransactionType(uint(txType)));
                    (uint256 winnerPotFee, uint256 devFee, address firstInfectorAddress, uint256 firstInfectedFee) = _calculateFees(from, to, amount);
                    uint allFee = winnerPotFee + devFee + firstInfectedFee;
                    amount -= allFee;

                    accumulatedWinnerPotFeeVirus += winnerPotFee;
                    accumulatedDevFeeVirus += devFee;
                    
                    super._update(from, address(this), (winnerPotFee + devFee));
                    
                    if (firstInfectedFee > 0) {
                        rewardFirstInfection.recordVirusDeposit(firstInfectorAddress, firstInfectedFee);
                        super._update(from, address(rewardFirstInfection), firstInfectedFee);
                    }
                }
            } else {
                TransactionType txType = TransactionType.NORMAL_TRANSFER;
                if (to == address(virusFactory)) {
                    txType = TransactionType.TOKEN_SELL;
                }
                
                infectionManager.tryInfect(
                    from, 
                    to, 
                    amount, 
                    InfectionManager.TransactionType(uint(txType))
                );
            }
        }
        super._update(from, to, amount);
    }

    function _excludedFromTaxes(address addr) internal view returns (bool) {
        if (addr == address(this)) return true;
        if (addr == address(winnerPot)) return true;
        if (addr == address(rewardFirstInfection)) return true;
        if (addr == address(devAddress)) return true;
        return false;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == virusFactory, "Only virusFactory can mint");
        infectionManager.tryInfect(
            to, 
            to, 
            amount, 
            InfectionManager.TransactionType(uint(TransactionType.TOKEN_PURCHASE))
        );
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function airdropTransfer(address from, address to, uint256 amount) external {
        require(msg.sender == virusDrop, "Only virusDrop can call this function");
        infectionManager.tryInfect(
            from,
            to,
            amount,
            InfectionManager.TransactionType(uint(TransactionType.NORMAL_TRANSFER))
        );
    }

    function setSlippagePercentage(uint256 _slippagePercentage) external {
        require(msg.sender == devAddress, "Only the developer can set this.");
        slippagePercentage = _slippagePercentage;
    }
}
