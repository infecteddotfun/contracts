// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {GameManager} from "../src/GameManager.sol";
import {InfectionManager} from "../src/InfectionManager.sol";
import {RewardWinnerPot} from "../src/RewardWinnerPot.sol";
import {RewardFirstInfection} from "../src/RewardFirstInfection.sol";
import {VirusFactory} from "../src/VirusFactory.sol";
import {VirusDrop} from "../src/VirusDrop.sol";
import "@uniswap-v2-core-1.0.1/contracts/interfaces/IUniswapV2Factory.sol";

contract DeployInfected is Script {
    // Define merkle root as a constant
    bytes32 constant WHITELIST_MERKLE_ROOT =
        0xf1517bc31b936e2b102afb8d87bef8f1b8d5b2d7cc33b5ca6f10fe0bcc4d5982;

    function run() public returns (GameManager) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        uint256 startTime = 1740416400;
        address uniswapFactory = 0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6;
        address uniswapRouter = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
        address devAddress = 0x9c659Ebae0bF0279ACD570e82E86073FA5afc613; // Multi-sig address
        address weth = 0x4200000000000000000000000000000000000006;

        VirusDrop virusDrop = new VirusDrop();
        GameManager gameManager = new GameManager(startTime);
        InfectionManager infectionManager = new InfectionManager(
            address(gameManager)
        );
        RewardWinnerPot rewardWinnerPot = new RewardWinnerPot(
            address(uniswapFactory),
            address(uniswapRouter),
            address(gameManager),
            address(infectionManager),
            address(weth)
        );

        RewardFirstInfection rewardFirstInfection = new RewardFirstInfection(
            address(gameManager)
        );

        VirusFactory virusFactory = new VirusFactory(
            address(gameManager),
            address(infectionManager),
            payable(address(rewardWinnerPot)),
            payable(address(rewardFirstInfection)),
            address(uniswapFactory),
            address(uniswapRouter),
            address(devAddress),
            address(virusDrop)
        );

        virusFactory.setWhitelistEndTime(startTime + 30 minutes);
        virusFactory.setMerkleRoot(WHITELIST_MERKLE_ROOT);
        rewardWinnerPot.setVirusFactory(address(virusFactory));
        rewardFirstInfection.setVirusFactory(address(virusFactory));
        string[30] memory names = [
            "COVID-19",
            "HIV/AIDS",
            "Influenza",
            "SARS",
            "Bird Flu",
            "Pig Flu",
            "Ebola",
            "Rabies",
            "Malaria",
            "Tuberculosis",
            "Measles",
            "Dengue Fever",
            "Smallpox",
            "Monkeypox",
            "Hepatitis B",
            "Hepatitis C",
            "Polio",
            "Cholera",
            "Zika",
            "Plague (Black Death)",
            "Yellow Fever",
            "Norovirus",
            "Tetanus",
            "MERS",
            "Herpes",
            "West Nile Virus",
            "Anthrax",
            "Diphtheria",
            "Pneumonia",
            "Brain-eating Amoeba"
        ];

        string[30] memory symbols = [
            "COVID",
            "HIV",
            "INFLUENZA",
            "SARS",
            "BIRDFLU",
            "PIGFLU",
            "EBOLA",
            "RABIES",
            "MALARIA",
            "TUBERCULOSIS",
            "MEASLES",
            "DENGUE",
            "SMALLPOX",
            "MONKEYPOX",
            "HEPATITISB",
            "HEPATITISC",
            "POLIO",
            "CHOLERA",
            "ZIKA",
            "PLAGUE",
            "YELLOWFEVER",
            "NOROVIRUS",
            "TETANUS",
            "MERS",
            "HERPES",
            "WNV",
            "ANTHRAX",
            "DIPHTHERIA",
            "PNEUMONIA",
            "BRAINEAT"
        ];

        address[] memory virusTokens = new address[](30);

        // Create virus tokens
        for (uint i = 0; i < 30; i++) {
            address virus = virusFactory.createToken(names[i], symbols[i]);
            virusTokens[i] = virus;
        }

        infectionManager.setVirusFactory(address(virusFactory));

        vm.stopBroadcast();
        return gameManager;
    }
}
