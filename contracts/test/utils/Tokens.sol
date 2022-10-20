// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Addresses.sol";

contract Tokens is Test {
    IERC20 public weth;
    IERC20 public usdt;
    IERC20 public usdc;
    IERC20 public dai;
    IERC20 public wbtc;
    IERC20 public lon;
    IERC20 public ankreth;
    IERC20[] public tokens;

    constructor() {
        if (vm.envBool("deployed")) {
            // load ERC20s using address in env vars
            weth = IERC20(vm.envAddress("WETH_ADDRESS"));
            usdt = IERC20(vm.envAddress("USDT_ADDRESS"));
            usdc = IERC20(vm.envAddress("USDC_ADDRESS"));
            dai = IERC20(vm.envAddress("DAI_ADDRESS"));
            wbtc = IERC20(vm.envAddress("WBTC_ADDRESS"));
            lon = IERC20(vm.envAddress("LON_ADDRESS"));
            ankreth = IERC20(vm.envAddress("ANKRETH_ADDRESS"));
        } else {
            // load ERC20s using constant address
            weth = IERC20(WETH_ADDRESS);
            usdt = IERC20(USDT_ADDRESS);
            usdc = IERC20(USDC_ADDRESS);
            dai = IERC20(DAI_ADDRESS);
            wbtc = IERC20(WBTC_ADDRESS);
            lon = IERC20(LON_ADDRESS);
            ankreth = IERC20(ANKRETH_ADDRESS);
        }

        tokens = [weth, usdt, usdc, dai, wbtc, lon, ankreth];

        vm.label(address(weth), "WETH");
        vm.label(address(usdt), "USDT");
        vm.label(address(usdc), "USDC");
        vm.label(address(dai), "DAI");
        vm.label(address(wbtc), "WBTC");
        vm.label(address(lon), "LON");
        vm.label(address(ankreth), "ANKRETH");
    }
}
