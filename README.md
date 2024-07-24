# Tokenlon

[![Node.js CI](https://github.com/consenlabs/tokenlon-contracts/actions/workflows/node.js.yml/badge.svg?branch=master)](https://github.com/consenlabs/tokenlon-contracts/actions/workflows/node.js.yml)
[![Built-with openzeppelin](https://img.shields.io/badge/built%20with-OpenZeppelin-3677FF)](https://docs.openzeppelin.com/)

Tokenlon is a decentralized exchange and payment settlement protocol based on blockchain technology. Visit [tokenlon.im](https://tokenlon.im/)

> Notice: This repository may contain changes that are under development. Make sure the correct commit is referenced when reviewing specific deployed contract.

## Architecture

Under construction

## Deployed contracts

Under construction

## Prerequisite

-   node (>=16.0.0 <18)
-   yarn (^1.22.10)
-   [foundry](https://github.com/foundry-rs/foundry)
-   Environment Variables (Used for foundry fork tests)
    -   `MAINNET_NODE_RPC_URL`: The RPC URL for accessing forked states.

### Example

```bash
MAINNET_NODE_RPC_URL=https://eth-mainnet.infura.io/v3//#####__YOUR_SECRET__#####
```
```bash
MAINNET_NODE_RPC_URL=https://polygon-mainnet.infura.io/v3//#####__YOUR_SECRET__#####
```

## Installation

```bash
$ git submodule update --init --recursive
$ yarn run setup
```

## Compile contracts

```bash
# Compile contracts
$ yarn run compile
```

## Run unit test

```bash
# Run unit tests with fresh states
$ yarn run test-foundry-local

# Run integration tests with forked states
$ yarn run test-foundry-fork
```
