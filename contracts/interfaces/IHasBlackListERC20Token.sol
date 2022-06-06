pragma solidity >=0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IHasBlackListERC20Token is IERC20 {
    function isBlackListed(address user) external returns (bool);

    function addBlackList(address user) external;

    function removeBlackList(address user) external;
}
