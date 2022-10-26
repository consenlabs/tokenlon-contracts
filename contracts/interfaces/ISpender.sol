// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "../utils/SpenderLibEIP712.sol";

interface ISpender {
    // System events
    event TimeLockActivated(uint256 activatedTimeStamp);
    // Owner events
    event SetAllowanceTarget(address allowanceTarget);
    event SetNewSpender(address newSpender);
    event SetConsumeGasERC20Token(address token);
    event TearDownAllowanceTarget(uint256 tearDownTimeStamp);
    event BlackListToken(address token, bool isBlacklisted);
    event AuthorizeSpender(address spender, bool isAuthorized);

    function spendFromUser(
        address _user,
        address _tokenAddr,
        uint256 _amount
    ) external;

    function spendFromUserTo(
        address _user,
        address _tokenAddr,
        address _receiverAddr,
        uint256 _amount
    ) external;

    function spendFromUserToWithPermit(SpenderLibEIP712.SpendWithPermit calldata _params, bytes calldata _spendWithPermitSig) external;
}
