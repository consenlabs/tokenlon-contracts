pragma solidity 0.7.6;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./Addresses.sol";

contract BalanceUtil is Test {
    using stdStorage for StdStorage;

    function setERC20Balance(
        address tokenAddr,
        address userAddr,
        uint256 amount
    ) internal {
        uint256 decimals = uint256(ERC20(tokenAddr).decimals());
        // Skip setting WETH's totalSupply because WETH does not store total supply in storage
        bool updateTotalSupply = tokenAddr == WETH_ADDRESS ? false : true;
        deal(
            tokenAddr,
            userAddr,
            amount * (10**decimals),
            updateTotalSupply // also update totalSupply
        );
    }
}
