// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

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

    function spendFromUserToWithPermit(
        address _tokenAddr,
        address _requester,
        address _user,
        address _recipient,
        uint256 _amount,
        uint256 _salt,
        uint64 _expiry,
        bytes calldata _spendWithPermitSig
    ) external;
}
