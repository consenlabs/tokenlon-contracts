// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./interfaces/IPMM.sol";
import "./interfaces/ISpender.sol";
import "./interfaces/IPermanentStorage.sol";
import "./interfaces/IWeth.sol";
import "./interfaces/IERC1271Wallet.sol";
import "./interfaces/IZeroExchange.sol";
import "./utils/pmm/LibOrder.sol";
import "./utils/pmm/LibDecoder.sol";
import "./utils/pmm/LibEncoder.sol";

contract PMM is ReentrancyGuard, IPMM, LibOrder, LibDecoder, LibEncoder {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;

    // Constants do not have storage slot.
    string public constant version = "5.0.0";
    uint256 private constant MAX_UINT = 2**256 - 1;
    string public constant SOURCE = "0x v2";
    uint256 private constant BPS_MAX = 10000;
    bytes4 internal constant ERC1271_MAGICVALUE_BYTES32 = 0x1626ba7e; // bytes4(keccak256("isValidSignature(bytes32,bytes)"))
    address public immutable userProxy;
    ISpender public immutable spender;
    IPermanentStorage public immutable permStorage;
    IZeroExchange public immutable zeroExchange;
    address public immutable zxERC20Proxy;

    // Below are the variables which consume storage slots.
    address public operator;

    struct TradeInfo {
        address user;
        address receiver;
        uint16 feeFactor;
        address makerAssetAddr;
        address takerAssetAddr;
        bytes32 transactionHash;
        bytes32 orderHash;
    }

    // events
    event FillOrder(
        string source,
        bytes32 indexed transactionHash,
        bytes32 indexed orderHash,
        address indexed userAddr,
        address takerAssetAddr,
        uint256 takerAssetAmount,
        address makerAddr,
        address makerAssetAddr,
        uint256 makerAssetAmount,
        address receiverAddr,
        uint256 settleAmount,
        uint16 feeFactor
    );

    receive() external payable {}

    /************************************************************
     *          Access control and ownership management          *
     *************************************************************/
    modifier onlyOperator() {
        require(operator == msg.sender, "PMM: not operator");
        _;
    }

    modifier onlyUserProxy() {
        require(address(userProxy) == msg.sender, "PMM: not the UserProxy contract");
        _;
    }

    function transferOwnership(address _newOperator) external onlyOperator {
        require(_newOperator != address(0), "AMMWrapper: operator can not be zero address");
        operator = _newOperator;
    }

    /************************************************************
     *              Constructor and init functions               *
     *************************************************************/
    constructor(
        address _operator,
        address _userProxy,
        ISpender _spender,
        IPermanentStorage _permStorage,
        IZeroExchange _zeroExchange,
        address _zxERC20Proxy
    ) public {
        operator = _operator;
        userProxy = _userProxy;
        spender = _spender;
        permStorage = _permStorage;
        zeroExchange = _zeroExchange;
        zxERC20Proxy = _zxERC20Proxy;
        // This constant follows ZX_EXCHANGE address
        EIP712_DOMAIN_HASH = keccak256(
            abi.encodePacked(
                EIP712_DOMAIN_SEPARATOR_SCHEMA_HASH,
                keccak256(bytes(EIP712_DOMAIN_NAME)),
                keccak256(bytes(EIP712_DOMAIN_VERSION)),
                bytes12(0),
                address(_zeroExchange)
            )
        );
    }

    /************************************************************
     *           Management functions for Operator               *
     *************************************************************/
    /**
     * @dev approve spender to transfer tokens from this contract. This is used to collect fee.
     */
    function setAllowance(address[] calldata _tokenList, address _spender) external override onlyOperator {
        for (uint256 i = 0; i < _tokenList.length; i++) {
            IERC20(_tokenList[i]).safeApprove(_spender, MAX_UINT);
        }
    }

    function closeAllowance(address[] calldata _tokenList, address _spender) external override onlyOperator {
        for (uint256 i = 0; i < _tokenList.length; i++) {
            IERC20(_tokenList[i]).safeApprove(_spender, 0);
        }
    }

    /************************************************************
     *                   External functions                      *
     *************************************************************/
    function fill(
        uint256 userSalt,
        bytes memory data,
        bytes memory userSignature
    ) public payable override onlyUserProxy nonReentrant returns (uint256) {
        // decode & assert
        (LibOrder.Order memory order, TradeInfo memory tradeInfo) = _assertTransaction(userSalt, data, userSignature);

        // Deposit to WETH if taker asset is ETH, else transfer from user
        IWETH weth = IWETH(permStorage.wethAddr());
        if (address(weth) == tradeInfo.takerAssetAddr) {
            require(msg.value == order.takerAssetAmount, "PMM: insufficient ETH");
            weth.deposit{ value: msg.value }();
        } else {
            spender.spendFromUser(tradeInfo.user, tradeInfo.takerAssetAddr, order.takerAssetAmount);
        }

        IERC20(tradeInfo.takerAssetAddr).safeIncreaseAllowance(zxERC20Proxy, order.takerAssetAmount);

        // send tx to 0x
        zeroExchange.executeTransaction(userSalt, address(this), data, "");

        // settle token/ETH to user
        uint256 settleAmount = _settle(weth, tradeInfo.receiver, tradeInfo.makerAssetAddr, order.makerAssetAmount, tradeInfo.feeFactor);
        IERC20(tradeInfo.takerAssetAddr).safeApprove(zxERC20Proxy, 0);

        emit FillOrder(
            SOURCE,
            tradeInfo.transactionHash,
            tradeInfo.orderHash,
            tradeInfo.user,
            tradeInfo.takerAssetAddr,
            order.takerAssetAmount,
            order.makerAddress,
            tradeInfo.makerAssetAddr,
            order.makerAssetAmount,
            tradeInfo.receiver,
            settleAmount,
            tradeInfo.feeFactor
        );
        return settleAmount;
    }

    /**
     * @dev internal function of `fill`.
     * It decodes and validates transaction data.
     */
    function _assertTransaction(
        uint256 userSalt,
        bytes memory data,
        bytes memory userSignature
    ) internal view returns (LibOrder.Order memory order, TradeInfo memory tradeInfo) {
        // decode fillOrder data
        uint256 takerFillAmount;
        bytes memory mmSignature;
        (order, takerFillAmount, mmSignature) = decodeFillOrder(data);

        require(order.takerAddress == address(this), "PMM: incorrect taker");
        require(order.takerAssetAmount == takerFillAmount, "PMM: incorrect fill amount");

        // generate transactionHash
        tradeInfo.transactionHash = encodeTransactionHash(userSalt, address(this), data);

        tradeInfo.orderHash = getOrderHash(order);
        tradeInfo.feeFactor = uint16(order.salt);
        tradeInfo.receiver = decodeUserSignatureWithoutSign(userSignature);
        tradeInfo.user = _ecrecoverAddress(tradeInfo.transactionHash, userSignature);

        if (tradeInfo.user != order.feeRecipientAddress) {
            require(order.feeRecipientAddress.isContract(), "PMM: invalid contract address");
            // isValidSignature() should return magic value: bytes4(keccak256("isValidSignature(bytes32,bytes)"))
            require(
                ERC1271_MAGICVALUE_BYTES32 == IERC1271Wallet(order.feeRecipientAddress).isValidSignature(tradeInfo.transactionHash, userSignature),
                "PMM: invalid ERC1271 signer"
            );
            tradeInfo.user = order.feeRecipientAddress;
        }

        require(tradeInfo.feeFactor < 10000, "PMM: invalid fee factor");

        require(tradeInfo.receiver != address(0), "PMM: invalid receiver");

        // decode asset
        // just support ERC20
        tradeInfo.makerAssetAddr = decodeERC20Asset(order.makerAssetData);
        tradeInfo.takerAssetAddr = decodeERC20Asset(order.takerAssetData);
        return (order, tradeInfo);
    }

    // settle
    function _settle(
        IWETH weth,
        address receiver,
        address makerAssetAddr,
        uint256 makerAssetAmount,
        uint16 feeFactor
    ) internal returns (uint256) {
        uint256 settleAmount = makerAssetAmount;
        if (feeFactor > 0) {
            // settleAmount = settleAmount * (10000 - feeFactor) / 10000
            settleAmount = settleAmount.mul((BPS_MAX).sub(feeFactor)).div(BPS_MAX);
        }

        if (makerAssetAddr == address(weth)) {
            weth.withdraw(settleAmount);
            payable(receiver).transfer(settleAmount);
        } else {
            IERC20(makerAssetAddr).safeTransfer(receiver, settleAmount);
        }

        return settleAmount;
    }

    function _ecrecoverAddress(bytes32 transactionHash, bytes memory signature) internal pure returns (address) {
        (uint8 v, bytes32 r, bytes32 s, address receiver) = decodeUserSignature(signature);
        return ecrecover(keccak256(abi.encodePacked(transactionHash, receiver)), v, r, s);
    }
}
