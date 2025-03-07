# Infected 🦠

## Overview

The game is simple: 30 deadly viruses (ERC20) compete to infect the most population on the Base chain during a 7 day period. Spread the virus, Dominate the infection charts, and claim the winner pot. It's a simulation of the pandemic warfare on chain.

## Game Details

### 🔬 Infection Mechanics

#### Infecting People:
- Target wallets must have 0.005+ ETH ("Live People")
- Minimum 1000 virus tokens required to infect
- One virus per address - highest token amount wins

#### Super Spreaders:
- Top 3 spreaders of each virus earn the "Super Spreader" badge and featured on the leaderboard.

### 💰 Reward System

#### Winner Rewards:
1.5% trading fee goes to winner pot, distributed as:
- 34% to Super Spreaders (17%/10%/7% each)
- 66% to winning virus holders

#### First Infector Reward:
First to infect earns 1% of tx value on target's future virus purchases - for life.

### 🪙 Token Information
- 30 virus tokens available
- 100 billion total supply each (Bonding Curve at 67 billion and Uniswap listing at 33 billion)

### FAQ

Q. How much is the protocol fee?
- We take 1% trading fee during the game, and 0.5% after the game ends.

Q. Who will receive the first infector reward if I have already bought some virus tokens before others infect me?
- There won't be infector rewards. So you don't have to pay extra fee when buying a virus token.

Q. What happens if I sell all the viruses?
- If you sold all the virus tokens and hold 0 virus token, your infected status is "None".

Q. Is the chat for each virus token gated or visible for anyone?
- The chat box for each virus is accessible to anyone, just like the general chat.

Q. Can I create a new population by creating new wallets with 0.005+ ETH in them?
- Yes, ETH count will be tracked when virus tokens are received.

## Contract Overview

| Contract | Description |
|----------|-------------|
| GameManager | Basic contract that manages game start time and duration. Sets a 7-day game period and tracks game status (pending, active, ended). |
| InfectionManager | Core contract managing infection states. Tracks infection history between wallets, active infections, infection counts per virus, and top infectors.(*1) |
| RewardWinnerPot | Manages reward distribution. At game end, distributes rewards to top 3 infectors (17%,10%,7%) and Uniswap buyback (66%). |
| RewardFirstInfection | Virus tokens can be used to infect other wallets, and the first time a wallet is able to infect a certain wallet, it receives a fee for the wallet it purchases. users receive ETH tokens and after being listed on Uniswap receive virus tokens as reward. |
| Virus | ERC20 token-based virus token. Collects 0.25% fee on transactions and attempts infection during token transfers. |
| VirusFactory | Factory contract for creating virus tokens and managing initial liquidity. Can create up to 30 viruses with pricing following y = x + 1 curve. |
| VirusDrop | Utility contract providing gas-optimized bulk transfers. Enables efficient ERC20 token airdrops. |

(*1) Infection test cases can be found in the following spreadsheet:
https://docs.google.com/spreadsheets/d/1Kth1n7RxUUWyAjVXJXNudb8KTJm2jXZcjeT8NaFDMKQ/edit?gid=0#gid=0

## how to build

```
$ forge install foundry-rs/forge-std --no-commit
$ forge install OpenZeppelin/openzeppelin-contracts --no-commit
$ forge soldeer install @uniswap-v2-core~1.0.1
$ forge soldeer install @uniswap-v2-periphery~1.1.0-beta.0
$ forge clean
$ forge build
```

## test

whole test

```
anvil --fork-url https://mainnet.base.org
forge test -vvv --fork-url http://localhost:8545
```

each test

```
forge test
forge test --match-path test/FILE_NAME.t.sol --fork-url http://localhost:8545 -vvvv 
forge test --match-test testVirusTransfer --fork-url http://localhost:8545 

```


## how to operate

### deploy

```
$ forge build
$ forge script script/DeployInfected.s.sol:DeployInfected --rpc-url base_sepolia --broadcast --verify
$ forge script script/DeployVirusDrop.s.sol:DeployVirusDrop --rpc-url base_sepolia --broadcast --verify
```


### after finished

In order for the winner to make a withdrawal, the following must be done.
The reason for this procedure is that the distribution of the winner's rewards takes place at the time liquidity is provided to Uniswap.

1. afterGameEndsUniswapAdded (VirusFactory)
2. aggregation (RewardWinnerPot)

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details.
