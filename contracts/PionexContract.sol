// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./interfaces/IPionexContract.sol";
import "./interfaces/IPermanentStorage.sol";
import "./interfaces/ISpender.sol";
import "./interfaces/IWeth.sol";
import "./utils/StrategyBase.sol";
import "./utils/BaseLibEIP712.sol";
import "./utils/LibConstant.sol";
import "./utils/LibPionexContractOrderStorage.sol";
import "./utils/PionexContractLibEIP712.sol";
import "./utils/SignatureValidator.sol";

/// @title Pionex Contract
/// @notice Order can be filled as long as the provided pionexToken/userToken ratio is better than or equal to user's specfied pionexToken/userToken ratio.
/// @author imToken Labs
contract PionexContract is IPionexContract, StrategyBase, BaseLibEIP712, SignatureValidator, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public immutable factorActivateDelay;

    // Below are the variables which consume storage slots.
    address public coordinator;
    address public feeCollector;

    // Factors
    uint256 public factorsTimeLock;
    uint16 public userFeeFactor = 0;
    uint16 public pendingMakerFeeFactor;

    constructor(
        address _owner,
        address _userProxy,
        address _weth,
        address _permStorage,
        address _spender,
        address _coordinator,
        uint256 _factorActivateDelay,
        address _feeCollector
    ) StrategyBase(_owner, _userProxy, _weth, _permStorage, _spender) {
        coordinator = _coordinator;
        factorActivateDelay = _factorActivateDelay;
        feeCollector = _feeCollector;
    }

    receive() external payable {}

    /// @notice Only owner can call
    /// @param _newCoordinator The new address of coordinator
    function upgradeCoordinator(address _newCoordinator) external onlyOwner {
        require(_newCoordinator != address(0), "PionexContract: coordinator can not be zero address");
        coordinator = _newCoordinator;

        emit UpgradeCoordinator(_newCoordinator);
    }

    /// @notice Only owner can call
    /// @param _userFeeFactor The new fee factor for user
    function setFactors(uint16 _userFeeFactor) external onlyOwner {
        require(_userFeeFactor <= LibConstant.BPS_MAX, "PionexContract: Invalid user fee factor");

        pendingMakerFeeFactor = _userFeeFactor;

        factorsTimeLock = block.timestamp + factorActivateDelay;
    }

    /// @notice Only owner can call
    function activateFactors() external onlyOwner {
        require(factorsTimeLock != 0, "PionexContract: no pending fee factors");
        require(block.timestamp >= factorsTimeLock, "PionexContract: fee factors timelocked");
        factorsTimeLock = 0;
        userFeeFactor = pendingMakerFeeFactor;
        pendingMakerFeeFactor = 0;

        emit FactorsUpdated(userFeeFactor);
    }

    /// @notice Only owner can call
    /// @param _newFeeCollector The new address of fee collector
    function setFeeCollector(address _newFeeCollector) external onlyOwner {
        require(_newFeeCollector != address(0), "PionexContract: fee collector can not be zero address");
        feeCollector = _newFeeCollector;

        emit SetFeeCollector(_newFeeCollector);
    }

    /// @inheritdoc IPionexContract
    function fillLimitOrder(
        PionexContractLibEIP712.Order calldata _order,
        bytes calldata _orderMakerSig,
        TraderParams calldata _params,
        CoordinatorParams calldata _crdParams
    ) external override onlyUserProxy nonReentrant returns (uint256, uint256) {
        bytes32 orderHash = getEIP712Hash(PionexContractLibEIP712._getOrderStructHash(_order));

        _validateOrder(_order, orderHash, _orderMakerSig);
        bytes32 allowFillHash = _validateFillPermission(orderHash, _params.pionexTokenAmount, _params.pionex, _crdParams);
        _validateOrderTaker(_order, _params.pionex);

        // Check provided pionexToken/userToken ratio is better than or equal to user's specfied pionexToken/userToken ratio
        // -> _params.pionexTokenAmount/_params.userTokenAmount >= _order.pionexTokenAmount/_order.userTokenAmount
        require(
            _params.pionexTokenAmount.mul(_order.userTokenAmount) >= _order.pionexTokenAmount.mul(_params.userTokenAmount),
            "PionexContract: pionex/user token ratio not good enough"
        );
        // Check gas fee factor and pionex strategy fee factor do not exceed limit
        require(
            (_params.gasFeeFactor <= LibConstant.BPS_MAX) &&
                (_params.pionexStrategyFeeFactor <= LibConstant.BPS_MAX) &&
                (_params.gasFeeFactor + _params.pionexStrategyFeeFactor <= LibConstant.BPS_MAX - userFeeFactor),
            "PionexContract: Invalid pionex fee factor"
        );

        {
            PionexContractLibEIP712.Fill memory fill = PionexContractLibEIP712.Fill({
                orderHash: orderHash,
                pionex: _params.pionex,
                recipient: _params.recipient,
                userTokenAmount: _params.userTokenAmount,
                pionexTokenAmount: _params.pionexTokenAmount,
                pionexSalt: _params.salt,
                expiry: _params.expiry
            });
            _validateTraderFill(fill, _params.pionexSig);
        }

        (uint256 userTokenAmount, uint256 remainingAmount) = _quoteOrderFromMakerToken(_order, orderHash, _params.userTokenAmount);
        // Calculate pionexTokenAmount according to the provided pionexToken/userToken ratio
        uint256 pionexTokenAmount = userTokenAmount.mul(_params.pionexTokenAmount).div(_params.userTokenAmount);

        uint256 userTokenOut = _settleForTrader(
            TraderSettlement({
                orderHash: orderHash,
                allowFillHash: allowFillHash,
                trader: _params.pionex,
                recipient: _params.recipient,
                user: _order.user,
                pionex: _order.pionex,
                userToken: _order.userToken,
                pionexToken: _order.pionexToken,
                userTokenAmount: userTokenAmount,
                pionexTokenAmount: pionexTokenAmount,
                remainingAmount: remainingAmount,
                gasFeeFactor: _params.gasFeeFactor,
                pionexStrategyFeeFactor: _params.pionexStrategyFeeFactor
            })
        );

        _recordMakerTokenFilled(orderHash, userTokenAmount);

        return (pionexTokenAmount, userTokenOut);
    }

    function _validateTraderFill(PionexContractLibEIP712.Fill memory _fill, bytes memory _fillTakerSig) internal {
        require(_fill.expiry > uint64(block.timestamp), "PionexContract: Fill request is expired");
        require(_fill.recipient != address(0), "PionexContract: recipient can not be zero address");

        bytes32 fillHash = getEIP712Hash(PionexContractLibEIP712._getFillStructHash(_fill));
        require(isValidSignature(_fill.pionex, fillHash, bytes(""), _fillTakerSig), "PionexContract: Fill is not signed by pionex");

        // Set fill seen to avoid replay attack.
        // PermanentStorage would throw error if fill is already seen.
        permStorage.setLimitOrderTransactionSeen(fillHash);
    }

    function _validateFillPermission(
        bytes32 _orderHash,
        uint256 _fillAmount,
        address _executor,
        CoordinatorParams memory _crdParams
    ) internal returns (bytes32) {
        require(_crdParams.expiry > uint64(block.timestamp), "PionexContract: Fill permission is expired");

        bytes32 allowFillHash = getEIP712Hash(
            PionexContractLibEIP712._getAllowFillStructHash(
                PionexContractLibEIP712.AllowFill({
                    orderHash: _orderHash,
                    executor: _executor,
                    fillAmount: _fillAmount,
                    salt: _crdParams.salt,
                    expiry: _crdParams.expiry
                })
            )
        );
        require(isValidSignature(coordinator, allowFillHash, bytes(""), _crdParams.sig), "PionexContract: AllowFill is not signed by coordinator");

        // Set allow fill seen to avoid replay attack
        // PermanentStorage would throw error if allow fill is already seen.
        permStorage.setLimitOrderAllowFillSeen(allowFillHash);

        return allowFillHash;
    }

    struct TraderSettlement {
        bytes32 orderHash;
        bytes32 allowFillHash;
        address trader;
        address recipient;
        address user;
        address pionex;
        IERC20 userToken;
        IERC20 pionexToken;
        uint256 userTokenAmount;
        uint256 pionexTokenAmount;
        uint256 remainingAmount;
        uint16 gasFeeFactor;
        uint16 pionexStrategyFeeFactor;
    }

    function _settleForTrader(TraderSettlement memory _settlement) internal returns (uint256) {
        // memory cache
        ISpender _spender = spender;
        address _feeCollector = feeCollector;

        // Calculate user fee (user receives pionex token so fee is charged in pionex token)
        // 1. Fee for Tokenlon
        uint256 tokenlonFee = _mulFactor(_settlement.pionexTokenAmount, userFeeFactor);
        // 2. Fee for Pionex, including gas fee and strategy fee
        uint256 pionexFee = _mulFactor(_settlement.pionexTokenAmount, _settlement.gasFeeFactor + _settlement.pionexStrategyFeeFactor);
        uint256 pionexTokenForMaker = _settlement.pionexTokenAmount.sub(tokenlonFee).sub(pionexFee);

        // trader -> user
        _spender.spendFromUserTo(_settlement.trader, address(_settlement.pionexToken), _settlement.user, pionexTokenForMaker);

        // user -> recipient
        _spender.spendFromUserTo(_settlement.user, address(_settlement.userToken), _settlement.recipient, _settlement.userTokenAmount);

        // Collect user fee (charged in pionex token)
        if (tokenlonFee > 0) {
            _spender.spendFromUserTo(_settlement.trader, address(_settlement.pionexToken), _feeCollector, tokenlonFee);
        }

        // bypass stack too deep error
        _emitLimitOrderFilledByTrader(
            LimitOrderFilledByTraderParams({
                orderHash: _settlement.orderHash,
                user: _settlement.user,
                pionex: _settlement.trader,
                allowFillHash: _settlement.allowFillHash,
                recipient: _settlement.recipient,
                userToken: address(_settlement.userToken),
                pionexToken: address(_settlement.pionexToken),
                userTokenFilledAmount: _settlement.userTokenAmount,
                pionexTokenFilledAmount: _settlement.pionexTokenAmount,
                remainingAmount: _settlement.remainingAmount,
                tokenlonFee: tokenlonFee,
                pionexFee: pionexFee
            })
        );

        return _settlement.userTokenAmount;
    }

    /// @inheritdoc IPionexContract
    function cancelLimitOrder(PionexContractLibEIP712.Order calldata _order, bytes calldata _cancelOrderMakerSig) external override onlyUserProxy nonReentrant {
        require(_order.expiry > uint64(block.timestamp), "PionexContract: Order is expired");
        bytes32 orderHash = getEIP712Hash(PionexContractLibEIP712._getOrderStructHash(_order));
        bool isCancelled = LibPionexContractOrderStorage.getStorage().orderHashToCancelled[orderHash];
        require(!isCancelled, "PionexContract: Order is cancelled already");
        {
            PionexContractLibEIP712.Order memory cancelledOrder = _order;
            cancelledOrder.pionexTokenAmount = 0;

            bytes32 cancelledOrderHash = getEIP712Hash(PionexContractLibEIP712._getOrderStructHash(cancelledOrder));
            require(isValidSignature(_order.user, cancelledOrderHash, bytes(""), _cancelOrderMakerSig), "PionexContract: Cancel request is not signed by user");
        }

        // Set cancelled state to storage
        LibPionexContractOrderStorage.getStorage().orderHashToCancelled[orderHash] = true;
        emit OrderCancelled(orderHash, _order.user);
    }

    /* order utils */

    function _validateOrder(
        PionexContractLibEIP712.Order memory _order,
        bytes32 _orderHash,
        bytes memory _orderMakerSig
    ) internal view {
        require(_order.expiry > uint64(block.timestamp), "PionexContract: Order is expired");
        bool isCancelled = LibPionexContractOrderStorage.getStorage().orderHashToCancelled[_orderHash];
        require(!isCancelled, "PionexContract: Order is cancelled");

        require(isValidSignature(_order.user, _orderHash, bytes(""), _orderMakerSig), "PionexContract: Order is not signed by user");
    }

    function _validateOrderTaker(PionexContractLibEIP712.Order memory _order, address _pionex) internal pure {
        if (_order.pionex != address(0)) {
            require(_order.pionex == _pionex, "PionexContract: Order cannot be filled by this pionex");
        }
    }

    function _quoteOrderFromMakerToken(
        PionexContractLibEIP712.Order memory _order,
        bytes32 _orderHash,
        uint256 _userTokenAmount
    ) internal view returns (uint256, uint256) {
        uint256 userTokenFilledAmount = LibPionexContractOrderStorage.getStorage().orderHashToMakerTokenFilledAmount[_orderHash];

        require(userTokenFilledAmount < _order.userTokenAmount, "PionexContract: Order is filled");

        uint256 userTokenFillableAmount = _order.userTokenAmount.sub(userTokenFilledAmount);
        uint256 userTokenQuota = Math.min(_userTokenAmount, userTokenFillableAmount);
        uint256 remainingAfterFill = userTokenFillableAmount.sub(userTokenQuota);

        require(userTokenQuota != 0, "PionexContract: zero token amount");
        return (userTokenQuota, remainingAfterFill);
    }

    function _recordMakerTokenFilled(bytes32 _orderHash, uint256 _userTokenAmount) internal {
        LibPionexContractOrderStorage.Storage storage stor = LibPionexContractOrderStorage.getStorage();
        uint256 userTokenFilledAmount = stor.orderHashToMakerTokenFilledAmount[_orderHash];
        stor.orderHashToMakerTokenFilledAmount[_orderHash] = userTokenFilledAmount.add(_userTokenAmount);
    }

    /* math utils */

    function _mulFactor(uint256 amount, uint256 factor) internal pure returns (uint256) {
        return amount.mul(factor).div(LibConstant.BPS_MAX);
    }

    /* event utils */

    struct LimitOrderFilledByTraderParams {
        bytes32 orderHash;
        address user;
        address pionex;
        bytes32 allowFillHash;
        address recipient;
        address userToken;
        address pionexToken;
        uint256 userTokenFilledAmount;
        uint256 pionexTokenFilledAmount;
        uint256 remainingAmount;
        uint256 tokenlonFee;
        uint256 pionexFee;
    }

    function _emitLimitOrderFilledByTrader(LimitOrderFilledByTraderParams memory _params) internal {
        emit LimitOrderFilledByTrader(
            _params.orderHash,
            _params.user,
            _params.pionex,
            _params.allowFillHash,
            _params.recipient,
            FillReceipt({
                userToken: _params.userToken,
                pionexToken: _params.pionexToken,
                userTokenFilledAmount: _params.userTokenFilledAmount,
                pionexTokenFilledAmount: _params.pionexTokenFilledAmount,
                remainingAmount: _params.remainingAmount,
                tokenlonFee: _params.tokenlonFee,
                pionexFee: _params.pionexFee
            })
        );
    }
}
