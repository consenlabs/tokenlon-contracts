// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "contracts/AMMWrapper.sol";
import "contracts/AMMQuoter.sol";
import "contracts/interfaces/IPermanentStorage.sol";
import "contracts/interfaces/ISpender.sol";
import "contracts/utils/AMMLibEIP712.sol";
import "contracts-test/utils/StrategySharedSetup.sol"; // Using the deployment Strategy Contract function
import "contracts-test/utils/Permit.sol";
import { getEIP712Hash } from "contracts-test/utils/Sig.sol";

contract TestAMMWrapper is StrategySharedSetup, Permit {
    bytes32 public constant relayerValidStorageId = 0x2c97779b4deaf24e9d46e02ec2699240a957d92782b51165b93878b09dd66f61; // keccak256("relayerValid")

    uint256 userPrivateKey = uint256(1);
    uint256 otherPrivateKey = uint256(2);

    address user = vm.addr(userPrivateKey);
    address owner = makeAddr("owner");
    address feeCollector = makeAddr("feeCollector");
    address relayer = makeAddr("relayer");
    address[] wallet = [user, relayer];

    AMMWrapper ammWrapper;
    AMMQuoter ammQuoter;

    uint16 DEFAULT_FEE_FACTOR = 500;
    uint256 DEADLINE = block.timestamp + 1;
    AMMLibEIP712.Order DEFAULT_ORDER;

    event Swapped(
        string source,
        bytes32 indexed transactionHash,
        address indexed userAddr,
        bool relayed,
        address takerAssetAddr,
        uint256 takerAssetAmount,
        address makerAddr,
        address makerAssetAddr,
        uint256 makerAssetAmount,
        address receiverAddr,
        uint256 settleAmount,
        uint16 feeFactor
    );
    event SetFeeCollector(address newFeeCollector);

    // effectively a "beforeEach" block
    function setUp() public {
        setUpSystemContracts();

        address[] memory relayerListAddress = new address[](1);
        relayerListAddress[0] = relayer;
        bool[] memory relayerListBool = new bool[](1);
        relayerListBool[0] = true;
        vm.prank(psOperator, psOperator);
        permanentStorage.setRelayersValid(relayerListAddress, relayerListBool);

        // Deal 100 ETH to each account
        dealWallet(wallet, 100 ether);
        // Set token balance and approve
        setEOABalanceAndApprove(user, tokens, uint256(100));

        // Default order
        DEFAULT_ORDER = AMMLibEIP712.Order({
            makerAddr: UNISWAP_V2_ADDRESS,
            takerAssetAddr: address(dai),
            makerAssetAddr: address(usdt),
            takerAssetAmount: uint256(100 * 1e18),
            makerAssetAmount: uint256(90 * 1e6),
            userAddr: user,
            receiverAddr: payable(user),
            salt: uint256(1234),
            deadline: DEADLINE
        });

        // Label addresses for easier debugging
        vm.label(user, "User");
        vm.label(relayer, "Relayer");
        vm.label(address(this), "TestingContract");
        vm.label(address(ammWrapper), "AMMWrapperContract");
        vm.label(UNISWAP_V2_ADDRESS, "UniswapV2");
    }

    // Deploy the strategy contract by overriding the StrategySharedSetup.sol deployment function
    function _deployStrategyAndUpgrade() internal override returns (address) {
        ammQuoter = new AMMQuoter(
            UNISWAP_V2_ADDRESS,
            UNISWAP_V3_ADDRESS,
            UNISWAP_V3_QUOTER_ADDRESS,
            SUSHISWAP_ADDRESS,
            BALANCER_V2_ADDRESS,
            IPermanentStorage(permanentStorage),
            address(weth)
        );

        ammWrapper = new AMMWrapper(
            owner,
            address(userProxy),
            address(weth),
            address(permanentStorage),
            address(spender),
            DEFAULT_FEE_FACTOR,
            UNISWAP_V2_ADDRESS,
            SUSHISWAP_ADDRESS,
            feeCollector
        );
        // Setup
        userProxy.upgradeAMMWrapper(address(ammWrapper), true);
        vm.startPrank(psOperator, psOperator);
        permanentStorage.upgradeAMMWrapper(address(ammWrapper));
        permanentStorage.setPermission(permanentStorage.transactionSeenStorageId(), address(ammWrapper), true);
        vm.stopPrank();

        return address(ammWrapper);
    }

    function _setupDeployedStrategy() internal override {
        ammQuoter = AMMQuoter(vm.envAddress("AMMQUOTER_ADDRESS"));
        ammWrapper = AMMWrapper(payable(vm.envAddress("AMMWRAPPER_ADDRESS")));
        owner = ammWrapper.owner();
        feeCollector = ammWrapper.feeCollector();
        psOperator = permanentStorage.operator();
    }

    /*********************************
     *          Test Helpers         *
     *********************************/

    function _signTrade(uint256 privateKey, AMMLibEIP712.Order memory order) internal returns (bytes memory sig) {
        bytes32 orderHash = AMMLibEIP712._getOrderHash(order);
        bytes32 EIP712SignDigest = getEIP712Hash(ammWrapper.EIP712_DOMAIN_SEPARATOR(), orderHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        sig = abi.encodePacked(r, s, v, bytes32(0), uint8(2));
    }

    function _createSpenderPermitFromOrder(AMMLibEIP712.Order memory order) internal view returns (SpenderLibEIP712.SpendWithPermit memory takerAssetPermit) {
        takerAssetPermit = SpenderLibEIP712.SpendWithPermit({
            tokenAddr: order.takerAssetAddr,
            requester: address(ammWrapper),
            user: order.userAddr,
            recipient: address(ammWrapper),
            amount: order.takerAssetAmount,
            actionHash: AMMLibEIP712._getOrderHash(order),
            expiry: uint64(order.deadline)
        });
        return takerAssetPermit;
    }

    function _genTradePayload(
        AMMLibEIP712.Order memory order,
        uint256 feeFactor,
        bytes memory sig,
        bytes memory takerAssetPermitSig
    ) internal pure returns (bytes memory payload) {
        return abi.encodeWithSelector(AMMWrapper.trade.selector, order, feeFactor, sig, takerAssetPermitSig);
    }
}
