// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./interfaces/ILimitOrder.sol";
import "./interfaces/IPermanentStorage.sol";
import "./interfaces/ISpender.sol";
import "./interfaces/IWeth.sol";
import "./utils/BaseLibEIP712.sol";
import "./utils/LibConstant.sol";
import "./utils/LibUniswapV2.sol";
import "./utils/LibUniswapV3.sol";
import "./utils/LibOrderStorage.sol";
import "./utils/LimitOrderLibEIP712.sol";
import "./utils/SignatureValidator.sol";

contract LimitOrder is ILimitOrder, BaseLibEIP712, SignatureValidator, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IPermanentStorage public immutable permStorage;
    address public immutable userProxy;
    IWETH public immutable weth;

    // AMM
    address public immutable uniswapV3RouterAddress;
    address public immutable sushiswapRouterAddress;

    // Below are the variables which consume storage slots.
    address public operator;
    address public coordinator;
    ISpender public spender;
    address public feeCollector;

    // Factors
    uint16 public makerFeeFactor = 0;
    uint16 public takerFeeFactor = 0;
    uint16 public profitFeeFactor = 0;

    constructor(
        address _operator,
        address _coordinator,
        address _userProxy,
        ISpender _spender,
        IPermanentStorage _permStorage,
        IWETH _weth,
        address _uniswapV3RouterAddress,
        address _sushiswapRouterAddress,
        address _feeCollector
    ) {
        operator = _operator;
        coordinator = _coordinator;
        userProxy = _userProxy;
        spender = _spender;
        permStorage = _permStorage;
        weth = _weth;
        uniswapV3RouterAddress = _uniswapV3RouterAddress;
        sushiswapRouterAddress = _sushiswapRouterAddress;
        feeCollector = _feeCollector;
    }

    receive() external payable {}

    modifier onlyOperator() {
        require(operator == msg.sender, "LimitOrder: not operator");
        _;
    }

    modifier onlyUserProxy() {
        require(address(userProxy) == msg.sender, "LimitOrder: not the UserProxy contract");
        _;
    }

    function transferOwnership(address _newOperator) external onlyOperator {
        require(_newOperator != address(0), "LimitOrder: operator can not be zero address");
        operator = _newOperator;

        emit TransferOwnership(_newOperator);
    }

    function upgradeSpender(address _newSpender) external onlyOperator {
        require(_newSpender != address(0), "LimitOrder: spender can not be zero address");
        spender = ISpender(_newSpender);

        emit UpgradeSpender(_newSpender);
    }

    function upgradeCoordinator(address _newCoordinator) external onlyOperator {
        require(_newCoordinator != address(0), "LimitOrder: coordinator can not be zero address");
        coordinator = _newCoordinator;

        emit UpgradeCoordinator(_newCoordinator);
    }

    /**
     * @dev approve spender to transfer tokens from this contract. This is used to collect fee.
     */
    function setAllowance(address[] calldata _tokenList, address _spender) external onlyOperator {
        for (uint256 i = 0; i < _tokenList.length; i++) {
            IERC20(_tokenList[i]).safeApprove(_spender, LibConstant.MAX_UINT);

            emit AllowTransfer(_spender);
        }
    }

    function closeAllowance(address[] calldata _tokenList, address _spender) external onlyOperator {
        for (uint256 i = 0; i < _tokenList.length; i++) {
            IERC20(_tokenList[i]).safeApprove(_spender, 0);

            emit DisallowTransfer(_spender);
        }
    }

    /**
     * @dev convert collected ETH to WETH
     */
    function depositETH() external onlyOperator {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            weth.deposit{ value: balance }();

            emit DepositETH(balance);
        }
    }

    function setFactors(
        uint16 _makerFeeFactor,
        uint16 _takerFeeFactor,
        uint16 _profitFeeFactor
    ) external onlyOperator {
        require(_makerFeeFactor <= LibConstant.BPS_MAX, "LimitOrder: Invalid maker fee factor");
        require(_takerFeeFactor <= LibConstant.BPS_MAX, "LimitOrder: Invalid taker fee factor");
        require(_profitFeeFactor <= LibConstant.BPS_MAX, "LimitOrder: Invalid profit fee factor");

        makerFeeFactor = _makerFeeFactor;
        takerFeeFactor = _takerFeeFactor;
        profitFeeFactor = _profitFeeFactor;

        emit FactorsUpdated(_makerFeeFactor, _takerFeeFactor, _profitFeeFactor);
    }

    /**
     * @dev set fee collector
     */
    function setFeeCollector(address _newFeeCollector) external onlyOperator {
        require(_newFeeCollector != address(0), "LimitOrder: fee collector can not be zero address");
        feeCollector = _newFeeCollector;

        emit SetFeeCollector(_newFeeCollector);
    }

    /**
     * Fill limit order by trader
     */
    function fillLimitOrderByTrader(
        LimitOrderLibEIP712.Order calldata _order,
        bytes calldata _orderMakerSig,
        TraderParams calldata _params,
        CoordinatorParams calldata _crdParams
    ) external override onlyUserProxy nonReentrant returns (uint256, uint256) {
        bytes32 orderHash = getEIP712Hash(LimitOrderLibEIP712._getOrderStructHash(_order));

        _validateOrder(_order, orderHash, _orderMakerSig);
        bytes32 allowFillHash = _validateFillPermission(orderHash, _params.takerTokenAmount, _params.taker, _crdParams);
        _validateOrderTaker(_order, _params.taker);

        {
            LimitOrderLibEIP712.Fill memory fill = LimitOrderLibEIP712.Fill({
                orderHash: orderHash,
                taker: _params.taker,
                recipient: _params.recipient,
                takerTokenAmount: _params.takerTokenAmount,
                takerSalt: _params.salt,
                expiry: _params.expiry
            });
            _validateTraderFill(fill, _params.takerSig);
        }

        (uint256 makerTokenAmount, uint256 takerTokenAmount, uint256 remainingAmount) = _quoteOrder(_order, orderHash, _params.takerTokenAmount);

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

        _recordOrderFilled(orderHash, takerTokenAmount);

        return (takerTokenAmount, makerTokenOut);
    }

    function _validateTraderFill(LimitOrderLibEIP712.Fill memory _fill, bytes memory _fillTakerSig) internal {
        require(_fill.expiry > uint64(block.timestamp), "LimitOrder: Fill request is expired");

        bytes32 fillHash = getEIP712Hash(LimitOrderLibEIP712._getFillStructHash(_fill));
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
            LimitOrderLibEIP712._getAllowFillStructHash(
                LimitOrderLibEIP712.AllowFill({
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
        // Calculate maker fee (maker receives taker token so fee is charged in taker token)
        uint256 takerTokenFee = _mulFactor(_settlement.takerTokenAmount, makerFeeFactor);
        uint256 takerTokenForMaker = _settlement.takerTokenAmount.sub(takerTokenFee);

        // Calculate taker fee (taker receives maker token so fee is charged in maker token)
        uint256 makerTokenFee = _mulFactor(_settlement.makerTokenAmount, takerFeeFactor);
        uint256 makerTokenForTrader = _settlement.makerTokenAmount.sub(makerTokenFee);

        // trader -> maker
        spender.spendFromUserTo(_settlement.trader, address(_settlement.takerToken), _settlement.maker, takerTokenForMaker);

        // maker -> recipient
        spender.spendFromUserTo(_settlement.maker, address(_settlement.makerToken), _settlement.recipient, makerTokenForTrader);

        // Collect maker fee (charged in taker token)
        if (takerTokenFee > 0) {
            spender.spendFromUserTo(_settlement.trader, address(_settlement.takerToken), feeCollector, takerTokenFee);
        }
        // Collect taker fee (charged in maker token)
        if (makerTokenFee > 0) {
            spender.spendFromUserTo(_settlement.maker, address(_settlement.makerToken), feeCollector, makerTokenFee);
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
                makerTokenFee: makerTokenFee,
                takerTokenFee: takerTokenFee
            })
        );

        return makerTokenForTrader;
    }

    /**
     * Fill limit order by protocol
     */
    function fillLimitOrderByProtocol(
        LimitOrderLibEIP712.Order calldata _order,
        bytes calldata _orderMakerSig,
        ProtocolParams calldata _params,
        CoordinatorParams calldata _crdParams
    ) external override onlyUserProxy nonReentrant returns (uint256) {
        bytes32 orderHash = getEIP712Hash(LimitOrderLibEIP712._getOrderStructHash(_order));

        _validateOrder(_order, orderHash, _orderMakerSig);
        bytes32 allowFillHash = _validateFillPermission(orderHash, _params.takerTokenAmount, tx.origin, _crdParams);

        address protocolAddress = _getProtocolAddress(_params.protocol);
        _validateOrderTaker(_order, protocolAddress);

        (uint256 makerTokenAmount, uint256 takerTokenAmount, uint256 remainingAmount) = _quoteOrder(_order, orderHash, _params.takerTokenAmount);

        uint256 relayerTakerTokenProfit = _settleForProtocol(
            ProtocolSettlement({
                orderHash: orderHash,
                allowFillHash: allowFillHash,
                protocolAddress: protocolAddress,
                protocol: _params.protocol,
                data: _params.data,
                relayer: tx.origin,
                profitRecipient: _params.profitRecipient,
                maker: _order.maker,
                taker: _order.taker,
                makerToken: _order.makerToken,
                takerToken: _order.takerToken,
                makerTokenAmount: makerTokenAmount,
                takerTokenAmount: takerTokenAmount,
                remainingAmount: remainingAmount,
                protocolOutMinimum: _params.protocolOutMinimum,
                expiry: _params.expiry
            })
        );

        _recordOrderFilled(orderHash, takerTokenAmount);

        return relayerTakerTokenProfit;
    }

    function _getProtocolAddress(Protocol protocol) internal view returns (address) {
        if (protocol == Protocol.UniswapV3) {
            return uniswapV3RouterAddress;
        }
        if (protocol == Protocol.Sushiswap) {
            return sushiswapRouterAddress;
        }
        revert("LimitOrder: Unknown protocol");
    }

    struct ProtocolSettlement {
        bytes32 orderHash;
        bytes32 allowFillHash;
        address protocolAddress;
        Protocol protocol;
        bytes data;
        address relayer;
        address profitRecipient;
        address maker;
        address taker;
        IERC20 makerToken;
        IERC20 takerToken;
        uint256 makerTokenAmount;
        uint256 takerTokenAmount;
        uint256 remainingAmount;
        uint256 protocolOutMinimum;
        uint64 expiry;
    }

    function _settleForProtocol(ProtocolSettlement memory _settlement) internal returns (uint256) {
        // Collect maker token from maker in order to swap through protocol
        spender.spendFromUserTo(_settlement.maker, address(_settlement.makerToken), address(this), _settlement.makerTokenAmount);

        uint256 takerTokenOut = _swapByProtocol(_settlement);

        require(takerTokenOut >= _settlement.takerTokenAmount, "LimitOrder: Insufficient token amount out from protocol");

        uint256 ammOutputExtra = takerTokenOut.sub(_settlement.takerTokenAmount);
        uint256 relayerTakerTokenProfitFee = _mulFactor(ammOutputExtra, profitFeeFactor);
        uint256 relayerTakerTokenProfit = ammOutputExtra.sub(relayerTakerTokenProfitFee);
        // Distribute taker token profit to profit recipient assigned by relayer
        _settlement.takerToken.safeTransfer(_settlement.profitRecipient, relayerTakerTokenProfit);

        // Calculate maker fee (maker receives taker token so fee is charged in taker token)
        uint256 takerTokenFee = _mulFactor(_settlement.takerTokenAmount, makerFeeFactor);
        uint256 takerTokenForMaker = _settlement.takerTokenAmount.sub(takerTokenFee);

        // Distribute taker token to maker
        _settlement.takerToken.safeTransfer(_settlement.maker, takerTokenForMaker);

        // Collect fee in taker token if any
        uint256 feeTotal = takerTokenFee.add(relayerTakerTokenProfitFee);
        if (feeTotal > 0) {
            _settlement.takerToken.safeTransfer(feeCollector, feeTotal);
        }

        // Bypass stack too deep error
        _emitLimitOrderFilledByProtocol(
            LimitOrderFilledByProtocolParams({
                orderHash: _settlement.orderHash,
                maker: _settlement.maker,
                taker: _settlement.protocolAddress,
                allowFillHash: _settlement.allowFillHash,
                relayer: _settlement.relayer,
                profitRecipient: _settlement.profitRecipient,
                makerToken: address(_settlement.makerToken),
                takerToken: address(_settlement.takerToken),
                makerTokenFilledAmount: _settlement.makerTokenAmount,
                takerTokenFilledAmount: _settlement.takerTokenAmount,
                remainingAmount: _settlement.remainingAmount,
                makerTokenFee: 0,
                takerTokenFee: takerTokenFee,
                relayerTakerTokenProfit: relayerTakerTokenProfit,
                relayerTakerTokenProfitFee: relayerTakerTokenProfitFee
            })
        );

        return relayerTakerTokenProfit;
    }

    function _swapByProtocol(ProtocolSettlement memory _settlement) internal returns (uint256 amountOut) {
        _settlement.makerToken.safeApprove(_settlement.protocolAddress, _settlement.makerTokenAmount);

        // UniswapV3
        if (_settlement.protocol == Protocol.UniswapV3) {
            amountOut = LibUniswapV3.exactInput(
                _settlement.protocolAddress,
                LibUniswapV3.ExactInputParams({
                    tokenIn: address(_settlement.makerToken),
                    tokenOut: address(_settlement.takerToken),
                    path: _settlement.data,
                    recipient: address(this),
                    deadline: _settlement.expiry,
                    amountIn: _settlement.makerTokenAmount,
                    amountOutMinimum: _settlement.protocolOutMinimum
                })
            );
        } else {
            // Sushiswap
            address[] memory path = abi.decode(_settlement.data, (address[]));
            amountOut = LibUniswapV2.swapExactTokensForTokens(
                _settlement.protocolAddress,
                LibUniswapV2.SwapExactTokensForTokensParams({
                    tokenIn: address(_settlement.makerToken),
                    tokenInAmount: _settlement.makerTokenAmount,
                    tokenOut: address(_settlement.takerToken),
                    tokenOutAmountMin: _settlement.protocolOutMinimum,
                    path: path,
                    to: address(this),
                    deadline: _settlement.expiry
                })
            );
        }

        _settlement.makerToken.safeApprove(_settlement.protocolAddress, 0);
    }

    /**
     * Cancel limit order
     */
    function cancelLimitOrder(LimitOrderLibEIP712.Order calldata _order, bytes calldata _cancelOrderMakerSig) external override onlyUserProxy nonReentrant {
        require(_order.expiry > uint64(block.timestamp), "LimitOrder: Order is expired");
        bytes32 orderHash = getEIP712Hash(LimitOrderLibEIP712._getOrderStructHash(_order));
        bool isCancelled = LibOrderStorage.getStorage().orderHashToCancelled[orderHash];
        require(!isCancelled, "LimitOrder: Order is cancelled already");
        {
            LimitOrderLibEIP712.Order memory cancelledOrder = _order;
            cancelledOrder.takerTokenAmount = 0;

            bytes32 cancelledOrderHash = getEIP712Hash(LimitOrderLibEIP712._getOrderStructHash(cancelledOrder));
            require(isValidSignature(_order.maker, cancelledOrderHash, bytes(""), _cancelOrderMakerSig), "LimitOrder: Cancel request is not signed by maker");
        }

        // Set cancelled state to storage
        LibOrderStorage.getStorage().orderHashToCancelled[orderHash] = true;
        emit OrderCancelled(orderHash, _order.maker);
    }

    /* order utils */

    function _validateOrder(
        LimitOrderLibEIP712.Order memory _order,
        bytes32 _orderHash,
        bytes memory _orderMakerSig
    ) internal view {
        require(_order.expiry > uint64(block.timestamp), "LimitOrder: Order is expired");
        bool isCancelled = LibOrderStorage.getStorage().orderHashToCancelled[_orderHash];
        require(!isCancelled, "LimitOrder: Order is cancelled");

        require(isValidSignature(_order.maker, _orderHash, bytes(""), _orderMakerSig), "LimitOrder: Order is not signed by maker");
    }

    function _validateOrderTaker(LimitOrderLibEIP712.Order memory _order, address _taker) internal pure {
        if (_order.taker != address(0)) {
            require(_order.taker == _taker, "LimitOrder: Order cannot be filled by this taker");
        }
    }

    function _quoteOrder(
        LimitOrderLibEIP712.Order memory _order,
        bytes32 _orderHash,
        uint256 _takerTokenAmount
    )
        internal
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 takerTokenFilledAmount = LibOrderStorage.getStorage().orderHashToTakerTokenFilledAmount[_orderHash];

        require(takerTokenFilledAmount < _order.takerTokenAmount, "LimitOrder: Order is filled");

        uint256 takerTokenFillableAmount = _order.takerTokenAmount.sub(takerTokenFilledAmount);
        uint256 takerTokenQuota = Math.min(_takerTokenAmount, takerTokenFillableAmount);
        uint256 makerTokenQuota = takerTokenQuota.mul(_order.makerTokenAmount).div(_order.takerTokenAmount);
        uint256 remainingAfterFill = takerTokenFillableAmount.sub(takerTokenQuota);

        return (makerTokenQuota, takerTokenQuota, remainingAfterFill);
    }

    function _recordOrderFilled(bytes32 _orderHash, uint256 _takerTokenAmount) internal {
        LibOrderStorage.Storage storage stor = LibOrderStorage.getStorage();
        uint256 takerTokenFilledAmount = stor.orderHashToTakerTokenFilledAmount[_orderHash];
        stor.orderHashToTakerTokenFilledAmount[_orderHash] = takerTokenFilledAmount.add(_takerTokenAmount);
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
        uint256 makerTokenFee;
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
                makerTokenFee: _params.makerTokenFee,
                takerTokenFee: _params.takerTokenFee
            })
        );
    }

    struct LimitOrderFilledByProtocolParams {
        bytes32 orderHash;
        address maker;
        address taker;
        bytes32 allowFillHash;
        address relayer;
        address profitRecipient;
        address makerToken;
        address takerToken;
        uint256 makerTokenFilledAmount;
        uint256 takerTokenFilledAmount;
        uint256 remainingAmount;
        uint256 makerTokenFee;
        uint256 takerTokenFee;
        uint256 relayerTakerTokenProfit;
        uint256 relayerTakerTokenProfitFee;
    }

    function _emitLimitOrderFilledByProtocol(LimitOrderFilledByProtocolParams memory _params) internal {
        emit LimitOrderFilledByProtocol(
            _params.orderHash,
            _params.maker,
            _params.taker,
            _params.allowFillHash,
            _params.relayer,
            _params.profitRecipient,
            FillReceipt({
                makerToken: _params.makerToken,
                takerToken: _params.takerToken,
                makerTokenFilledAmount: _params.makerTokenFilledAmount,
                takerTokenFilledAmount: _params.takerTokenFilledAmount,
                remainingAmount: _params.remainingAmount,
                makerTokenFee: _params.makerTokenFee,
                takerTokenFee: _params.takerTokenFee
            }),
            _params.relayerTakerTokenProfit,
            _params.relayerTakerTokenProfitFee
        );
    }
}
