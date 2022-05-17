# Tokenlon

[![Node.js CI](https://github.com/consenlabs/tokenlon-contracts/actions/workflows/node.js.yml/badge.svg?branch=master)](https://github.com/consenlabs/tokenlon-contracts/actions/workflows/node.js.yml)

> Notice: This repository may contains changes that are under development. Make sure the correct commit is referenced when reviewing specific deployed contract.

## Prerequisite

-   node (>=14.0.0 <16)
-   yarn (^1.22.10)
-   [foundry](https://github.com/foundry-rs/foundry)
-   Environment Variables (Used for foundry fork tests)
    -   FORK_URL : The RPC URL for accessing forked states.
    -   FORK_BLOCK_NUMBER : Specfic block number of forked states.

## Installation

```bash
$ git submodule update --init --recursive
$ yarn install
```

## Compile contracts

```bash
$ yarn run compile-contracts // compile contracts
$ yarn run compile-foundry // compile tests written in solidity
```

## Run unit test

```bash
$ yarn run test-foundry-local // run unit tests with fresh states
$ yarn run test-foundry-fork // run unit tests with forked states
```
