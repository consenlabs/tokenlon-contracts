// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Tokens } from "test/utils/Tokens.sol";
import { BalanceUtil } from "test/utils/BalanceUtil.sol";
import { getEIP712Hash } from "test/utils/Sig.sol";
import { computeContractAddress } from "test/utils/Addresses.sol";
import { MockLimitOrderTaker } from "test/mocks/MockLimitOrderTaker.sol";
import { LimitOrderSwap } from "contracts/LimitOrderSwap.sol";
import { AllowanceTarget } from "contracts/AllowanceTarget.sol";
import { IWETH } from "contracts/interfaces/IWETH.sol";
import { TokenCollector } from "contracts/abstracts/TokenCollector.sol";
import { LimitOrder, getLimitOrderHash } from "contracts/libraries/LimitOrder.sol";

contract LimitOrderSwapTest is Test, Tokens, BalanceUtil {
    event SetFeeCollector(address newFeeCollector);
    event LimitOrderFilled(
        bytes32 indexed offerHash,
        address indexed taker,
        address indexed maker,
        address takerToken,
        uint256 takerTokenFilledAmount,
        address makerToken,
        uint256 makerTokenSettleAmount,
        uint256 fee,
        address recipient
    );

    address limitOrderOwner = makeAddr("limitOrderOwner");
    uint256 makerPrivateKey = uint256(1);
    address payable maker = payable(vm.addr(makerPrivateKey));
    address taker = makeAddr("taker");
    address payable recipient = payable(makeAddr("recipient"));
    address payable feeCollector = payable(makeAddr("feeCollector"));
    address walletOwner = makeAddr("walletOwner");
    uint256 defaultExpiry = block.timestamp + 1;
    uint256 defaultSalt = 1234;
    uint256 defaultFeeFactor = 100;
    LimitOrder defaultOrder;
    bytes defaultMakerSig;
    bytes defaultPermit;
    MockLimitOrderTaker mockLimitOrderTaker;
    LimitOrderSwap limitOrderSwap;
    AllowanceTarget allowanceTarget;

    function setUp() public virtual {
        // deploy allowance target
        address[] memory trusted = new address[](1);
        // pre-compute LimitOrderSwap address since the whitelist of allowance target is immutable
        // NOTE: this assumes LimitOrderSwap is deployed right next to Allowance Target
        trusted[0] = computeContractAddress(address(this), uint8(vm.getNonce(address(this)) + 1));
        allowanceTarget = new AllowanceTarget(trusted);

        limitOrderSwap = new LimitOrderSwap(limitOrderOwner, UNISWAP_PERMIT2_ADDRESS, address(allowanceTarget), IWETH(WETH_ADDRESS), feeCollector);
        mockLimitOrderTaker = new MockLimitOrderTaker(walletOwner, UNISWAP_V2_ADDRESS);

        deal(maker, 100 ether);
        setTokenBalanceAndApprove(maker, address(limitOrderSwap), tokens, 100000);
        deal(taker, 100 ether);
        setTokenBalanceAndApprove(taker, address(limitOrderSwap), tokens, 100000);
        deal(address(mockLimitOrderTaker), 100 ether);
        setTokenBalanceAndApprove(address(mockLimitOrderTaker), address(limitOrderSwap), tokens, 100000);
        defaultPermit = abi.encode(TokenCollector.Source.Token, bytes(""));

        address[] memory tokenList = new address[](2);
        tokenList[0] = DAI_ADDRESS;
        tokenList[1] = USDT_ADDRESS;
        vm.startPrank(walletOwner);
        mockLimitOrderTaker.setAllowance(tokenList, UNISWAP_V2_ADDRESS);
        vm.stopPrank();

        defaultOrder = LimitOrder({
            taker: address(0),
            maker: maker,
            takerToken: USDT_ADDRESS,
            takerTokenAmount: 10 * 1e6,
            makerToken: DAI_ADDRESS,
            makerTokenAmount: 10 ether,
            makerTokenPermit: defaultPermit,
            feeFactor: defaultFeeFactor,
            expiry: defaultExpiry,
            salt: defaultSalt
        });

        defaultMakerSig = _signLimitOrder(makerPrivateKey, defaultOrder);

        vm.label(address(limitOrderSwap), "limitOrderSwap");
        vm.label(taker, "taker");
        vm.label(maker, "maker");
    }

    function _signLimitOrder(uint256 _privateKey, LimitOrder memory _order) internal view returns (bytes memory sig) {
        bytes32 orderHash = getLimitOrderHash(_order);
        bytes32 EIP712SignDigest = getEIP712Hash(limitOrderSwap.EIP712_DOMAIN_SEPARATOR(), orderHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }
}
