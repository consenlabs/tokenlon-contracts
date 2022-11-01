# Tokenlon

Tokenlon is a decentralized exchanging protocol consists of multiple components with a single static entry. Users can trade assets with a quote from a professional market maker or swap with other AMM protocol with no husstle. Also, complex contract interactions can be simplified by leveraging the approval mechanism of the protocol. Tokenlon has its own native token named LON and the protocol is governed by LON token holders. Also, there're other functions in the token economic system which provide incentive for LON token holders and help keeping the protocol sustainable.

There are three major categories of contracts in this repo:

1. [Tokenlon Protocol Infrastructure](#Infrastructure)

2. [Trading Strategy Contracts](#Trading-Strategy-Contracts)

3. [LON Token peripherals](#LON-Token-peripherals)

![image info](../tokenlon_architecture.png)

# Protocol Infrastructure

## User Proxy & Tokenlon

User proxy is the entry of the whole procotol while Tokenlon is a transparent upgradeable proxy of it. User proxy navigate users to a specific strategy contract. Meanwhile, it has a multicall entry which allows batching calls between differnt strategy contracts in a single transaction.

## Permanent Storage & ProxyPermanentStorage

## Allowance Target & Spender

## SpenderSimulation

## MarketMakerProxy

# Trading Strategy Contracts

-   AMMWrapper & AMMQuoter
-   [RFQ (MarketMakerProxy)](./strategies/RFQ.md)
-   Limit Order
-   L2Deposit

# LON Token peripherals

-   LON
-   LON Staking & xLON
-   LPStakingRewards
-   RewardDistributor
-   MerkleRedeem
-   TreasuryVester & TreasuryVesterFactory
