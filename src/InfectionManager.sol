// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./interfaces/ITransactionType.sol";
import "./abstracts/GameAware.sol";
import "./VirusFactory.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract InfectionManager is GameAware, Ownable {
    enum TransactionType {
        NORMAL_TRANSFER,
        TOKEN_PURCHASE,
        TOKEN_SELL
    }

    struct FirstInfection {
        address infector;
        address virusAddress;
        bool isActive;
    }
    
    struct ActiveInfection {
        address infector;
        address virusAddress;
        bool isActive;
        uint256 infectionOrder;
    }

    address payable public virusFactory;
    bool public isVirusFactorySet;
    uint256 public constant ACTIVE_WALLET_CONDITION = 0.005 ether;
    uint256 public constant MAX_VIRUS_COUNT = 30;
    uint256 public constant MIN_INFECTION_AMOUNT = 1000 * 10**18;

    mapping(address => bool) public registeredViruses;
    mapping(address => address[3]) public topInfectorsByVirus;

    //// Wallet Infection Status ////
    // Wallet's first infection status
    mapping(address => FirstInfection) public firstInfection;
    // Wallet's current active infection status
    mapping(address => ActiveInfection) public activeInfection;


    //// Wallet Info ////
    mapping(address => mapping(address => ActiveInfection)) public activeInfectorHistory; // wallet => virusAddress => infector
    mapping(address => uint256) public activeInfectorHistoryUniqueSum; // wallet => Sum of unique infections caused

    //// Spreader Status ////
    // Infection count by virus
    mapping(address => uint256) public activeInfectionCountByVirusContract;
    // Infection count by virus by infector
    mapping(address => mapping(address => uint256)) public infectorSuccessCount; // virusAddress => infector => count
    // Add a mapping that maintains a FirstInfection count for each infector
    mapping(address => mapping(address => uint256)) public firstInfectionCountByInfector; // virusAddress => infector => count

    event TopInfectorUpdated(
        address indexed virusAddress,
        address indexed infector,
        uint256 newCount,
        uint256 rank
    );

    event FirstInfectionInitialized(
        address indexed victim,
        address indexed virusAddress,
        address indexed infector,
        uint256 timestamp
    );

    event ActiveInfectionSet(
        address indexed victim,
        address indexed infector,
        address indexed virusAddress,
        uint256 infectionOrder,
        uint256 timestamp
    );

    event InfectionReset(
        address indexed victim,
        uint256 timestamp
    );

    event InfectionCountUpdated(
        address indexed virusAddress,
        address indexed infector,
        uint256 newCount,
        bool isIncrement,
        uint256 timestamp
    );

    event VirusInfectionCountUpdated(
        address indexed virusContract,
        uint256 count,
        uint256 timestamp
    );

    constructor(
        address _gameManager
    ) GameAware(_gameManager) Ownable(msg.sender) {}

    function setVirusFactory(address _virusFactory) external onlyOwner {
        require(!isVirusFactorySet, "Virus factory already set");
        require(_virusFactory != address(0), "Invalid virus factory address");
        virusFactory = payable(_virusFactory);
        isVirusFactorySet = true;

        address[] memory existingTokens = VirusFactory(payable(_virusFactory))
            .getAllTokens();
        require(
            existingTokens.length <= MAX_VIRUS_COUNT,
            "Too many existing viruses"
        );

        for (uint i = 0; i < existingTokens.length; i++) {
            registeredViruses[existingTokens[i]] = true;
        }
    }

    function tryInfect(
        address infector,
        address victim,
        uint256 newAmount,
        TransactionType txType
    ) external returns (bool) {
        address virusAddress = msg.sender;
        require(registeredViruses[virusAddress], "Not a registered virus");
        

        // Returns false if out of game period
        if (!gameManager.isGameActive()) {
            return false;
        }

        if (newAmount < MIN_INFECTION_AMOUNT) {
            return false;
        }

        if (txType == TransactionType.TOKEN_PURCHASE) {
            // Update the infection status of the victim's address
            if (!_activeWalletCheck(victim)) {
                return false;
            }

            // If there is no FirstInfection, create one.
            _initializeFirstInfection(infector, victim, virusAddress);
            // victim increase itself  the virus balance.
            _processTryActiveInfection(infector, victim, newAmount, true);
            
        } else if (txType == TransactionType.TOKEN_SELL) {
            // Update the infection status of the victim's address
            // infector decrease itself (Infector, infector, ...) the virus balance.
            _processTryActiveInfection(infector, infector, newAmount, false);
        } else {
            _processTryActiveInfection(infector, infector, newAmount, false);
            // Update the address of the victim and the infection status of the token increase side.
            if (!_activeWalletCheck(victim)) {
                return false;
            }
            // If there is no FirstInfection, create one.
            _initializeFirstInfection(infector, victim, virusAddress);
            _processTryActiveInfection(infector, victim, newAmount, true);
        }

        return true;
    }

    function _activeWalletCheck(address victim) private view returns (bool) {
        if (!_isEoaContract(victim)) {
            return false;
        }
        return (victim.balance >= ACTIVE_WALLET_CONDITION) || (firstInfection[victim].isActive);
    }

    function _initializeFirstInfection(address infector, address victim, address virusAddress) private {
        if (!firstInfection[victim].isActive) {
            if (infector == victim) {
                firstInfection[victim] = FirstInfection({
                    infector: address(0),
                    virusAddress: address(0),
                    isActive: true
                });        
            } else {
                firstInfection[victim] = FirstInfection({
                    infector: infector,
                    virusAddress: virusAddress,
                    isActive: true
                });
                firstInfectionCountByInfector[virusAddress][infector]++;
            }
            emit FirstInfectionInitialized(victim, virusAddress, infector, block.timestamp);
        }
    }

    function _processTryActiveInfection(
        address infector,
        address victim,
        uint256 newAmount,
        bool isPlus
    ) internal {
        address targetVirusAddress = msg.sender;
        address activeVirusAddress = activeInfection[victim].virusAddress;
        if (isPlus) {
            // If you are infected with the same virus, the number of infections will not be updated.
            if (activeVirusAddress != targetVirusAddress) {
                uint256 currentInfectionVirusBalance = 0;
                if (activeVirusAddress != address(0)) {
                    currentInfectionVirusBalance = IERC20(activeVirusAddress).balanceOf(victim);
                }

                uint256 targetVirusBalance = 0;
                if (targetVirusAddress != address(0)) {
                    uint256 currentTargetVirusBalance = IERC20(targetVirusAddress).balanceOf(victim);
                    require(newAmount <= type(uint256).max - currentTargetVirusBalance, "Overflow would occur");
                    targetVirusBalance = currentTargetVirusBalance + newAmount;
                }
                
                if (currentInfectionVirusBalance < targetVirusBalance) {
                    ActiveInfection memory oldActiveInfection = activeInfection[victim];
                    if (oldActiveInfection.virusAddress != address(0)) {
                        _updateInfectionCounts(oldActiveInfection, false);
                    }
                    
                    _setNewActiveInfection(
                        victim,
                        infector,
                        targetVirusAddress,
                        ++activeInfectorHistoryUniqueSum[victim]
                    );
                    activeInfectorHistory[victim][targetVirusAddress] = activeInfection[victim];

                    _updateInfectionCounts(activeInfection[victim], true);
                    _updateTopInfectors(targetVirusAddress, infector);
                }
            }
        } else {
            if (activeVirusAddress == targetVirusAddress) {
                address[] memory allVirusAddresses = VirusFactory(virusFactory).getAllTokens();
                
                // Maximum holding capacity and tracking of tokens
                uint256 maxBalance = 0;
                address maxBalanceVirusAddress = address(0);
                
                // Check the amount of each virus held.
                for (uint i = 0; i < allVirusAddresses.length; i++) {
                    address virusAddress = allVirusAddresses[i];
                    if (!registeredViruses[virusAddress]) continue;
                    
                    uint256 balance = IERC20(virusAddress).balanceOf(victim);
                    // In the case of targetVirusAddress, subtract the amount
                    if (virusAddress == targetVirusAddress) {
                        balance -= newAmount;
                    }
                    
                    // Updated maximum holding amount
                    if (balance > maxBalance) {
                        maxBalance = balance;
                        maxBalanceVirusAddress = virusAddress;
                    } else if (balance == maxBalance && maxBalanceVirusAddress != address(0)) {
                        // In the case of the same balance, the one with the larger (more recent) infectionOrder takes priority.
                        uint256 currentInfectionOrder = activeInfectorHistory[victim][allVirusAddresses[i]].infectionOrder;
                        uint256 maxInfectionOrder = activeInfectorHistory[victim][maxBalanceVirusAddress].infectionOrder;
                        
                        if (currentInfectionOrder > maxInfectionOrder) {
                            maxBalanceVirusAddress = virusAddress;
                        }
                    }
                }
                
                if (maxBalanceVirusAddress != address(0)) {
                    ActiveInfection memory oldActiveInfection = activeInfection[victim];
                    _updateInfectionCounts(oldActiveInfection, false);

                    if (maxBalance == 0) {
                        _resetActiveInfection(victim);
                    } else {
                        address newInfector = activeInfectorHistory[victim][maxBalanceVirusAddress].infector;
                        _setNewActiveInfection(
                            victim,
                            newInfector,
                            maxBalanceVirusAddress,
                            ++activeInfectorHistoryUniqueSum[victim]
                        );
                        _updateInfectionCounts(activeInfection[victim], true);
                    }

                    // Update top infectors rankings
                    _updateTopInfectorsRankings(
                        oldActiveInfection,
                        maxBalanceVirusAddress,
                        activeInfectorHistory[victim][maxBalanceVirusAddress].infector
                    );
                } else {
                    _resetActiveInfection(victim);
                }
            }
        }
    }

    function _updateTopInfectors(
        address virusAddress,
        address infector
    ) internal {
        if (infector == address(0)) {
            return;
        }

        uint256 newCount = infectorSuccessCount[virusAddress][infector];
        address[3] storage topAddresses = topInfectorsByVirus[virusAddress];

        // Check if infector is already in top 3
        for (uint256 i = 0; i < 3; i++) {
            if (topAddresses[i] == infector) {
                return;
            }
        }

        // Find first empty slot or the slot with lowest count
        uint256 lowestCount = type(uint256).max;
        uint256 lowestCountIndex = 3;

        for (uint256 i = 0; i < 3; i++) {
            if (topAddresses[i] == address(0)) {
                // Found empty slot
                topAddresses[i] = infector;
                emit TopInfectorUpdated(virusAddress, infector, newCount, i + 1);
                return;
            }
            uint256 currentCount = infectorSuccessCount[virusAddress][topAddresses[i]];
            if (currentCount < lowestCount) {
                lowestCount = currentCount;
                lowestCountIndex = i;
            }
        }

        // Replace the lowest count if new count is higher
        if (newCount > lowestCount && lowestCountIndex < 3) {
            topAddresses[lowestCountIndex] = infector;
            emit TopInfectorUpdated(virusAddress, infector, newCount, lowestCountIndex + 1);
        }
    }

    // Obtain active infection for specified address
    function getActiveInfection(
        address victim
    ) external view returns (ActiveInfection memory) {
        return activeInfection[victim];
    }

    // Get the current infection status of the specified address
    function getCurrentInfection(
        address victim
    )
        external
        view
        returns (
            address infector,
            address virusAddress,
            bool isActive
        )
    {
        ActiveInfection memory infection = activeInfection[victim];
        return (
            infection.infector,
            infection.virusAddress,
            infection.isActive
        );
    }

    function getFirstInfection(
        address victim
    )
        external
        view
        returns (
            address infector,
            address virusAddress,
            bool isActive
        )
    {
        FirstInfection memory infection = firstInfection[victim];
        return (
            infection.infector,
            infection.virusAddress,
            infection.isActive
        );
    }

    function getActiveInfectionCountByVirusContract(
        address virusAddress
    ) external view returns (uint256) {
        require(registeredViruses[virusAddress], "Not a registered virus");
        return activeInfectionCountByVirusContract[virusAddress];
    }

    function getAllActiveInfectionCounts()
        external
        view
        returns (address[] memory, uint256[] memory)
    {
        // Get all tokens from virus factory
        address[] memory allVirusAddresses = VirusFactory(virusFactory).getAllTokens();
        
        // Create arrays of the same size as allTokens
        address[] memory virusAddresses = new address[](allVirusAddresses.length);
        uint256[] memory counts = new uint256[](allVirusAddresses.length);
        uint256 currentIndex = 0;

        // Iterate through all registered viruses
        for (uint256 i = 0; i < allVirusAddresses.length; i++) {
            address virusAddress = allVirusAddresses[i];
            if (registeredViruses[virusAddress]) {
                virusAddresses[currentIndex] = virusAddress;
                counts[currentIndex] = activeInfectionCountByVirusContract[virusAddress];
                currentIndex++;
            }
        }

        address[] memory finalAddresses = new address[](currentIndex);
        uint256[] memory finalCounts = new uint256[](currentIndex);
        
        for (uint256 i = 0; i < currentIndex; i++) {
            finalAddresses[i] = virusAddresses[i];
            finalCounts[i] = counts[i];
        }

        return (finalAddresses, finalCounts);
    }

    function getInfectorSuccessCount(
        address virusAddress,
        address infector
    ) external view returns (uint256) {
        return infectorSuccessCount[virusAddress][infector];
    }

    function getInfectorSuccessCountMulti(
        address infector
    ) external view returns (uint256[] memory) {
        address[] memory allVirusAddresses = VirusFactory(virusFactory).getAllTokens();
        uint256[] memory counts = new uint256[](allVirusAddresses.length);
        
        for (uint256 i = 0; i < allVirusAddresses.length; i++) {
            counts[i] = infectorSuccessCount[allVirusAddresses[i]][infector];
        }
        return counts;
    }

    function getFirstInfectionCount(
        address virusAddress,
        address infector
    ) external view returns (uint256) {
        return firstInfectionCountByInfector[virusAddress][infector];
    }

    function getFirstInfectionCountMulti(
        address infector
    ) external view returns (uint256[] memory) {
        address[] memory allVirusAddresses = VirusFactory(virusFactory).getAllTokens();
        uint256[] memory counts = new uint256[](allVirusAddresses.length);
        
        for (uint256 i = 0; i < allVirusAddresses.length; i++) {
            counts[i] = firstInfectionCountByInfector[allVirusAddresses[i]][infector];
        }
        return counts;
    }

    function getTopInfectors(
        address virusAddress
    ) external view returns (address[3] memory, uint256[3] memory) {
        address[3] memory addresses = topInfectorsByVirus[virusAddress];
        uint256[3] memory counts;
        
        for (uint256 i = 0; i < 3; i++) {
            counts[i] = infectorSuccessCount[virusAddress][addresses[i]];
        }
        
        for (uint256 i = 0; i < 2; i++) {
            for (uint256 j = 0; j < 2 - i; j++) {
                if (counts[j] < counts[j + 1]) {
                    
                    uint256 tempCount = counts[j];
                    counts[j] = counts[j + 1];
                    counts[j + 1] = tempCount;
                    
                    address tempAddr = addresses[j];
                    addresses[j] = addresses[j + 1];
                    addresses[j + 1] = tempAddr;
                }
            }
        }
        
        return (addresses, counts);
    }

    function _updateInfectionCounts(
        ActiveInfection memory infection,
        bool isIncrement
    ) private {
        if (infection.isActive && infection.virusAddress != address(0)) {
            if (isIncrement) {
                _incrementActiveInfectionCount(infection.virusAddress);
                infectorSuccessCount[infection.virusAddress][infection.infector]++;
            } else {
                if (activeInfectionCountByVirusContract[infection.virusAddress] > 0) {
                    _decrementActiveInfectionCount(infection.virusAddress);
                }
                if (infectorSuccessCount[infection.virusAddress][infection.infector] > 0) {
                    infectorSuccessCount[infection.virusAddress][infection.infector]--;
                }
            }

            emit InfectionCountUpdated(
                infection.virusAddress,
                infection.infector,
                infectorSuccessCount[infection.virusAddress][infection.infector],
                isIncrement,
                block.timestamp
            );
        }
    }

    function _resetActiveInfection(address victim) private {
        activeInfection[victim] = ActiveInfection({
            infector: address(0),
            virusAddress: address(0),
            isActive: false,
            infectionOrder: 0
        });

        emit InfectionReset(victim, block.timestamp);
    }

    function _setNewActiveInfection(
        address victim,
        address infector,
        address virusAddress,
        uint256 infectionOrder
    ) private {
        activeInfection[victim] = ActiveInfection({
            infector: infector,
            virusAddress: virusAddress,
            isActive: true,
            infectionOrder: infectionOrder
        });

        emit ActiveInfectionSet(
            victim,
            infector,
            virusAddress,
            infectionOrder,
            block.timestamp
        );
    }

    function _updateTopInfectorsRankings(
        ActiveInfection memory oldInfection,
        address maxBalanceVirusAddress,
        address newInfector
    ) private {
        _updateTopInfectors(
            oldInfection.virusAddress,
            oldInfection.infector
        );
        _updateTopInfectors(
            maxBalanceVirusAddress,
            newInfector
        );
    }

    function _isEoaContract(address account) private view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size == 0;
    }

    function _incrementActiveInfectionCount(address virusContract) internal {
        activeInfectionCountByVirusContract[virusContract]++;
        emit VirusInfectionCountUpdated(
            virusContract,
            activeInfectionCountByVirusContract[virusContract],
            block.timestamp
        );
    }

    function _decrementActiveInfectionCount(address virusContract) internal {
        if (activeInfectionCountByVirusContract[virusContract] > 0) {
            activeInfectionCountByVirusContract[virusContract]--;
            emit VirusInfectionCountUpdated(
                virusContract,
                activeInfectionCountByVirusContract[virusContract],
                block.timestamp
            );
        }
    }
}
