// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { ConditionalSwap } from "contracts/ConditionalSwap.sol";
import { AllowanceTarget } from "contracts/AllowanceTarget.sol";
import { ConOrder } from "contracts/libraries/ConditionalOrder.sol";
import { Tokens } from "test/utils/Tokens.sol";
import { BalanceUtil } from "test/utils/BalanceUtil.sol";
import { SigHelper } from "test/utils/SigHelper.sol";
import { computeContractAddress } from "test/utils/Addresses.sol";
import { Permit2Helper } from "test/utils/Permit2Helper.sol";

contract ConditionalOrderSwapTest is Test, Tokens, BalanceUtil, Permit2Helper, SigHelper {
    event ConditionalOrderFilled(
        bytes32 indexed orderHash,
        address indexed taker,
        address indexed maker,
        address takerToken,
        uint256 takerTokenFilledAmount,
        address makerToken,
        uint256 makerTokenSettleAmount,
        address recipient
    );

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

    // mask for triggering different business logic (e.g. BestBuy, Repayment, DCA)
    uint256 public constant FLG_SINGLE_AMOUNT_CAP_MASK = 1 << 255; // ConOrder.amount is the cap of single execution, not total cap
    uint256 public constant FLG_PERIODIC_MASK = 1 << 254; // ConOrder can be executed periodically
    uint256 public constant FLG_PARTIAL_FILL_MASK = 1 << 253; // ConOrder can be fill partially

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
