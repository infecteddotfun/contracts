// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./Virus.sol";
import "./abstracts/GameAware.sol";
import "./RewardWinnerPot.sol";
import "./RewardFirstInfection.sol";
import "./InfectionManager.sol";

import "@uniswap-v2-core-1.0.1/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap-v2-core-1.0.1/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap-v2-periphery-1.1.0-beta.0/contracts/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract VirusFactory is Ownable, GameAware, ReentrancyGuard {
    event TokenStateChanged(address indexed virus, TokenState state);

    InfectionManager public infectionManager;
    RewardWinnerPot public rewardWinnerPot;
    RewardFirstInfection public rewardFirstInfection;
    uint256 private nextVirusId;
    address[] public allTokens;
    bool public allTokensUniswapEnabled;
    uint256 public lastProcessedIndex;

    address public immutable UNISWAP_V2_FACTORY;
    address public immutable UNISWAP_V2_ROUTER;
    address public immutable devAddress;
    address public immutable virusDrop;
    uint256 public accumulatedEth;

    bytes32 public merkleRoot;
    uint256 public whitelistEndTime;

    uint256 public constant WHITELIST_MAX_PURCHASE = 0.5 ether;
    mapping(address => uint256) public whitelistPurchases;

    constructor(
        address _gameManager,
        address _infectionManager,
        address payable _rewardWinnerPot,
        address payable _rewardFirstInfection,
        address _uniswapFactory,
        address _uniswapRouter,
        address _devAddress,
        address _virusDrop
    ) Ownable(msg.sender) GameAware(_gameManager) {
        infectionManager = InfectionManager(_infectionManager);
        rewardWinnerPot = RewardWinnerPot(_rewardWinnerPot);
        rewardFirstInfection = RewardFirstInfection(payable(_rewardFirstInfection));
        UNISWAP_V2_FACTORY = _uniswapFactory;
        UNISWAP_V2_ROUTER = _uniswapRouter;
        nextVirusId = 0;
        devAddress = _devAddress;
        virusDrop = _virusDrop;
    }

    enum TokenState {
        NOT_CREATED,
        ACTIVE,
        UNISWAP_ENABLED
    }

    uint public constant FEE_PERCENTAGE = 25 * 1e15; // 2.5% = 0.025 * 1e18
    uint public constant INFECTED_FEE_PERCENTAGE = 10 * 1e15; // 1% = 0.01 * 1e18
    uint public constant DECIMALS = 1e18;
    uint public constant MAX_SUPPLY = 100_000_000_000 * DECIMALS; // 100 billion
    uint public constant SUPPLY_THRESHOLD = 67_000_000_000 * DECIMALS; // 67 billion
    

    uint public constant WINNER_POT_SHARE = 60; // 60%
    uint public constant ALL_SHARE = 100; // 100%

    mapping(address => TokenState) public tokens;
    mapping(address => uint) public collateral; // amount of ETH received
    mapping(address => mapping(address => uint)) public balances; // token balances for ppl bought tokens not released yet
    mapping(address => uint256) public customSlippageTolerances;

    uint256 public constant DEFAULT_SLIPPAGE_TOLERANCE = 500; // 5%
    uint256 public constant MAX_SLIPPAGE_TOLERANCE = 10000; // 100%

    uint256 public sellCooldownPeriod = 1 minutes;
    uint256 public constant MAX_COOLDOWN_PERIOD = 5 minutes;
    mapping(address => uint256) public lastBuyTimestamp;

    modifier validateTokenOperation(address virusAddress) {
        require(
            tokens[virusAddress] == TokenState.ACTIVE,
            "Token not found or not available in ACTIVE"
        );
        _;
    }

    struct FeeBreakdown {
        uint256 totalBasicFee;
        uint256 winnerPotFee;
        uint256 devFee;
    }

    function createToken(
        string memory name,
        string memory symbol
    ) external onlyOwner onlyBeforeGame returns (address) {
        require(nextVirusId < 30, "Maximum number of viruses reached");
        IUniswapV2Router02 router = IUniswapV2Router02(UNISWAP_V2_ROUTER);
        Virus token = new Virus(
            name,
            symbol,
            0,
            address(rewardWinnerPot),
            UNISWAP_V2_FACTORY,
            UNISWAP_V2_ROUTER,
            address(infectionManager),
            payable(address(rewardFirstInfection)),
            address(gameManager),
            address(devAddress),
            address(rewardWinnerPot),
            router.WETH(),
            address(virusDrop)
        );
        tokens[address(token)] = TokenState.ACTIVE;
        nextVirusId++;

        allTokens.push(address(token));

        return address(token);
    }

    function buy(
        address virusAddress,
        uint256 virusAmount,
        bytes32[] calldata merkleProof
    ) external payable validateTokenOperation(virusAddress) onlyDuringGame nonReentrant {
        if (block.timestamp < whitelistEndTime) {
            require(isWhitelisted(msg.sender, merkleProof), "Not whitelisted");
        }

        require(virusAmount > 0, "Amount must be greater than 0");
        require(virusAmount % DECIMALS == 0, "Amount must be a whole number");
        
        Virus token = Virus(virusAddress);
        require(
            token.totalSupply() + virusAmount <= SUPPLY_THRESHOLD,
            "Purchase would exceed supply threshold"
        );
        
        uint requiredEth = _calculateTokenPrice(
            virusAddress,
            virusAmount,
            true
        );

        (
            uint baseFee,
            uint firstInfectedFee,
            address firstInfector
        ) = _calculateBuyFeesAndCreateNoInfection(msg.sender, requiredEth);
        uint totalETHRequired = requiredEth + baseFee + firstInfectedFee;

        require(msg.value >= totalETHRequired, "Insufficient ETH sent");

        if (block.timestamp < whitelistEndTime) {
            uint256 newTotalPurchase = whitelistPurchases[msg.sender] + totalETHRequired;
            require(newTotalPurchase <= WHITELIST_MAX_PURCHASE, "Exceeds whitelist purchase limit");
            whitelistPurchases[msg.sender] = newTotalPurchase;
        }

        collateral[virusAddress] += requiredEth;
        token.mint(msg.sender, virusAmount);

        if (token.totalSupply() >= SUPPLY_THRESHOLD) {
            _enableUniswap(virusAddress);
        }

        if (firstInfectedFee > 0) {
            rewardFirstInfection.deposit{value: firstInfectedFee}(
                firstInfector
            );
        }

        if (msg.value > totalETHRequired) {
            (bool success, ) = payable(msg.sender).call{
                value: msg.value - totalETHRequired
            }("");
            require(success, "ETH return failed");
        }

        lastBuyTimestamp[msg.sender] = block.timestamp;
    }

    function sell(
        address virusAddress,
        uint256 virusAmount,
        uint256 minAmountOut
    ) external validateTokenOperation(virusAddress) onlyDuringGame nonReentrant {
        require(virusAmount > 0, "Amount must be greater than 0");
        require(virusAmount % DECIMALS == 0, "Amount must be a whole number");
        require(
            block.timestamp >= lastBuyTimestamp[msg.sender] + sellCooldownPeriod,
            "Sell cooldown period not elapsed"
        );

        
        Virus token = Virus(virusAddress);
        require(
            token.balanceOf(msg.sender) >= virusAmount,
            "Insufficient token balance"
        );
        require(
            token.allowance(msg.sender, address(this)) >= virusAmount,
            "Please approve tokens before selling"
        );
        
        uint256 sellPrice = _calculateTokenPrice(
            virusAddress,
            virusAmount,
            false
        );
        uint256 fee = _calculateAndDistributeSellFees(sellPrice);
        uint256 netAmount = sellPrice - fee;

        require(netAmount >= minAmountOut, "Output amount below minimum");
        require(
            collateral[virusAddress] >= netAmount,
            "Insufficient collateral for this virus"
        );

        collateral[virusAddress] -= sellPrice;
        token.transferFrom(msg.sender, address(this), virusAmount);
        token.burn(virusAmount);
        (bool success, ) = payable(msg.sender).call{value: netAmount}("");
        require(success, "ETH transfer failed");
    }

    function afterGameEndsUniswapAdded(uint256 batchSize) external onlyAfterGame {
        require(!allTokensUniswapEnabled, "All tokens already Uniswap enabled");
        require(batchSize > 0, "Batch size must be greater than 0");

        uint256 startIndex = lastProcessedIndex;
        uint256 endIndex = Math.min(startIndex + batchSize, allTokens.length);

        for (uint i = startIndex; i < endIndex; i++) {
            address virusAddress = allTokens[i];
            if (
                tokens[virusAddress] == TokenState.ACTIVE &&
                collateral[virusAddress] > 0
            ) {
                _enableUniswap(virusAddress);
            }

            if (
                tokens[virusAddress] == TokenState.ACTIVE &&
                collateral[virusAddress] == 0
            ) {
                tokens[virusAddress] = TokenState.UNISWAP_ENABLED;
            }

            lastProcessedIndex = i + 1;
        }

        if (lastProcessedIndex == allTokens.length) {
            allTokensUniswapEnabled = true;
        }
    }

    function _createLiquidityPool(
        address virusAddress
    ) internal returns (address) {
        IUniswapV2Factory factory = IUniswapV2Factory(UNISWAP_V2_FACTORY);
        IUniswapV2Router02 router = IUniswapV2Router02(UNISWAP_V2_ROUTER);
        
        address pair = factory.getPair(virusAddress, router.WETH());
        
        if (pair == address(0)) {
            pair = factory.createPair(virusAddress, router.WETH());
        }
        
        return pair;
    }

    function _provideLiquidity(
        address virusAddress,
        uint256 tokenAmount,
        uint256 ethAmount
    ) internal returns (uint) {
        Virus token = Virus(virusAddress);
        IUniswapV2Router02 router = IUniswapV2Router02(UNISWAP_V2_ROUTER);
        
        token.approve(UNISWAP_V2_ROUTER, tokenAmount);
        
        uint256 slippageBps = getSlippageTolerance(virusAddress);
        uint256 minTokenAmount = tokenAmount * (10000 - slippageBps) / 10000;
        uint256 minEthAmount = ethAmount * (10000 - slippageBps) / 10000;
        
        (uint256 amountToken,, uint liquidity) = router.addLiquidityETH{value: ethAmount}(
            virusAddress,
            tokenAmount,
            minTokenAmount,
            minEthAmount,
            address(this),
            block.timestamp
        );
        
        if (amountToken < tokenAmount) {
            uint256 unusedTokens = tokenAmount - amountToken;
            token.burn(unusedTokens);
        }
        
        token.approve(UNISWAP_V2_ROUTER, 0);
        
        return liquidity;
    }

    function _burnLpTokens(address poolAddress, uint256 amount) internal {
        IUniswapV2Pair pool = IUniswapV2Pair(poolAddress);
        pool.transfer(address(0), amount);
    }

    function _calculateBasicFee(
        uint256 baseAmount
    ) internal pure returns (FeeBreakdown memory) {
        uint256 totalBasicFee = (baseAmount * FEE_PERCENTAGE) / DECIMALS;
        
        uint256 winnerPotFee = (totalBasicFee * WINNER_POT_SHARE) / ALL_SHARE;
        uint256 devFee = totalBasicFee - winnerPotFee;

        return FeeBreakdown({
            totalBasicFee: totalBasicFee,
            winnerPotFee: winnerPotFee,
            devFee: devFee
        });
    }

    function _distributeFees(FeeBreakdown memory fees) internal {
        if (fees.winnerPotFee > 0) {
            (bool success, ) = address(rewardWinnerPot).call{value: fees.winnerPotFee}("");
            require(success, "Winner pot fee transfer failed");
        }

        if (fees.devFee > 0) {
            require(
                address(this).balance >= fees.devFee,
                "Insufficient balance for dev fee"
            );
            (bool success, ) = devAddress.call{value: fees.devFee}("");
            require(success, "Dev fee transfer failed");
        }
    }

    function _calculateAndDistributeFees(uint256 baseAmount) internal returns (uint256) {
        FeeBreakdown memory fees = _calculateBasicFee(baseAmount);
        _distributeFees(fees);
        return fees.totalBasicFee;
    }

    function _calculateBuyFeesAndCreateNoInfection(
        address user,
        uint256 baseAmount
    )
        internal
        returns (
            uint baseFee,
            uint firstInfectedFee,
            address firstInfectorAddress
        )
    {
        baseFee = _calculateAndDistributeFees(baseAmount);

        (address firstInfector, , bool isActive) = infectionManager
            .getFirstInfection(user);

        firstInfectedFee = (isActive && firstInfector != address(0))
            ? (baseAmount * INFECTED_FEE_PERCENTAGE) / DECIMALS
            : 0;

        return (baseFee, firstInfectedFee, firstInfector);
    }

    function _calculateAndDistributeSellFees(uint256 baseAmount) internal returns (uint) {
        return _calculateAndDistributeFees(baseAmount);
    }

    function _calculateBuyPrice(
        uint256 totalSupply,
        uint256 numTokens
    ) internal pure returns (uint) {
        uint256 finalSupply = totalSupply + numTokens;
        return _curveIntegral(finalSupply) - _curveIntegral(totalSupply);
    }

    function _calculateSellPrice(
        uint256 totalSupply,
        uint256 numTokens
    ) internal pure returns (uint256) {
        uint256 finalSupply = totalSupply - numTokens;
        return _curveIntegral(totalSupply) - _curveIntegral(finalSupply);
    }

    // Add these helper functions
    function _curveIntegral(uint256 _x) internal pure returns (uint256) {
        uint256 scaledX = _x / DECIMALS;
        return ((scaledX * scaledX) / 400) + scaledX;
    }

    function _calculateTokenPrice(
        address virusAddress,
        uint virusAmount,
        bool isBuy
    ) internal view returns (uint) {
        Virus token = Virus(virusAddress);
        uint currentSupply = token.totalSupply();

        if (isBuy) {
            return _calculateBuyPrice(currentSupply, virusAmount);
        } else {
            require(
                currentSupply >= virusAmount,
                "Cannot sell more than total supply"
            );
            return _calculateSellPrice(currentSupply, virusAmount);
        }
    }

    function _enableUniswap(address virusAddress) internal {
        require(
            tokens[virusAddress] == TokenState.ACTIVE,
            "Token must be in ACTIVE state"
        );

        tokens[virusAddress] = TokenState.UNISWAP_ENABLED;
        emit TokenStateChanged(virusAddress, TokenState.UNISWAP_ENABLED);

        Virus token = Virus(virusAddress);
        uint liquidityTokenAmount = MAX_SUPPLY - SUPPLY_THRESHOLD;

        token.mint(address(this), liquidityTokenAmount);

        address pool = _createLiquidityPool(virusAddress);
        uint liquidity = _provideLiquidity(
            virusAddress,
            liquidityTokenAmount,
            collateral[virusAddress]
        );

        _burnLpTokens(pool, liquidity);
    }

    function _calculateFeePercentage(address userAddress) internal view returns (uint256) {
        (address firstInfector, , bool isActive) = infectionManager.getFirstInfection(
            userAddress
        );
        
        uint256 feePercentage = FEE_PERCENTAGE;
        if (isActive && firstInfector != address(0)) {
            feePercentage += INFECTED_FEE_PERCENTAGE;
        }
        
        return feePercentage;
    }

    function getBuyVirusPrice(
        address virusAddress,
        address userAddress,
        uint virusAmount
    ) external view returns (uint256 baseAmount, uint256 fee) {
        require(
            tokens[virusAddress] != TokenState.NOT_CREATED,
            "Token does not exist"
        );

        baseAmount = _calculateTokenPrice(
            virusAddress,
            virusAmount,
            true
        );

        fee = _calculateBasicFee(baseAmount).totalBasicFee;
        (address firstInfector, , bool isActive) = infectionManager
            .getFirstInfection(userAddress);

        uint256 firstInfectedFee = (isActive && firstInfector != address(0))
            ? (baseAmount * INFECTED_FEE_PERCENTAGE) / DECIMALS
            : 0;
        fee += firstInfectedFee;
        return (baseAmount, fee);
    }

    function getBuyVirusPriceFromETH(
        address virusAddress,
        address userAddress,
        uint256 ethAmount
    ) external view returns (
        uint256 virusAmount,
        uint256 basicAmount,
        uint256 fee
    ) {
        require(
            tokens[virusAddress] != TokenState.NOT_CREATED,
            "Token does not exist"
        );

        uint256 feePercentage = _calculateFeePercentage(userAddress);
        uint256 totalMultiplier = DECIMALS + feePercentage;

        uint256 left = 0;
        uint256 right = 1e36;
        
        while (left < right - 1) {
            uint256 mid = (left + right) / 2;
            uint256 price = _calculateTokenPrice(virusAddress, mid, true);
            uint256 totalPrice = (price * totalMultiplier) / DECIMALS;
            
            if (totalPrice <= ethAmount) {
                left = mid;
            } else {
                right = mid;
            }
        }

        virusAmount = (left / 1e18) * 1e18;
        require(virusAmount > 0, "Amount too small");

        (basicAmount, fee) = this.getBuyVirusPrice(virusAddress, userAddress, virusAmount);

        return (virusAmount, basicAmount, fee);
    }

    function getSellVirusPrice(
        address virusAddress,
        uint virusAmount
    ) external view returns (uint256 priceIncludedFees, uint256 fee) {
        require(
            tokens[virusAddress] != TokenState.NOT_CREATED,
            "Token does not exist"
        );

        priceIncludedFees = _calculateTokenPrice(
            virusAddress,
            virusAmount,
            false
        );

        uint256 feePercentage = FEE_PERCENTAGE;

        fee = (priceIncludedFees * feePercentage) / DECIMALS;
        return (priceIncludedFees, fee);
    }

    function getAllTokens() external view returns (address[] memory) {
        return allTokens;
    }

    function getTokenCount() external view returns (uint256) {
        return allTokens.length;
    }

    receive() external payable {
        accumulatedEth += msg.value;
    }

    function withdrawAccumulatedEth() external onlyOwner {
        uint256 amount = accumulatedEth;
        accumulatedEth = 0;
        
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "ETH withdrawal failed");
    }

    function isVirusToken(address token) external view returns (bool) {
        return tokens[token] != TokenState.NOT_CREATED;
    }

    function setCustomSlippageTolerance(
        address virusAddress,
        uint256 slippageBps
    ) external onlyOwner {
        require(tokens[virusAddress] != TokenState.NOT_CREATED, "Token does not exist");
        require(slippageBps <= MAX_SLIPPAGE_TOLERANCE, "Slippage too high");
        
        customSlippageTolerances[virusAddress] = slippageBps;
    }

    function getSlippageTolerance(address virusAddress) public view returns (uint256) {
        uint256 customTolerance = customSlippageTolerances[virusAddress];
        return customTolerance > 0 ? customTolerance : DEFAULT_SLIPPAGE_TOLERANCE;
    }

    function setWhitelistEndTime(uint256 _endTime) external onlyOwner onlyBeforeGame {
        require(_endTime > block.timestamp, "End time must be in the future");
        whitelistEndTime = _endTime;
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner onlyBeforeGame {
        merkleRoot = _merkleRoot;
    }

    function isWhitelisted(address account, bytes32[] calldata proof) public view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(account));
        return MerkleProof.verify(proof, merkleRoot, leaf);
    }

    function isWhitelistPeriod() public view returns (bool) {
        return block.timestamp < whitelistEndTime;
    }

    function setSellCooldownPeriod(uint256 newPeriod) external onlyOwner {
        require(newPeriod <= MAX_COOLDOWN_PERIOD, "Cooldown period too long");
        sellCooldownPeriod = newPeriod;
    }
}
