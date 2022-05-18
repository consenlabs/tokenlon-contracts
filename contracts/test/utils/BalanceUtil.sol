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
        // Use stdStorage to find storage slot of user's balance
        // prettier-ignore
        uint256 tokenStorageSlot = stdstore
            .target(tokenAddr)
            .sig("balanceOf(address)")
            .with_key(userAddr)
            .find();
        // prettier-ignore
        vm.store(
            tokenAddr, // address
            bytes32(tokenStorageSlot), // key
            bytes32(amount * (10**decimals)) // value
        );
    }
}
