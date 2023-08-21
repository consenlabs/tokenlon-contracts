// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Tokens } from "test/utils/Tokens.sol";
import { BalanceUtil } from "test/utils/BalanceUtil.sol";
import { SigHelper } from "test/utils/SigHelper.sol";
import { computeContractAddress } from "test/utils/Addresses.sol";
import { Permit2Helper } from "test/utils/Permit2Helper.sol";
import { MockLimitOrderTaker } from "test/mocks/MockLimitOrderTaker.sol";
import { LimitOrderSwap } from "contracts/LimitOrderSwap.sol";
import { AllowanceTarget } from "contracts/AllowanceTarget.sol";
import { IWETH } from "contracts/interfaces/IWETH.sol";
import { ILimitOrderSwap } from "contracts/interfaces/ILimitOrderSwap.sol";
import { IUniswapPermit2 } from "contracts/interfaces/IUniswapPermit2.sol";
import { TokenCollector } from "contracts/abstracts/TokenCollector.sol";
import { LimitOrder, getLimitOrderHash } from "contracts/libraries/LimitOrder.sol";

contract LimitOrderSwapTest is Test, Tokens, BalanceUtil, Permit2Helper, SigHelper {
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
    address allowanceTargetOwner = makeAddr("allowanceTargetOwner");
    uint256 makerPrivateKey = uint256(1);
    address payable maker = payable(vm.addr(makerPrivateKey));
    uint256 takerPrivateKey = uint256(2);
    address taker = vm.addr(takerPrivateKey);
    address payable recipient = payable(makeAddr("recipient"));
    address payable feeCollector = payable(makeAddr("feeCollector"));
    address walletOwner = makeAddr("walletOwner");
    uint256 defaultExpiry = block.timestamp + 1;
    uint256 defaultSalt = 1234;
    uint256 defaultFeeFactor = 100;
    LimitOrder defaultOrder;
    bytes defaultMakerSig;
    bytes directApprovePermit = abi.encodePacked(TokenCollector.Source.Token);
    bytes allowanceTransferPermit = abi.encodePacked(TokenCollector.Source.Permit2AllowanceTransfer);
    bytes defaultMakerPermit = allowanceTransferPermit;
    bytes defaultTakerPermit;
    ILimitOrderSwap.TakerParams defaultTakerParams;
    MockLimitOrderTaker mockLimitOrderTaker;
    LimitOrderSwap limitOrderSwap;
    AllowanceTarget allowanceTarget;

    function setUp() public virtual {
        // deploy allowance target
        address[] memory trusted = new address[](1);
        // pre-compute LimitOrderSwap address since the whitelist of allowance target is immutable
        // NOTE: this assumes LimitOrderSwap is deployed right next to Allowance Target
        trusted[0] = computeContractAddress(address(this), uint8(vm.getNonce(address(this)) + 1));
        allowanceTarget = new AllowanceTarget(allowanceTargetOwner, trusted);

        limitOrderSwap = new LimitOrderSwap(limitOrderOwner, UNISWAP_PERMIT2_ADDRESS, address(allowanceTarget), IWETH(WETH_ADDRESS), feeCollector);
        mockLimitOrderTaker = new MockLimitOrderTaker(walletOwner, UNISWAP_V2_ADDRESS);

        deal(maker, 100 ether);
        setTokenBalanceAndApprove(maker, UNISWAP_PERMIT2_ADDRESS, tokens, 100000);
        deal(taker, 100 ether);
        setTokenBalanceAndApprove(taker, UNISWAP_PERMIT2_ADDRESS, tokens, 100000);
        deal(address(mockLimitOrderTaker), 100 ether);
        // mockLimitOrderTaker approve LO contract directly for convenience
        setTokenBalanceAndApprove(address(mockLimitOrderTaker), address(limitOrderSwap), tokens, 100000);

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
            makerTokenPermit: defaultMakerPermit,
            feeFactor: defaultFeeFactor,
            expiry: defaultExpiry,
            salt: defaultSalt
        });

        // maker should call permit2 first independently
        vm.prank(maker);
        IUniswapPermit2(UNISWAP_PERMIT2_ADDRESS).approve(defaultOrder.makerToken, address(limitOrderSwap), type(uint160).max, uint48(block.timestamp + 1 days));

        defaultTakerPermit = getTokenlonPermit2Data(taker, takerPrivateKey, defaultOrder.takerToken, address(limitOrderSwap));

        defaultTakerParams = ILimitOrderSwap.TakerParams({
            takerTokenAmount: defaultOrder.takerTokenAmount,
            makerTokenAmount: defaultOrder.makerTokenAmount,
            recipient: recipient,
            extraAction: bytes(""),
            takerTokenPermit: defaultTakerPermit
        });

        defaultMakerSig = signLimitOrder(makerPrivateKey, defaultOrder, address(limitOrderSwap));

        vm.label(address(limitOrderSwap), "limitOrderSwap");
        vm.label(taker, "taker");
        vm.label(maker, "maker");
    }
}
