// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;
pragma abicoder v2;

import "contracts/AMMWrapperWithPath.sol";
import "contracts/AMMQuoter.sol";
import "contracts/interfaces/IPermanentStorage.sol";
import "contracts/interfaces/ISpender.sol";
import "contracts/interfaces/IBalancerV2Vault.sol";
import "contracts/utils/AMMLibEIP712.sol";
import "contracts-test/utils/AMMUtil.sol";
import "contracts-test/utils/BalanceSnapshot.sol";
import "contracts-test/utils/StrategySharedSetup.sol";
import "contracts-test/utils/UniswapV3Util.sol";

contract AMMWrapperWithPathTest is StrategySharedSetup {
    using SafeERC20 for IERC20;
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    bytes32 public constant relayerValidStorageId = 0x2c97779b4deaf24e9d46e02ec2699240a957d92782b51165b93878b09dd66f61; // keccak256("relayerValid")
    uint256 constant BPS_MAX = 10000;
    event Swapped(AMMWrapperWithPath.TxMetaData, AMMLibEIP712.Order order);

    uint256 userPrivateKey = uint256(1);
    uint256 otherPrivateKey = uint256(2);

    address user = vm.addr(userPrivateKey);
    address relayer = address(0x133702);
    address psOperator;
    address[] wallet = [user, relayer];

    AMMWrapperWithPath ammWrapperWithPath;
    AMMQuoter ammQuoter;
    IERC20 weth;
    IERC20 usdt;
    IERC20 lon;
    IERC20[] tokens;

    uint256 SUBSIDY_FACTOR = 3;
    uint256 DEADLINE = block.timestamp + 1;
    AMMLibEIP712.Order DEFAULT_ORDER;
    // UniswapV3
    uint256 SINGLE_POOL_SWAP_TYPE = 1;
    uint256 MULTI_POOL_SWAP_TYPE = 2;
    address[] DEFAULT_MULTI_HOP_PATH;
    uint24[] DEFAULT_MULTI_HOP_POOL_FEES;
    // BalancerV2
    bytes32 constant BALANCER_DAI_USDT_USDC_POOL = 0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000063;
    bytes32 constant BALANCER_WETH_DAI_POOL = 0x0b09dea16768f0799065c475be02919503cb2a3500020000000000000000001a;
    bytes32 constant BALANCER_WETH_USDC_POOL = 0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019;

    // effectively a "beforeEach" block
    function setUp() public {
        weth = IERC20(vm.envAddress("WETH_ADDRESS"));
        usdt = IERC20(vm.envAddress("USDT_ADDRESS"));
        lon = IERC20(vm.envAddress("LON_ADDRESS"));
        tokens = [usdt, lon];
        if (vm.envBool("mainnet")) {
            allowanceTarget = AllowanceTarget(vm.envAddress("AllowanceTarget_ADDRESS"));
            spender = Spender(vm.envAddress("Spender_ADDRESS"));
            userProxy = UserProxy(payable(vm.envAddress("UserProxy_ADDRESS")));
            permanentStorage = PermanentStorage(vm.envAddress("PermanentStorage_ADDRESS"));

            ammWrapperWithPath = AMMWrapperWithPath(payable(vm.envAddress("AMMWRAPPER_ADDRESS")));

            psOperator = permanentStorage.operator();
        } else {
            setUpSystemContracts();
            psOperator = address(this);
        }

        ammQuoter = new AMMQuoter(IPermanentStorage(permanentStorage), address(weth));
        address[] memory relayerListAddress = new address[](1);
        relayerListAddress[0] = relayer;
        bool[] memory relayerListBool = new bool[](1);
        relayerListBool[0] = true;
        vm.prank(psOperator, psOperator);
        permanentStorage.setPermission(relayerValidStorageId, psOperator, true);
        vm.prank(psOperator, psOperator);
        permanentStorage.setRelayersValid(relayerListAddress, relayerListBool);

        // Deal 100 ETH to each account
        dealWallet(wallet, 100 ether);
        // Set token balance and approve
        setEOABalanceAndApprove(user, tokens, 100);

        // Default order
        DEFAULT_ORDER = AMMLibEIP712.Order(
            UNISWAP_V2_ADDRESS, // makerAddr
            address(usdt), // takerAssetAddr
            address(lon), // makerAssetAddr
            10 * 1e6, // takerAssetAmount
            1, // makerAssetAmount
            user, // userAddr
            payable(user), // receiverAddr
            uint256(1234), // salt
            DEADLINE // deadline
        );
        DEFAULT_MULTI_HOP_PATH = new address[](3);
        DEFAULT_MULTI_HOP_PATH[0] = DEFAULT_ORDER.takerAssetAddr;
        DEFAULT_MULTI_HOP_PATH[1] = address(weth);
        DEFAULT_MULTI_HOP_PATH[2] = DEFAULT_ORDER.makerAssetAddr;
        DEFAULT_MULTI_HOP_POOL_FEES = new uint24[](2);
        DEFAULT_MULTI_HOP_POOL_FEES[0] = FEE_MEDIUM;
        DEFAULT_MULTI_HOP_POOL_FEES[1] = FEE_MEDIUM;

        // Label addresses for easier debugging
        vm.label(user, "User");
        vm.label(relayer, "Relayer");
        vm.label(address(this), "TestingContract");
        vm.label(address(ammWrapperWithPath), "AMMWrapperWithPathContract");
        vm.label(address(usdt), "USDT");
        vm.label(address(lon), "LON");
        vm.label(UNISWAP_V2_ADDRESS, "UniswapV2");
        vm.label(SUSHISWAP_ADDRESS, "Sushiswap");
        vm.label(UNISWAP_V3_ADDRESS, "UniswapV3");
        vm.label(CURVE_USDT_POOL_ADDRESS, "CurveUSDTPool");
        vm.label(CURVE_TRICRYPTO2_POOL_ADDRESS, "CurveTriCryptoPool");
    }

    function _deployStrategyAndUpgrade() internal override returns (address) {
        ammWrapperWithPath = new AMMWrapperWithPath(
            address(this), // This contract would be the operator
            SUBSIDY_FACTOR,
            address(userProxy),
            ISpender(address(spender)),
            permanentStorage,
            IWETH(address(weth))
        );
        // Setup
        userProxy.upgradeAMMWrapper(address(ammWrapperWithPath), true);
        permanentStorage.upgradeAMMWrapper(address(ammWrapperWithPath));
        permanentStorage.setPermission(permanentStorage.transactionSeenStorageId(), address(ammWrapperWithPath), true);
        return address(ammWrapperWithPath);
    }

    function testEmitSwappedEvent() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = DEFAULT_MULTI_HOP_PATH;
        uint24[] memory fees = DEFAULT_MULTI_HOP_POOL_FEES;
        bytes memory makerSpecificData = _encodeUniswapMultiPoolData(MULTI_POOL_SWAP_TYPE, path, fees);
        bytes memory payload = _genTradePayload(order, feeFactor, sig, makerSpecificData, path);

        userProxy.toAMM(payload);
    }

    /*********************************
     *             Helpers           *
     *********************************/

    function _getEIP712Hash(bytes32 structHash) internal view returns (bytes32) {
        string memory EIP191_HEADER = "\x19\x01";
        bytes32 EIP712_DOMAIN_SEPARATOR = ammWrapperWithPath.EIP712_DOMAIN_SEPARATOR();
        return keccak256(abi.encodePacked(EIP191_HEADER, EIP712_DOMAIN_SEPARATOR, structHash));
    }

    function _signTrade(uint256 privateKey, AMMLibEIP712.Order memory order) internal returns (bytes memory sig) {
        bytes32 orderHash = AMMLibEIP712._getOrderHash(order);
        bytes32 EIP712SignDigest = _getEIP712Hash(orderHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        sig = abi.encodePacked(r, s, v, bytes32(0), uint8(2));
    }

    function _genTradePayload(
        AMMLibEIP712.Order memory order,
        uint256 feeFactor,
        bytes memory sig,
        bytes memory makerSpecificData,
        address[] memory path
    ) internal view returns (bytes memory payload) {
        return
            abi.encodeWithSignature(
                "trade((address,address,address,uint256,uint256,address,address,uint256,uint256),uint256,bytes,bytes,address[])",
                order,
                feeFactor,
                sig,
                makerSpecificData,
                path
            );
    }
}
