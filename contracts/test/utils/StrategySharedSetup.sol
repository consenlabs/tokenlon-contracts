// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "contracts/Spender.sol";
import "contracts/AllowanceTarget.sol";
import "contracts/interfaces/ISetAllowance.sol";
import "contracts/stub/UserProxyStub.sol";
import "contracts/stub/PermanentStorageStub.sol";
import "./Addresses.sol";
import "./BalanceUtil.sol";

contract StrategySharedSetup is BalanceUtil {
    using SafeERC20 for IERC20;

    AllowanceTarget allowanceTarget;
    Spender spender;
    UserProxyStub userProxyStub;
    PermanentStorageStub permanentStorageStub;

    function _deployStrategyAndUpgrade() internal virtual returns (address) {}

    function setUpSystemContracts() internal {
        // Deploy
        spender = new Spender(address(this));
        allowanceTarget = new AllowanceTarget(address(spender));
        userProxyStub = new UserProxyStub(Addresses.WETH_ADDRESS);
        permanentStorageStub = new PermanentStorageStub();
        address strategy = _deployStrategyAndUpgrade();
        // Setup
        spender.setAllowanceTarget(address(allowanceTarget));
        address[] memory authListAddress = new address[](1);
        authListAddress[0] = strategy;
        spender.authorize(authListAddress);

        vm.label(address(spender), "SpenderContract");
        vm.label(address(allowanceTarget), "AllowanceTargetContract");
        vm.label(address(userProxyStub), "UserProxyStubContract");
        vm.label(address(permanentStorageStub), "PermanentStorageStubContract");
    }

    function dealWallet(address[] memory wallet, uint256 amount) internal {
        // Deal 100 ETH to each account
        for (uint256 i = 0; i < wallet.length; i++) {
            vm.deal(wallet[i], amount);
        }
    }

    function setEOABalanceAndApprove(
        address eoa,
        IERC20[] memory tokens,
        uint256 amount
    ) internal {
        require(address(allowanceTarget) != address(0), "System contracts not setup yet");
        vm.startPrank(eoa);
        for (uint256 j = 0; j < tokens.length; j++) {
            setERC20Balance(address(tokens[j]), eoa, amount);
            tokens[j].safeApprove(address(allowanceTarget), type(uint256).max);
        }
        vm.stopPrank();
    }

    function setWalletContractBalanceAndApprove(
        address owner,
        address walletContract,
        IERC20[] memory tokens,
        uint256 amount
    ) internal {
        require(address(allowanceTarget) != address(0), "System contracts not setup yet");
        address[] memory tokenAddresses = new address[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            // Convert from type IERC20[] to address[] since wallet contract's `setAllowance` only accepts address[] type
            tokenAddresses[i] = address(tokens[i]);
            setERC20Balance(tokenAddresses[i], walletContract, amount);
        }
        vm.prank(owner);
        ISetAllowance(walletContract).setAllowance(tokenAddresses, address(allowanceTarget));
    }
}
