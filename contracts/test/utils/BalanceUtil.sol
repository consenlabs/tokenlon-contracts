pragma solidity 0.7.6;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BalanceUtil is Test {
    using stdStorage for StdStorage;

    function setERC20Balance(
        address tokenAddr,
        address userAddr,
        uint256 amount
    ) internal {
        uint256 decimals = uint256(ERC20(tokenAddr).decimals());
        deal(
            tokenAddr,
            userAddr,
            amount * (10**decimals),
            true // also update totalSupply
        );
    }
}
