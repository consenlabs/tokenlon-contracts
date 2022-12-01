// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "./interfaces/IHasBlackListERC20Token.sol";
import "./interfaces/ISpender.sol";

contract SpenderSimulation {
    ISpender public immutable spender;

    mapping(address => bool) public hasBlackListERC20Tokens;

    modifier checkBlackList(address _tokenAddr, address _user) {
        if (hasBlackListERC20Tokens[_tokenAddr]) {
            IHasBlackListERC20Token hasBlackListERC20Token = IHasBlackListERC20Token(_tokenAddr);
            require(!hasBlackListERC20Token.isBlackListed(_user), "SpenderSimulation: user in token's blacklist");
        }
        _;
    }

    /************************************************************
     *                       Constructor                         *
     *************************************************************/
    constructor(ISpender _spender, address[] memory _hasBlackListERC20Tokens) {
        spender = _spender;

        for (uint256 i = 0; i < _hasBlackListERC20Tokens.length; i++) {
            hasBlackListERC20Tokens[_hasBlackListERC20Tokens[i]] = true;
        }
    }

    /************************************************************
     *                    Helper functions                       *
     *************************************************************/
    /// @dev Spend tokens on user's behalf but reverts if succeed.
    /// This is only intended to be run off-chain to check if the transfer will succeed.
    /// @param _user The user to spend token from.
    /// @param _tokenAddr The address of the token.
    /// @param _amount Amount to spend.
    function simulate(
        address _user,
        address _tokenAddr,
        uint256 _amount
    ) external checkBlackList(_tokenAddr, _user) {
        spender.spendFromUser(_user, _tokenAddr, _amount);

        // All checks passed: revert with success reason string
        revert("SpenderSimulation: transfer simulation success");
    }
}
