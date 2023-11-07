// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockWETH } from "test/mocks/MockWETH.sol";
import { Addresses } from "test/utils/Addresses.sol";

contract Tokens is Addresses {
    IERC20 public weth;
    IERC20 public usdt;
    IERC20 public usdc;
    IERC20 public dai;
    IERC20 public wbtc;
    IERC20 public lon;
    IERC20 public ankreth;
    IERC20[] public tokens;

    constructor() {
        uint256 chainId = getChainId();

        if (chainId == 31337) {
            // local testnet, deploy new ERC20s
            weth = IERC20(address(new MockWETH("Wrapped ETH", "WETH", 18)));
            usdt = new MockERC20("USDT", "USDT", 6);
            usdc = new MockERC20("USDC", "USDC", 18);
            dai = new MockERC20("DAI", "DAI", 18);
            wbtc = new MockERC20("WBTC", "WBTC", 18);
            lon = new MockERC20("LON", "LON", 18);
        } else {
            // forked mainnet, load ERC20s using constant address
            weth = IERC20(WETH_ADDRESS);
            usdt = IERC20(USDT_ADDRESS);
            usdc = IERC20(USDC_ADDRESS);
            dai = IERC20(DAI_ADDRESS);
            wbtc = IERC20(WBTC_ADDRESS);
            lon = IERC20(LON_ADDRESS);
        }

        tokens = [weth, usdt, usdc, dai, wbtc, lon];

        vm.label(address(weth), "WETH");
        vm.label(address(usdt), "USDT");
        vm.label(address(usdc), "USDC");
        vm.label(address(dai), "DAI");
        vm.label(address(wbtc), "WBTC");
        vm.label(address(lon), "LON");
        vm.label(address(ankreth), "ANKRETH");
    }
}
