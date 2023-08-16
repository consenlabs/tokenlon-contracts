// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./interfaces/ISignalBuyContract.sol";
import "./interfaces/IWETH.sol";
import { Asset } from "./utils/Asset.sol";
import "./utils/BaseLibEIP712.sol";
import "./utils/LibConstant.sol";
import "./utils/LibSignalBuyContractOrderStorage.sol";
import "./utils/Ownable.sol";
import { Order, getOrderStructHash, Fill, getFillStructHash, AllowFill, getAllowFillStructHash } from "./utils/SignalBuyContractLibEIP712.sol";
import "./utils/SignatureValidator.sol";

/// @title SignalBuy Contract
/// @notice Order can be filled as long as the provided dealerToken/userToken ratio is better than or equal to user's specfied dealerToken/userToken ratio.
/// @author imToken Labs
contract SignalBuyContract is ISignalBuyContract, BaseLibEIP712, SignatureValidator, ReentrancyGuard, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Asset for address;

    IWETH public immutable weth;
    uint256 public immutable factorActivateDelay;

    // Below are the variables which consume storage slots.
    address public coordinator;
    address public feeCollector;

    // Factors
    uint256 public factorsTimeLock;
    uint16 public tokenlonFeeFactor = 0;
    uint16 public pendingTokenlonFeeFactor;

    mapping(bytes32 => uint256) public filledAmount;

    /// @notice Emitted when allowing another account to spend assets
    /// @param spender The address that is allowed to transfer tokens
    event AllowTransfer(address indexed spender, address token);

    /// @notice Emitted when disallowing an account to spend assets
    /// @param spender The address that is removed from allow list
    event DisallowTransfer(address indexed spender, address token);

    /// @notice Emitted when ETH converted to WETH
    /// @param amount The amount of converted ETH
    event DepositETH(uint256 amount);

    constructor(
        address _owner,
        address _weth,
        address _coordinator,
        uint256 _factorActivateDelay,
        address _feeCollector
    ) Ownable(_owner) {
        weth = IWETH(_weth);
        coordinator = _coordinator;
        factorActivateDelay = _factorActivateDelay;
        feeCollector = _feeCollector;
    }

    receive() external payable {}

    /// @notice Set allowance of tokens to an address
    /// @notice Only owner can call
    /// @param _tokenList The list of tokens
    /// @param _spender The address that will be allowed
    function setAllowance(address[] calldata _tokenList, address _spender) external onlyOwner {
        for (uint256 i = 0; i < _tokenList.length; ++i) {
            IERC20(_tokenList[i]).safeApprove(_spender, LibConstant.MAX_UINT);

            emit AllowTransfer(_spender, _tokenList[i]);
        }
    }

    /// @notice Clear allowance of tokens to an address
    /// @notice Only owner can call
    /// @param _tokenList The list of tokens
    /// @param _spender The address that will be cleared
    function closeAllowance(address[] calldata _tokenList, address _spender) external onlyOwner {
        for (uint256 i = 0; i < _tokenList.length; ++i) {
            IERC20(_tokenList[i]).safeApprove(_spender, 0);

            emit DisallowTransfer(_spender, _tokenList[i]);
        }
    }

    /// @notice Convert ETH in this contract to WETH
    /// @notice Only owner can call
    function depositETH() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            weth.deposit{ value: balance }();

            emit DepositETH(balance);
        }
    }

    /// @notice Only owner can call
    /// @param _newCoordinator The new address of coordinator
    function upgradeCoordinator(address _newCoordinator) external onlyOwner {
        require(_newCoordinator != address(0), "SignalBuyContract: coordinator can not be zero address");
        coordinator = _newCoordinator;

        emit UpgradeCoordinator(_newCoordinator);
    }

    /// @notice Only owner can call
    /// @param _tokenlonFeeFactor The new fee factor for user
    function setFactors(uint16 _tokenlonFeeFactor) external onlyOwner {
        require(_tokenlonFeeFactor <= LibConstant.BPS_MAX, "SignalBuyContract: Invalid user fee factor");

        pendingTokenlonFeeFactor = _tokenlonFeeFactor;

        factorsTimeLock = block.timestamp + factorActivateDelay;
    }

    /// @notice Only owner can call
    function activateFactors() external onlyOwner {
        require(factorsTimeLock != 0, "SignalBuyContract: no pending fee factors");
        require(block.timestamp >= factorsTimeLock, "SignalBuyContract: fee factors timelocked");
        factorsTimeLock = 0;
        tokenlonFeeFactor = pendingTokenlonFeeFactor;
        pendingTokenlonFeeFactor = 0;

        emit FactorsUpdated(tokenlonFeeFactor);
    }

    /// @notice Only owner can call
    /// @param _newFeeCollector The new address of fee collector
    function setFeeCollector(address _newFeeCollector) external onlyOwner {
        require(_newFeeCollector != address(0), "SignalBuyContract: fee collector can not be zero address");
        feeCollector = _newFeeCollector;

        emit SetFeeCollector(_newFeeCollector);
    }

    /// @inheritdoc ISignalBuyContract
    function fillSignalBuy(
        Order calldata _order,
        bytes calldata _orderUserSig,
        TraderParams calldata _params,
        CoordinatorParams calldata _crdParams
    ) external payable override nonReentrant returns (uint256, uint256) {
        bytes32 orderHash = getEIP712Hash(getOrderStructHash(_order));

        _validateOrder(_order, orderHash, _orderUserSig);
        bytes32 allowFillHash = _validateFillPermission(orderHash, _params.dealerTokenAmount, _params.dealer, _crdParams);
        _validateOrderTaker(_order, _params.dealer);

        // Check gas fee factor and dealer strategy fee factor do not exceed limit
        require(
            (_params.gasFeeFactor <= LibConstant.BPS_MAX) &&
                (_params.dealerStrategyFeeFactor <= LibConstant.BPS_MAX) &&
                (_params.gasFeeFactor + _params.dealerStrategyFeeFactor <= LibConstant.BPS_MAX - tokenlonFeeFactor),
            "SignalBuyContract: Invalid dealer fee factor"
        );

        {
            Fill memory fill = Fill({
                orderHash: orderHash,
                dealer: _params.dealer,
                recipient: _params.recipient,
                userTokenAmount: _params.userTokenAmount,
                dealerTokenAmount: _params.dealerTokenAmount,
                dealerSalt: _params.salt,
                expiry: _params.expiry
            });
            _validateTraderFill(fill, _params.dealerSig);
        }

        (uint256 userTokenAmount, uint256 remainingUserTokenAmount) = _quoteOrderFromUserToken(_order, orderHash, _params.userTokenAmount);
        // Calculate dealerTokenAmount according to the provided dealerToken/userToken ratio
        uint256 dealerTokenAmount = userTokenAmount.mul(_params.dealerTokenAmount).div(_params.userTokenAmount);
        // Calculate minimum dealerTokenAmount according to the offer's dealerToken/userToken ratio
        uint256 minDealerTokenAmount = userTokenAmount.mul(_order.minDealerTokenAmount).div(_order.userTokenAmount);

        _settleForTrader(
            TraderSettlement({
                orderHash: orderHash,
                allowFillHash: allowFillHash,
                trader: _params.dealer,
                recipient: _params.recipient,
                user: _order.user,
                userToken: _order.userToken,
                dealerToken: _order.dealerToken,
                userTokenAmount: userTokenAmount,
                dealerTokenAmount: dealerTokenAmount,
                minDealerTokenAmount: minDealerTokenAmount,
                remainingUserTokenAmount: remainingUserTokenAmount,
                gasFeeFactor: _params.gasFeeFactor,
                dealerStrategyFeeFactor: _params.dealerStrategyFeeFactor
            })
        );

        _recordUserTokenFilled(orderHash, userTokenAmount);

        return (dealerTokenAmount, userTokenAmount);
    }

    function _validateTraderFill(Fill memory _fill, bytes memory _fillTakerSig) internal {
        require(_fill.expiry > uint64(block.timestamp), "SignalBuyContract: Fill request is expired");
        require(_fill.recipient != address(0), "SignalBuyContract: recipient can not be zero address");

        bytes32 fillHash = getEIP712Hash(getFillStructHash(_fill));
        require(!LibSignalBuyContractOrderStorage.getStorage().fillSeen[fillHash], "SignalBuyContract: Fill seen before");
        require(isValidSignature(_fill.dealer, fillHash, bytes(""), _fillTakerSig), "SignalBuyContract: Fill is not signed by dealer");

        // Set fill seen to avoid replay attack.
        LibSignalBuyContractOrderStorage.getStorage().fillSeen[fillHash] = true;
    }

    function _validateFillPermission(
        bytes32 _orderHash,
        uint256 _fillAmount,
        address _executor,
        CoordinatorParams memory _crdParams
    ) internal returns (bytes32) {
        require(_crdParams.expiry > uint64(block.timestamp), "SignalBuyContract: Fill permission is expired");

        bytes32 allowFillHash = getEIP712Hash(
            getAllowFillStructHash(
                AllowFill({ orderHash: _orderHash, executor: _executor, fillAmount: _fillAmount, salt: _crdParams.salt, expiry: _crdParams.expiry })
            )
        );
        require(!LibSignalBuyContractOrderStorage.getStorage().fillSeen[allowFillHash], "SignalBuyContract: AllowFill seen before");
        require(isValidSignature(coordinator, allowFillHash, bytes(""), _crdParams.sig), "SignalBuyContract: AllowFill is not signed by coordinator");

        // Set allow fill seen to avoid replay attack
        LibSignalBuyContractOrderStorage.getStorage().allowFillSeen[allowFillHash] = true;

        return allowFillHash;
    }

    struct TraderSettlement {
        bytes32 orderHash;
        bytes32 allowFillHash;
        address trader;
        address recipient;
        address user;
        IERC20 userToken;
        IERC20 dealerToken;
        uint256 userTokenAmount;
        uint256 dealerTokenAmount;
        uint256 minDealerTokenAmount;
        uint256 remainingUserTokenAmount;
        uint16 gasFeeFactor;
        uint16 dealerStrategyFeeFactor;
    }

    function _settleForTrader(TraderSettlement memory _settlement) internal {
        // memory cache
        address _feeCollector = feeCollector;

        // Calculate user fee (user receives dealer token so fee is charged in dealer token)
        // 1. Fee for Tokenlon
        uint256 tokenlonFee = _mulFactor(_settlement.dealerTokenAmount, tokenlonFeeFactor);
        // 2. Fee for SignalBuy, including gas fee and strategy fee
        uint256 dealerFee = _mulFactor(_settlement.dealerTokenAmount, _settlement.gasFeeFactor + _settlement.dealerStrategyFeeFactor);
        uint256 dealerTokenForUserAndTokenlon = _settlement.dealerTokenAmount.sub(dealerFee);
        uint256 dealerTokenForUser = dealerTokenForUserAndTokenlon.sub(tokenlonFee);
        require(dealerTokenForUser >= _settlement.minDealerTokenAmount, "SignalBuyContract: dealer token amount not enough");

        // trader -> user
        address _weth = address(weth); // cache
        if (address(_settlement.dealerToken).isETH()) {
            if (msg.value > 0) {
                // User wants ETH and dealer pays in ETH
                require(msg.value == dealerTokenForUserAndTokenlon, "SignalBuyContract: mismatch dealer token (ETH) amount");
            } else {
                // User wants ETH but dealer pays in WETH
                IERC20(_weth).safeTransferFrom(_settlement.trader, address(this), dealerTokenForUserAndTokenlon);
                weth.withdraw(dealerTokenForUserAndTokenlon);
            }
            // Send ETH to user
            LibConstant.ETH_ADDRESS.transferTo(payable(_settlement.user), dealerTokenForUser);
        } else if (address(_settlement.dealerToken) == _weth) {
            if (msg.value > 0) {
                // User wants WETH but dealer pays in ETH
                require(msg.value == dealerTokenForUserAndTokenlon, "SignalBuyContract: mismatch dealer token (ETH) amount");
                weth.deposit{ value: dealerTokenForUserAndTokenlon }();
                weth.transfer(_settlement.user, dealerTokenForUser);
            } else {
                // User wants WETH and dealer pays in WETH
                IERC20(_weth).safeTransferFrom(_settlement.trader, _settlement.user, dealerTokenForUser);
            }
        } else {
            _settlement.dealerToken.safeTransferFrom(_settlement.trader, _settlement.user, dealerTokenForUser);
        }

        // user -> recipient
        _settlement.userToken.safeTransferFrom(_settlement.user, _settlement.recipient, _settlement.userTokenAmount);

        // Collect user fee (charged in dealer token)
        if (tokenlonFee > 0) {
            if (address(_settlement.dealerToken).isETH()) {
                LibConstant.ETH_ADDRESS.transferTo(payable(_feeCollector), tokenlonFee);
            } else if (address(_settlement.dealerToken) == _weth) {
                if (msg.value > 0) {
                    weth.transfer(_feeCollector, tokenlonFee);
                } else {
                    weth.transferFrom(_settlement.trader, _feeCollector, tokenlonFee);
                }
            } else {
                _settlement.dealerToken.safeTransferFrom(_settlement.trader, _feeCollector, tokenlonFee);
            }
        }

        // bypass stack too deep error
        _emitSignalBuyFilledByTrader(
            SignalBuyFilledByTraderParams({
                orderHash: _settlement.orderHash,
                user: _settlement.user,
                dealer: _settlement.trader,
                allowFillHash: _settlement.allowFillHash,
                recipient: _settlement.recipient,
                userToken: address(_settlement.userToken),
                dealerToken: address(_settlement.dealerToken),
                userTokenFilledAmount: _settlement.userTokenAmount,
                dealerTokenFilledAmount: _settlement.dealerTokenAmount,
                remainingUserTokenAmount: _settlement.remainingUserTokenAmount,
                tokenlonFee: tokenlonFee,
                dealerFee: dealerFee
            })
        );
    }

    /// @inheritdoc ISignalBuyContract
    function cancelSignalBuy(Order calldata _order, bytes calldata _cancelOrderUserSig) external override nonReentrant {
        require(_order.expiry > uint64(block.timestamp), "SignalBuyContract: Order is expired");
        bytes32 orderHash = getEIP712Hash(getOrderStructHash(_order));
        bool isCancelled = LibSignalBuyContractOrderStorage.getStorage().orderHashToCancelled[orderHash];
        require(!isCancelled, "SignalBuyContract: Order is cancelled already");
        {
            Order memory cancelledOrder = _order;
            cancelledOrder.minDealerTokenAmount = 0;

            bytes32 cancelledOrderHash = getEIP712Hash(getOrderStructHash(cancelledOrder));
            require(
                isValidSignature(_order.user, cancelledOrderHash, bytes(""), _cancelOrderUserSig),
                "SignalBuyContract: Cancel request is not signed by user"
            );
        }

        // Set cancelled state to storage
        LibSignalBuyContractOrderStorage.getStorage().orderHashToCancelled[orderHash] = true;
        emit OrderCancelled(orderHash, _order.user);
    }

    /* order utils */

    function _validateOrder(
        Order memory _order,
        bytes32 _orderHash,
        bytes memory _orderUserSig
    ) internal view {
        require(_order.expiry > uint64(block.timestamp), "SignalBuyContract: Order is expired");
        bool isCancelled = LibSignalBuyContractOrderStorage.getStorage().orderHashToCancelled[_orderHash];
        require(!isCancelled, "SignalBuyContract: Order is cancelled");

        require(isValidSignature(_order.user, _orderHash, bytes(""), _orderUserSig), "SignalBuyContract: Order is not signed by user");
    }

    function _validateOrderTaker(Order memory _order, address _dealer) internal pure {
        if (_order.dealer != address(0)) {
            require(_order.dealer == _dealer, "SignalBuyContract: Order cannot be filled by this dealer");
        }
    }

    function _quoteOrderFromUserToken(
        Order memory _order,
        bytes32 _orderHash,
        uint256 _userTokenAmount
    ) internal view returns (uint256, uint256) {
        uint256 userTokenFilledAmount = LibSignalBuyContractOrderStorage.getStorage().orderHashToUserTokenFilledAmount[_orderHash];

        require(userTokenFilledAmount < _order.userTokenAmount, "SignalBuyContract: Order is filled");

        uint256 userTokenFillableAmount = _order.userTokenAmount.sub(userTokenFilledAmount);
        uint256 userTokenQuota = Math.min(_userTokenAmount, userTokenFillableAmount);
        uint256 remainingAfterFill = userTokenFillableAmount.sub(userTokenQuota);

        require(userTokenQuota != 0, "SignalBuyContract: zero token amount");
        return (userTokenQuota, remainingAfterFill);
    }

    function _recordUserTokenFilled(bytes32 _orderHash, uint256 _userTokenAmount) internal {
        LibSignalBuyContractOrderStorage.Storage storage stor = LibSignalBuyContractOrderStorage.getStorage();
        uint256 userTokenFilledAmount = stor.orderHashToUserTokenFilledAmount[_orderHash];
        stor.orderHashToUserTokenFilledAmount[_orderHash] = userTokenFilledAmount.add(_userTokenAmount);
    }

    /* math utils */

    function _mulFactor(uint256 amount, uint256 factor) internal pure returns (uint256) {
        return amount.mul(factor).div(LibConstant.BPS_MAX);
    }

    /* event utils */

    struct SignalBuyFilledByTraderParams {
        bytes32 orderHash;
        address user;
        address dealer;
        bytes32 allowFillHash;
        address recipient;
        address userToken;
        address dealerToken;
        uint256 userTokenFilledAmount;
        uint256 dealerTokenFilledAmount;
        uint256 remainingUserTokenAmount;
        uint256 tokenlonFee;
        uint256 dealerFee;
    }

    function _emitSignalBuyFilledByTrader(SignalBuyFilledByTraderParams memory _params) internal {
        emit SignalBuyFilledByTrader(
            _params.orderHash,
            _params.user,
            _params.dealer,
            _params.allowFillHash,
            _params.recipient,
            FillReceipt({
                userToken: _params.userToken,
                dealerToken: _params.dealerToken,
                userTokenFilledAmount: _params.userTokenFilledAmount,
                dealerTokenFilledAmount: _params.dealerTokenFilledAmount,
                remainingUserTokenAmount: _params.remainingUserTokenAmount,
                tokenlonFee: _params.tokenlonFee,
                dealerFee: _params.dealerFee
            })
        );
    }
}
