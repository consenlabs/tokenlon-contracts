// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "contracts/AMMWrapper.sol";
import "contracts/AMMQuoter.sol";
import "contracts/interfaces/IPermanentStorage.sol";
import "contracts/interfaces/ISpender.sol";
import "contracts/utils/AMMLibEIP712.sol";
import "contracts-test/utils/StrategySharedSetup.sol"; // Using the deployment Strategy Contract function
import { getEIP712Hash } from "contracts-test/utils/Sig.sol";

contract TestAMMWrapper is StrategySharedSetup {
    uint256 constant BPS_MAX = 10000;

    uint256 userPrivateKey = uint256(1);
    uint256 otherPrivateKey = uint256(2);

    address user = vm.addr(userPrivateKey);
    address feeCollector = address(0x133701);
    address relayer = address(0x133702);
    address[] wallet = [user, relayer];

    AMMWrapper ammWrapper;
    AMMQuoter ammQuoter;
    IERC20 weth = IERC20(WETH_ADDRESS);
    IERC20 usdt = IERC20(USDT_ADDRESS);
    IERC20 dai = IERC20(DAI_ADDRESS);
    IERC20 ankreth = IERC20(ANKRETH_ADDRESS);
    IERC20[] tokens = [weth, usdt, dai, ankreth];

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
    function setUp() public virtual {
        // Deploy and Setup Spender, AllowanceTarget, UserProxy, Tokenlon,
        // PermanentStorage, ProxyPermanentStorage, AMMWrapper contracts
        setUpSystemContracts();
        ammQuoter = new AMMQuoter(IPermanentStorage(permanentStorage), address(weth));
        address[] memory relayerListAddress = new address[](1);
        relayerListAddress[0] = relayer;
        bool[] memory relayerListBool = new bool[](1);
        relayerListBool[0] = true;
        permanentStorage.setRelayersValid(relayerListAddress, relayerListBool);

        // Deal 100 ETH to each account
        dealWallet(wallet, 100 ether);
        // Set token balance and approve
        setEOABalanceAndApprove(user, tokens, uint256(100));

        // Default order
        DEFAULT_ORDER = AMMLibEIP712.Order(
            UNISWAP_V2_ADDRESS, // makerAddr
            address(dai), // takerAssetAddr
            address(usdt), // makerAssetAddr
            uint256(100 * 1e18), // takerAssetAmount
            uint256(90 * 1e6), // makerAssetAmount
            user, // userAddr
            payable(user), // receiverAddr
            uint256(1234), // salt
            DEADLINE // deadline
        );

        // Label addresses for easier debugging
        vm.label(user, "User");
        vm.label(relayer, "Relayer");
        vm.label(address(this), "TestingContract");
        vm.label(address(ammWrapper), "AMMWrapperContract");
        vm.label(address(weth), "WETH");
        vm.label(address(usdt), "USDT");
        vm.label(address(dai), "DAI");
        vm.label(UNISWAP_V2_ADDRESS, "UniswapV2");
    }

    // Deploy the strategy contract by overriding the StrategySharedSetup.sol deployment function
    function _deployStrategyAndUpgrade() internal override returns (address) {
        ammWrapper = new AMMWrapper(
            address(this), // This contract would be the operator
            DEFAULT_FEE_FACTOR,
            address(userProxy),
            ISpender(address(spender)),
            permanentStorage,
            IWETH(address(weth)),
            UNISWAP_V2_ADDRESS,
            SUSHISWAP_ADDRESS,
            feeCollector
        );
        // Setup
        userProxy.upgradeAMMWrapper(address(ammWrapper), true);
        permanentStorage.upgradeAMMWrapper(address(ammWrapper));
        permanentStorage.setPermission(permanentStorage.transactionSeenStorageId(), address(ammWrapper), true);
        return address(ammWrapper);
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

    function _genTradePayload(
        AMMLibEIP712.Order memory order,
        uint256 feeFactor,
        bytes memory sig
    ) internal pure returns (bytes memory payload) {
        return
            abi.encodeWithSignature(
                "trade(address,address,address,uint256,uint256,uint256,address,address,uint256,uint256,bytes)",
                order.makerAddr,
                order.takerAssetAddr,
                order.makerAssetAddr,
                order.takerAssetAmount,
                order.makerAssetAmount,
                feeFactor,
                order.userAddr,
                order.receiverAddr,
                order.salt,
                order.deadline,
                sig
            );
    }
}
