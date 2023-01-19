// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "contracts/MarketMakerProxy.sol";
import "test/utils/BalanceSnapshot.sol";
import "test/utils/StrategySharedSetup.sol";
import "test/mocks/MockERC1271Wallet.sol";

contract MarketMakerProxyTest is StrategySharedSetup {
    using SafeMath for uint256;
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    bytes4 constant EIP1271_MAGICVALUE = 0x1626ba7e;

    event ChangeSigner(address);
    event UpdateWhitelist(address, bool);
    event WrapETH(uint256);
    event WithdrawETH(uint256);

    uint256 signerPrivateKey = uint256(1);
    address signer = vm.addr(signerPrivateKey);
    address owner = makeAddr("owner");
    address payable withdrawer = payable(makeAddr("withdrawer"));
    address[] walletTokens;
    MarketMakerProxy marketMakerProxy;

    // effectively a "beforeEach" block
    function setUp() public {
        marketMakerProxy = new MarketMakerProxy(owner, signer, IWETH(address(weth)));
        vm.prank(owner, owner);
        marketMakerProxy.updateWithdrawWhitelist(withdrawer, true);

        // init tokens
        walletTokens = [address(weth), address(usdt), address(usdc)];
        for (uint256 i = 0; i < walletTokens.length; ++i) {
            setERC20Balance(walletTokens[i], address(marketMakerProxy), 100000);
        }
        deal(address(marketMakerProxy), 100 ether);

        // Label addresses for easier debugging
        vm.label(signer, "signer");
        vm.label(owner, "owner");
        vm.label(withdrawer, "withdrawer");
        vm.label(address(marketMakerProxy), "MarketMakerProxy");
    }

    function testReceiveETH() public {
        address sender = makeAddr("sender");
        deal(sender, 100 ether);
        uint256 sendAmount = 15 ether;

        BalanceSnapshot.Snapshot memory walletETHBalance = BalanceSnapshot.take({ owner: address(marketMakerProxy), token: ETH_ADDRESS });
        BalanceSnapshot.Snapshot memory senderETHBalance = BalanceSnapshot.take({ owner: sender, token: ETH_ADDRESS });

        vm.prank(sender, sender);
        payable(address(marketMakerProxy)).send(sendAmount);

        walletETHBalance.assertChange(int256(sendAmount));
        senderETHBalance.assertChange(-int256(sendAmount));
    }

    function testCannotSetSignerByNotOwner() public {
        vm.expectRevert("not owner");
        marketMakerProxy.setSigner(makeAddr("new_signer"));
    }

    function testCannotSetSignerToZeroAddress() public {
        vm.expectRevert("MarketMakerProxy: zero address");
        vm.prank(owner, owner);
        marketMakerProxy.setSigner(address(0));
    }

    function testSetSigner() public {
        address newSigner = makeAddr("new_signer");
        vm.expectEmit(true, true, true, true);
        emit ChangeSigner(newSigner);
        vm.prank(owner, owner);
        marketMakerProxy.setSigner(newSigner);
    }

    function testCannotSetAllowanceByNotOwner() public {
        vm.expectRevert("not owner");
        marketMakerProxy.setAllowance(walletTokens, makeAddr("spender"));
    }

    function testSetAllowance() public {
        vm.prank(owner, owner);
        marketMakerProxy.setAllowance(walletTokens, makeAddr("spender"));
    }

    function testCannotCloseAllowanceByNotOwner() public {
        vm.expectRevert("not owner");
        marketMakerProxy.closeAllowance(walletTokens, makeAddr("spender"));
    }

    function testCloseAllowance() public {
        vm.prank(owner, owner);
        marketMakerProxy.closeAllowance(walletTokens, makeAddr("spender"));
    }

    function testCannotUpdateWithdrawWhitelistByNotOwner() public {
        vm.expectRevert("not owner");
        marketMakerProxy.updateWithdrawWhitelist(withdrawer, true);
    }

    function testCannotUpdateWithdrawWhitelistToZeroAddress() public {
        vm.expectRevert("MarketMakerProxy: zero address");
        vm.prank(owner, owner);
        marketMakerProxy.updateWithdrawWhitelist(address(0), true);
    }

    function testUpdateWithdrawWhitelist() public {
        vm.expectEmit(true, true, true, true);
        emit UpdateWhitelist(withdrawer, true);
        vm.prank(owner, owner);
        marketMakerProxy.updateWithdrawWhitelist(withdrawer, true);
    }

    function testCannotWrapETHByNotOwner() public {
        vm.expectRevert("not owner");
        marketMakerProxy.wrapETH();
    }

    function testWrapETH() public {
        BalanceSnapshot.Snapshot memory walletWETHBalance = BalanceSnapshot.take({ owner: address(marketMakerProxy), token: address(weth) });

        uint256 walletBalance = address(marketMakerProxy).balance;
        vm.expectEmit(true, true, true, true);
        emit WrapETH(walletBalance);
        vm.prank(owner, owner);
        marketMakerProxy.wrapETH();

        walletWETHBalance.assertChange(int256(walletBalance));
        assertEq(address(marketMakerProxy).balance, uint256(0));
    }

    function testCannotWithdrawTokenByNotOwner() public {
        vm.expectRevert("not owner");
        marketMakerProxy.withdrawToken(address(usdc), withdrawer, 50);
    }

    function testCannotWithdrawTokenToNonWhitelisted() public {
        vm.expectRevert("MarketMakerProxy: not in withdraw whitelist");
        vm.prank(owner, owner);
        marketMakerProxy.withdrawToken(address(usdc), makeAddr("random"), 50);
    }

    function testWithdrawToken() public {
        address tokenAddr = address(usdc);
        uint256 withdrawAmount = 125;
        BalanceSnapshot.Snapshot memory walletTokenBalance = BalanceSnapshot.take({ owner: address(marketMakerProxy), token: tokenAddr });

        vm.prank(owner, owner);
        marketMakerProxy.withdrawToken(tokenAddr, withdrawer, withdrawAmount);

        walletTokenBalance.assertChange(-int256(withdrawAmount));
    }

    function testCannotWithdrawETHByNotOwner() public {
        vm.expectRevert("not owner");
        marketMakerProxy.withdrawETH(withdrawer, 1 ether);
    }

    function testCannotWithdrawETHToNonWhitelisted() public {
        vm.expectRevert("MarketMakerProxy: not in withdraw whitelist");
        vm.prank(owner, owner);
        marketMakerProxy.withdrawETH(payable(makeAddr("random")), 1 ether);
    }

    function testWithdrawETHToEOA() public {
        BalanceSnapshot.Snapshot memory walletETHBalance = BalanceSnapshot.take({ owner: address(marketMakerProxy), token: ETH_ADDRESS });
        BalanceSnapshot.Snapshot memory withdrawerETHBalance = BalanceSnapshot.take({ owner: withdrawer, token: ETH_ADDRESS });

        uint256 withdrawAmount = 1 ether;
        vm.expectEmit(true, true, true, true);
        emit WithdrawETH(withdrawAmount);
        vm.prank(owner, owner);
        marketMakerProxy.withdrawETH(withdrawer, withdrawAmount);

        walletETHBalance.assertChange(-int256(withdrawAmount));
        withdrawerETHBalance.assertChange(int256(withdrawAmount));
    }

    function testWithdrawETHToContract() public {
        // deploy a new contract wallet and add to whitelist
        MockERC1271Wallet anotherWallet = new MockERC1271Wallet(makeAddr("mockWalletOwner"));
        vm.prank(owner, owner);
        marketMakerProxy.updateWithdrawWhitelist(address(anotherWallet), true);

        BalanceSnapshot.Snapshot memory walletETHBalance = BalanceSnapshot.take({ owner: address(marketMakerProxy), token: ETH_ADDRESS });
        BalanceSnapshot.Snapshot memory withdrawerETHBalance = BalanceSnapshot.take({ owner: address(anotherWallet), token: ETH_ADDRESS });

        uint256 withdrawAmount = 2 ether;
        vm.expectEmit(true, true, true, true);
        emit WithdrawETH(withdrawAmount);
        vm.prank(owner, owner);
        marketMakerProxy.withdrawETH(payable(address(anotherWallet)), withdrawAmount);

        walletETHBalance.assertChange(-int256(withdrawAmount));
        withdrawerETHBalance.assertChange(int256(withdrawAmount));
    }

    function testIsValidSignatureNotSignedBySigner() public {
        bytes32 dataHash = keccak256("PLAINTEXT_DATA");
        uint256 randomPrivateKey = 1234;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(randomPrivateKey, dataHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.expectRevert("MarketMakerProxy: invalid signature");
        bytes4 result = marketMakerProxy.isValidSignature(dataHash, signature);
    }

    function testIsValidSignatureWithRandomBytes() public {
        bytes32 dataHash = keccak256("PLAINTEXT_DATA");
        bytes memory fakeSig = abi.encodePacked("apple", uint256(1234), true);
        vm.expectRevert("ECDSA: invalid signature length");
        bytes4 result = marketMakerProxy.isValidSignature(dataHash, fakeSig);
    }

    function testIsValidSignature() public {
        bytes32 dataHash = keccak256("PLAINTEXT_DATA");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, dataHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes4 result = marketMakerProxy.isValidSignature(dataHash, signature);
        assertEq(result, EIP1271_MAGICVALUE);
    }
}
