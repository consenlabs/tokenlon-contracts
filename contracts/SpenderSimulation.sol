// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "./interfaces/IHasBlackListERC20Token.sol";
import "./interfaces/ISpender.sol";
import "./utils/SpenderLibEIP712.sol";

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
    /// @param _params The params of the SpendWithPermit.
    /// @param _spendWithPermitSig Spend with permit signature.
    function simulate(SpenderLibEIP712.SpendWithPermit calldata _params, bytes calldata _spendWithPermitSig)
        external
        checkBlackList(_params.tokenAddr, _params.user)
    {
        spender.spendFromUserToWithPermit(_params, _spendWithPermitSig);

        // All checks passed: revert with success reason string
        revert("SpenderSimulation: transfer simulation success");
    }
}
