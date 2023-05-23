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
/// @notice Modified from LimitOrder contract. Maker is user, taker is Pionex agent.
/// @notice Order can be filled as long as the provided takerToken/makerToken ratio is better than or equal to maker's specfied takerToken/makerToken ratio.
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
    uint16 public makerFeeFactor = 0;
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
        require(_newCoordinator != address(0), "LimitOrder: coordinator can not be zero address");
        coordinator = _newCoordinator;

        emit UpgradeCoordinator(_newCoordinator);
    }

    /// @notice Only owner can call
    /// @param _makerFeeFactor The new fee factor for maker
    function setFactors(uint16 _makerFeeFactor) external onlyOwner {
        require(_makerFeeFactor <= LibConstant.BPS_MAX, "LimitOrder: Invalid maker fee factor");

        pendingMakerFeeFactor = _makerFeeFactor;

        factorsTimeLock = block.timestamp + factorActivateDelay;
    }

    /// @notice Only owner can call
    function activateFactors() external onlyOwner {
        require(factorsTimeLock != 0, "LimitOrder: no pending fee factors");
        require(block.timestamp >= factorsTimeLock, "LimitOrder: fee factors timelocked");
        factorsTimeLock = 0;
        makerFeeFactor = pendingMakerFeeFactor;
        pendingMakerFeeFactor = 0;

        emit FactorsUpdated(makerFeeFactor);
    }

    /// @notice Only owner can call
    /// @param _newFeeCollector The new address of fee collector
    function setFeeCollector(address _newFeeCollector) external onlyOwner {
        require(_newFeeCollector != address(0), "LimitOrder: fee collector can not be zero address");
        feeCollector = _newFeeCollector;

        emit SetFeeCollector(_newFeeCollector);
    }

    /// @inheritdoc IPionexContract
    function fillLimitOrderByTrader(
        PionexContractLibEIP712.Order calldata _order,
        bytes calldata _orderMakerSig,
        TraderParams calldata _params,
        CoordinatorParams calldata _crdParams
    ) external override onlyUserProxy nonReentrant returns (uint256, uint256) {
        bytes32 orderHash = getEIP712Hash(PionexContractLibEIP712._getOrderStructHash(_order));

        _validateOrder(_order, orderHash, _orderMakerSig);
        bytes32 allowFillHash = _validateFillPermission(orderHash, _params.takerTokenAmount, _params.taker, _crdParams);
        _validateOrderTaker(_order, _params.taker);

        // Check provided takerToken/makerToken ratio is better than or equal to maker's specfied takerToken/makerToken ratio
        // -> _params.takerTokenAmount/_params.makerTokenAmount >= _order.takerTokenAmount/_order.makerTokenAmount
        require(
            _params.takerTokenAmount.mul(_order.makerTokenAmount) >= _order.takerTokenAmount.mul(_params.makerTokenAmount),
            "LimitOrder: taker/maker token ratio not good enough"
        );

        {
            PionexContractLibEIP712.Fill memory fill = PionexContractLibEIP712.Fill({
                orderHash: orderHash,
                taker: _params.taker,
                recipient: _params.recipient,
                makerTokenAmount: _params.makerTokenAmount,
                takerTokenAmount: _params.takerTokenAmount,
                takerSalt: _params.salt,
                expiry: _params.expiry
            });
            _validateTraderFill(fill, _params.takerSig);
        }

        (uint256 makerTokenAmount, uint256 remainingAmount) = _quoteOrderFromMakerToken(_order, orderHash, _params.makerTokenAmount);
        // Calculate takerTokenAmount according to the provided takerToken/makerToken ratio
        uint256 takerTokenAmount = makerTokenAmount.mul(_params.takerTokenAmount).div(_params.makerTokenAmount);

        uint256 makerTokenOut = _settleForTrader(
            TraderSettlement({
                orderHash: orderHash,
                allowFillHash: allowFillHash,
                trader: _params.taker,
                recipient: _params.recipient,
                maker: _order.maker,
                taker: _order.taker,
                makerToken: _order.makerToken,
                takerToken: _order.takerToken,
                makerTokenAmount: makerTokenAmount,
                takerTokenAmount: takerTokenAmount,
                remainingAmount: remainingAmount
            })
        );

        _recordMakerTokenFilled(orderHash, makerTokenAmount);

        return (takerTokenAmount, makerTokenOut);
    }

    function _validateTraderFill(PionexContractLibEIP712.Fill memory _fill, bytes memory _fillTakerSig) internal {
        require(_fill.expiry > uint64(block.timestamp), "LimitOrder: Fill request is expired");
        require(_fill.recipient != address(0), "LimitOrder: recipient can not be zero address");

        bytes32 fillHash = getEIP712Hash(PionexContractLibEIP712._getFillStructHash(_fill));
        require(isValidSignature(_fill.taker, fillHash, bytes(""), _fillTakerSig), "LimitOrder: Fill is not signed by taker");

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
        require(_crdParams.expiry > uint64(block.timestamp), "LimitOrder: Fill permission is expired");

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
        require(isValidSignature(coordinator, allowFillHash, bytes(""), _crdParams.sig), "LimitOrder: AllowFill is not signed by coordinator");

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
        address maker;
        address taker;
        IERC20 makerToken;
        IERC20 takerToken;
        uint256 makerTokenAmount;
        uint256 takerTokenAmount;
        uint256 remainingAmount;
    }

    function _settleForTrader(TraderSettlement memory _settlement) internal returns (uint256) {
        // memory cache
        ISpender _spender = spender;
        address _feeCollector = feeCollector;

        // Calculate maker fee (maker receives taker token so fee is charged in taker token)
        uint256 takerTokenFee = _mulFactor(_settlement.takerTokenAmount, makerFeeFactor);
        uint256 takerTokenForMaker = _settlement.takerTokenAmount.sub(takerTokenFee);

        // trader -> maker
        _spender.spendFromUserTo(_settlement.trader, address(_settlement.takerToken), _settlement.maker, takerTokenForMaker);

        // maker -> recipient
        _spender.spendFromUserTo(_settlement.maker, address(_settlement.makerToken), _settlement.recipient, _settlement.makerTokenAmount);

        // Collect maker fee (charged in taker token)
        if (takerTokenFee > 0) {
            _spender.spendFromUserTo(_settlement.trader, address(_settlement.takerToken), _feeCollector, takerTokenFee);
        }

        // bypass stack too deep error
        _emitLimitOrderFilledByTrader(
            LimitOrderFilledByTraderParams({
                orderHash: _settlement.orderHash,
                maker: _settlement.maker,
                taker: _settlement.trader,
                allowFillHash: _settlement.allowFillHash,
                recipient: _settlement.recipient,
                makerToken: address(_settlement.makerToken),
                takerToken: address(_settlement.takerToken),
                makerTokenFilledAmount: _settlement.makerTokenAmount,
                takerTokenFilledAmount: _settlement.takerTokenAmount,
                remainingAmount: _settlement.remainingAmount,
                takerTokenFee: takerTokenFee
            })
        );

        return _settlement.makerTokenAmount;
    }

    /// @inheritdoc IPionexContract
    function cancelLimitOrder(PionexContractLibEIP712.Order calldata _order, bytes calldata _cancelOrderMakerSig) external override onlyUserProxy nonReentrant {
        require(_order.expiry > uint64(block.timestamp), "LimitOrder: Order is expired");
        bytes32 orderHash = getEIP712Hash(PionexContractLibEIP712._getOrderStructHash(_order));
        bool isCancelled = LibPionexContractOrderStorage.getStorage().orderHashToCancelled[orderHash];
        require(!isCancelled, "LimitOrder: Order is cancelled already");
        {
            PionexContractLibEIP712.Order memory cancelledOrder = _order;
            cancelledOrder.takerTokenAmount = 0;

            bytes32 cancelledOrderHash = getEIP712Hash(PionexContractLibEIP712._getOrderStructHash(cancelledOrder));
            require(isValidSignature(_order.maker, cancelledOrderHash, bytes(""), _cancelOrderMakerSig), "LimitOrder: Cancel request is not signed by maker");
        }

        // Set cancelled state to storage
        LibPionexContractOrderStorage.getStorage().orderHashToCancelled[orderHash] = true;
        emit OrderCancelled(orderHash, _order.maker);
    }

    /* order utils */

    function _validateOrder(
        PionexContractLibEIP712.Order memory _order,
        bytes32 _orderHash,
        bytes memory _orderMakerSig
    ) internal view {
        require(_order.expiry > uint64(block.timestamp), "LimitOrder: Order is expired");
        bool isCancelled = LibPionexContractOrderStorage.getStorage().orderHashToCancelled[_orderHash];
        require(!isCancelled, "LimitOrder: Order is cancelled");

        require(isValidSignature(_order.maker, _orderHash, bytes(""), _orderMakerSig), "LimitOrder: Order is not signed by maker");
    }

    function _validateOrderTaker(PionexContractLibEIP712.Order memory _order, address _taker) internal pure {
        if (_order.taker != address(0)) {
            require(_order.taker == _taker, "LimitOrder: Order cannot be filled by this taker");
        }
    }

    function _quoteOrderFromMakerToken(
        PionexContractLibEIP712.Order memory _order,
        bytes32 _orderHash,
        uint256 _makerTokenAmount
    ) internal view returns (uint256, uint256) {
        uint256 makerTokenFilledAmount = LibPionexContractOrderStorage.getStorage().orderHashToMakerTokenFilledAmount[_orderHash];

        require(makerTokenFilledAmount < _order.makerTokenAmount, "LimitOrder: Order is filled");

        uint256 makerTokenFillableAmount = _order.makerTokenAmount.sub(makerTokenFilledAmount);
        uint256 makerTokenQuota = Math.min(_makerTokenAmount, makerTokenFillableAmount);
        uint256 remainingAfterFill = makerTokenFillableAmount.sub(makerTokenQuota);

        require(makerTokenQuota != 0, "LimitOrder: zero token amount");
        return (makerTokenQuota, remainingAfterFill);
    }

    function _recordMakerTokenFilled(bytes32 _orderHash, uint256 _makerTokenAmount) internal {
        LibPionexContractOrderStorage.Storage storage stor = LibPionexContractOrderStorage.getStorage();
        uint256 makerTokenFilledAmount = stor.orderHashToMakerTokenFilledAmount[_orderHash];
        stor.orderHashToMakerTokenFilledAmount[_orderHash] = makerTokenFilledAmount.add(_makerTokenAmount);
    }

    /* math utils */

    function _mulFactor(uint256 amount, uint256 factor) internal pure returns (uint256) {
        return amount.mul(factor).div(LibConstant.BPS_MAX);
    }

    /* event utils */

    struct LimitOrderFilledByTraderParams {
        bytes32 orderHash;
        address maker;
        address taker;
        bytes32 allowFillHash;
        address recipient;
        address makerToken;
        address takerToken;
        uint256 makerTokenFilledAmount;
        uint256 takerTokenFilledAmount;
        uint256 remainingAmount;
        uint256 takerTokenFee;
    }

    function _emitLimitOrderFilledByTrader(LimitOrderFilledByTraderParams memory _params) internal {
        emit LimitOrderFilledByTrader(
            _params.orderHash,
            _params.maker,
            _params.taker,
            _params.allowFillHash,
            _params.recipient,
            FillReceipt({
                makerToken: _params.makerToken,
                takerToken: _params.takerToken,
                makerTokenFilledAmount: _params.makerTokenFilledAmount,
                takerTokenFilledAmount: _params.takerTokenFilledAmount,
                remainingAmount: _params.remainingAmount,
                takerTokenFee: _params.takerTokenFee
            })
        );
    }
}
