// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./Ownable.sol";
import "./LibConstant.sol";
import "../interfaces/IWeth.sol";
import "../interfaces/IStrategyBase.sol";
import "../interfaces/ISpender.sol";
import "../interfaces/IPermanentStorage.sol";

/// @title StrategyBase Abstract Contract
/// @author imToken Labs
/// @dev This contract is shared by every Tokenlon strategy contracts
abstract contract StrategyBase is IStrategyBase, Ownable {
    using SafeERC20 for IERC20;

    address public immutable userProxy;
    IWETH public immutable weth;
    IPermanentStorage public immutable permStorage;
    ISpender public spender;

    constructor(
        address _owner,
        address _userProxy,
        address _weth,
        address _permStorage,
        address _spender
    ) Ownable(_owner) {
        userProxy = _userProxy;
        weth = IWETH(_weth);
        permStorage = IPermanentStorage(_permStorage);
        spender = ISpender(_spender);
    }

    modifier onlyUserProxy() {
        require(address(userProxy) == msg.sender, "Strategy: not from UserProxy contract");
        _;
    }

    /// @inheritdoc IStrategyBase
    function upgradeSpender(address _newSpender) external override onlyOwner {
        require(_newSpender != address(0), "Strategy: spender can not be zero address");
        spender = ISpender(_newSpender);

        emit UpgradeSpender(_newSpender);
    }

    /// @inheritdoc IStrategyBase
    function setAllowance(address[] calldata _tokenList, address _spender) external override onlyOwner {
        for (uint256 i = 0; i < _tokenList.length; i++) {
            IERC20(_tokenList[i]).safeApprove(_spender, LibConstant.MAX_UINT);

            emit AllowTransfer(_spender, _tokenList[i]);
        }
    }

    /// @inheritdoc IStrategyBase
    function closeAllowance(address[] calldata _tokenList, address _spender) external override onlyOwner {
        for (uint256 i = 0; i < _tokenList.length; i++) {
            IERC20(_tokenList[i]).safeApprove(_spender, 0);

            emit DisallowTransfer(_spender, _tokenList[i]);
        }
    }

    /// @inheritdoc IStrategyBase
    function depositETH() external override onlyOwner {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            weth.deposit{ value: balance }();

            emit DepositETH(balance);
        }
    }
}
