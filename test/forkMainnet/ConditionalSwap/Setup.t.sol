// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { IWETH } from "contracts/interfaces/IWETH.sol";
import { IConditionalSwap } from "contracts/interfaces/IConditionalSwap.sol";
import { ConditionalSwap } from "contracts/ConditionalSwap.sol";
import { AllowanceTarget } from "contracts/AllowanceTarget.sol";
import { ConOrder, getConOrderHash } from "contracts/libraries/ConditionalOrder.sol";
import { Tokens } from "test/utils/Tokens.sol";
import { BalanceUtil } from "test/utils/BalanceUtil.sol";
import { SigHelper } from "test/utils/SigHelper.sol";
import { computeContractAddress } from "test/utils/Addresses.sol";
import { Permit2Helper } from "test/utils/Permit2Helper.sol";

contract ConditionalOrderSwapTest is Test, Tokens, BalanceUtil, Permit2Helper, SigHelper {
    // role
    address public conditionalOrderOwner = makeAddr("conditionalOrderOwner");
    address public allowanceTargetOwner = makeAddr("allowanceTargetOwner");
    uint256 public takerPrivateKey = uint256(1);
    uint256 public makerPrivateKey = uint256(2);
    address public taker = vm.addr(takerPrivateKey);
    address payable public maker = payable(vm.addr(makerPrivateKey));
    address payable public recipient = payable(makeAddr("recipient"));

    uint256 public defaultExpiry = block.timestamp + 1 days;
    uint256 public defaultSalt = 1234;
    bytes public defaultTakerPermit;
    bytes public defaultTakerSig;
    bytes public defaultSettlementData;

    ConditionalSwap conditionalSwap;
    AllowanceTarget allowanceTarget;
    ConOrder defaultOrder;

    function setUp() public virtual {
        // deploy allowance target
        address[] memory trusted = new address[](1);
        // pre-compute ConditionalOrderSwap address since the whitelist of allowance target is immutable
        // NOTE: this assumes LimitOrderSwap is deployed right next to Allowance Target
        trusted[0] = computeContractAddress(address(this), uint8(vm.getNonce(address(this)) + 1));

        allowanceTarget = new AllowanceTarget(allowanceTargetOwner, trusted);
        conditionalSwap = new ConditionalSwap(conditionalOrderOwner, UNISWAP_PERMIT2_ADDRESS, address(allowanceTarget));

        deal(maker, 100 ether);
        deal(taker, 100 ether);
        setTokenBalanceAndApprove(maker, address(conditionalSwap), tokens, 100000);
        setTokenBalanceAndApprove(taker, address(conditionalSwap), tokens, 100000);

        defaultTakerPermit = hex"01";
        defaultSettlementData = hex"00";

        defaultOrder = ConOrder({
            taker: taker,
            maker: maker,
            recipient: recipient,
            takerToken: USDT_ADDRESS,
            takerTokenAmount: 10 * 1e6,
            makerToken: DAI_ADDRESS,
            makerTokenAmount: 10 ether,
            takerTokenPermit: defaultTakerPermit,
            flagsAndPeriod: 0,
            expiry: defaultExpiry,
            salt: defaultSalt
        });
    }
}
