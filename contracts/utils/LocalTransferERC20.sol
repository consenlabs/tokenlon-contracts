// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

abstract contract LocalTransferERC20 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    function _localSpendFromUserTo(
        address _user,
        address _tokenAddr,
        address _recipient,
        uint256 _amount
    ) internal {
        uint256 balanceBefore = IERC20(_tokenAddr).balanceOf(_recipient);
        IERC20(_tokenAddr).safeTransferFrom(_user, _recipient, _amount);
        uint256 balanceAfter = IERC20(_tokenAddr).balanceOf(_recipient);
        require(balanceAfter.sub(balanceBefore) == _amount, "ERC20Transfer: ERC20 transferFrom amount mismatch");
    }
}
