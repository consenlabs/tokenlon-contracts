# Tokenlon

[![Node.js CI](https://github.com/consenlabs/tokenlon-contracts/actions/workflows/node.js.yml/badge.svg?branch=master)](https://github.com/consenlabs/tokenlon-contracts/actions/workflows/node.js.yml)
[![Built-with openzeppelin](https://img.shields.io/badge/built%20with-OpenZeppelin-3677FF)](https://docs.openzeppelin.com/)

> Notice: This repository may contains changes that are under development. Make sure the correct commit is referenced when reviewing specific deployed contract.

## Architecture

![image info](./tokenlon_architecture.png)

## Deployed contracts (Mainnet)

| Contracts                        | Address                                                                                                               |
| -------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| LON                              | [0x0000000000095413afC295d19EDeb1Ad7B71c952](https://etherscan.io/address/0x0000000000095413afC295d19EDeb1Ad7B71c952) |
| xLON                             | [0xf88506b0f1d30056b9e5580668d5875b9cd30f23](https://etherscan.io/address/0xf88506b0f1d30056b9e5580668d5875b9cd30f23) |
| LONStaking                       | [0x413ecce5d56204962090eef1dead4c0a247e289b](https://etherscan.io/address/0x413ecce5d56204962090eef1dead4c0a247e289b) |
| MiningTreasury                   | [0x292a6921Efc261070a0d5C96911c102cBF1045E4](https://etherscan.io/address/0x292a6921Efc261070a0d5C96911c102cBF1045E4) |
| TreasuryVesterFactory            | [0x000000003A8DBF47cD362EDA39B3a5F3FC6E99ce](https://etherscan.io/address/0x000000003A8DBF47cD362EDA39B3a5F3FC6E99ce) |
| MerkleRedeem                     | [0x0000000006a0403952389B70d8EE4E45479023db](https://etherscan.io/address/0x0000000006a0403952389B70d8EE4E45479023db) |
| RewardDistributor                | [0xbF1C2c17CC77e7Dec3466B96F46f93c09f02aB07](https://etherscan.io/address/0xbF1C2c17CC77e7Dec3466B96F46f93c09f02aB07) |
| StakingRewards (LON/ETH)         | [0xb6bC1a713e4B11fa31480d31C825dCFd7e8FaBFD](https://etherscan.io/address/0xb6bC1a713e4B11fa31480d31C825dCFd7e8FaBFD) |
| StakingRewards (LON/USDT)        | [0x9648B119f442a3a096C0d5A1F8A0215B46dbb547](https://etherscan.io/address/0x9648B119f442a3a096C0d5A1F8A0215B46dbb547) |
| Tokenlon                         | [0x03f34bE1BF910116595dB1b11E9d1B2cA5D59659](https://etherscan.io/address/0x03f34bE1BF910116595dB1b11E9d1B2cA5D59659) |
| UserProxy                        | [0xe25ff902295Bc085bd548955B0595B518d4c46D2](https://etherscan.io/address/0xe25ff902295Bc085bd548955B0595B518d4c46D2) |
| PermanentStorage                 | [0x1A286652288691D086006B81655e4EfA895Df84D](https://etherscan.io/address/0x1A286652288691D086006B81655e4EfA895Df84D) |
| PermanentStorage (Upgrade Proxy) | [0x6D9Cc14a1d36E6fF13fc6efA9e9326FcD12E7903](https://etherscan.io/address/0x6D9Cc14a1d36E6fF13fc6efA9e9326FcD12E7903) |
| Spender                          | [0x3c68dfc45dc92C9c605d92B49858073e10b857A6](https://etherscan.io/address/0x3c68dfc45dc92C9c605d92B49858073e10b857A6) |
| AllowanceTarget                  | [0x8A42d311D282Bfcaa5133b2DE0a8bCDBECea3073](https://etherscan.io/address/0x8A42d311D282Bfcaa5133b2DE0a8bCDBECea3073) |
| PMM                              | [0x8D90113A1e286a5aB3e496fbD1853F265e5913c6](https://etherscan.io/address/0x8D90113A1e286a5aB3e496fbD1853F265e5913c6) |
| AMMQuoter                        | [0x7839254CfF8aaFBdC2da66fe709eB8f17cE09fe5](https://etherscan.io/address/0x7839254CfF8aaFBdC2da66fe709eB8f17cE09fe5) |
| AMMWrapperWithPath               | [0x4a14347083B80E5216cA31350a2D21702aC3650d](https://etherscan.io/address/0x4a14347083B80E5216cA31350a2D21702aC3650d) |
| RFQ                              | [0xfD6C2d2499b1331101726A8AC68CCc9Da3fAB54F](https://etherscan.io/address/0xfD6C2d2499b1331101726A8AC68CCc9Da3fAB54F) |

## Prerequisite

-   node (>=14.0.0 <16)
-   yarn (^1.22.10)
-   [foundry](https://github.com/foundry-rs/foundry)
-   Environment Variables (Used for foundry fork tests)
    -   MAINNET_NODE_RPC_URL : The RPC URL for accessing forked states.
    -   FORK_BLOCK_NUMBER : Specfic block number of forked states.

## Installation

```bash
$ git submodule update --init --recursive
$ yarn run setup
```

## Compile contracts

```bash
$ yarn run compile # compile contracts
```

## Run unit test

```bash
$ yarn run test-foundry-local # run unit tests with fresh states
$ yarn run test-foundry-fork # run unit tests with forked states
```
