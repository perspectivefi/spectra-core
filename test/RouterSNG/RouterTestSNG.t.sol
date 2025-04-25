// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "forge-std/Test.sol";

import "src/libraries/RayMath.sol";
import "src/libraries/CurvePoolUtil.sol";

import {RouterSNGBaseTest} from "./RouterSNGBaseTest.t.sol";
import {Commands} from "src/router/Commands.sol";
import {Constants} from "src/router/Constants.sol";

contract ContractRouterSNGTest is RouterSNGBaseTest {
    using RayMath for uint256;

    event RouterUtilChange(address indexed previousRouterUtil, address indexed newRouterUtil);
    event KyberRouterChange(address indexed previousKyberRouter, address indexed newKyberRouter);
    event Paused(address account);
    event Unpaused(address account);

    function setUp() public override {
        super.setUp();
    }

    function prepareTokens() public {
        underlying.mint(testUser, FAUCET_AMOUNT_UND * 3);
        ibt.deposit(FAUCET_AMOUNT_UND * 2, testUser);

        ibt.approve(address(spectra4626Wrapper), FAUCET_AMOUNT_IBT);
        spectra4626Wrapper.wrap(FAUCET_AMOUNT_IBT, testUser);
    }

    function testHasTokens(uint8 underlying_decimals, uint8 ibt_decimals) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(
            underlying_decimals,
            ibt_decimals,
            address(curvePool),
            curvePoolParams
        );
        this.prepareTokens();

        assertEq(ibt.balanceOf(testUser), FAUCET_AMOUNT_IBT);
        assertEq(underlying.balanceOf(testUser), FAUCET_AMOUNT_UND);
    }

    function testHasApproved(uint8 underlying_decimals, uint8 ibt_decimals) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(
            underlying_decimals,
            ibt_decimals,
            address(curvePool),
            curvePoolParams
        );
        this.prepareTokens();
        assertEq(ibt.allowance(testUser, address(router)), FAUCET_AMOUNT_IBT);
        assertEq(underlying.allowance(testUser, address(router)), FAUCET_AMOUNT_UND);
    }

    // -------------------------------
    // --- GETTERS & SETTERS TESTS ---
    // -------------------------------

    function testRouterGetters() public {
        assertEq(address(registry), router.getRegistry(), "registry getter is wrong");
        assertEq(address(routerUtil), router.getRouterUtil(), "routerUtil getter is wrong");
        assertEq(kyberRouterAddr, router.getKyberRouter(), "kyberRouter getter is wrong");
    }

    function testSetRouterUtil() public {
        address newRouterUtilAddr = address(0);
        bytes memory revertData = abi.encodeWithSelector(bytes4(keccak256("AddressError()")));
        vm.startPrank(scriptAdmin);
        vm.expectRevert(revertData);
        router.setRouterUtil(newRouterUtilAddr);

        newRouterUtilAddr = address(8);
        vm.startPrank(scriptAdmin);
        vm.expectEmit(true, true, true, false);
        emit RouterUtilChange(address(routerUtil), newRouterUtilAddr);
        router.setRouterUtil(newRouterUtilAddr);
        vm.stopPrank();
        assertEq(newRouterUtilAddr, router.getRouterUtil());
    }

    function testSetKyberRouter() public {
        address newKyberRouterAddr = address(9);
        vm.startPrank(scriptAdmin);
        vm.expectEmit(true, true, true, false);
        emit KyberRouterChange(kyberRouterAddr, newKyberRouterAddr);
        router.setKyberRouter(newKyberRouterAddr);
        vm.stopPrank();
        assertEq(newKyberRouterAddr, router.getKyberRouter());
    }

    // -----------------------
    // --- EXECUTION TESTS ---
    // -----------------------

    function testTransferFromFuzz(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 amount
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(
            underlying_decimals,
            ibt_decimals,
            address(curvePool),
            curvePoolParams
        );
        this.prepareTokens();
        amount = bound(amount, 0, FAUCET_AMOUNT_UND);
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.TRANSFER_FROM)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ibt, amount);

        uint256 ibtBalanceOfUserBefore = ibt.balanceOf(testUser);
        uint256 ibtBalanceOfRouterBefore = ibt.balanceOf(address(router));

        router.execute(commands, inputs);

        uint256 ibtBalanceOfUserAfter = ibt.balanceOf(testUser);
        uint256 ibtBalanceOfRouterAfter = ibt.balanceOf(address(router));

        assertEq(ibtBalanceOfUserBefore, ibtBalanceOfUserAfter + amount);
        assertEq(ibtBalanceOfRouterBefore + amount, ibtBalanceOfRouterAfter);
    }

    function testTransferFromWithDeadlineFuzz(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 amount
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(
            underlying_decimals,
            ibt_decimals,
            address(curvePool),
            curvePoolParams
        );
        this.prepareTokens();
        amount = bound(amount, 0, FAUCET_AMOUNT_UND);
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.TRANSFER_FROM)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ibt, amount);

        uint256 ibtBalanceOfUserBefore = ibt.balanceOf(testUser);
        uint256 ibtBalanceOfRouterBefore = ibt.balanceOf(address(router));

        vm.expectRevert();
        router.execute(commands, inputs, block.timestamp - 1);

        router.execute(commands, inputs, block.timestamp + 86400 * 3);

        uint256 ibtBalanceOfUserAfter = ibt.balanceOf(testUser);
        uint256 ibtBalanceOfRouterAfter = ibt.balanceOf(address(router));

        assertEq(ibtBalanceOfUserBefore, ibtBalanceOfUserAfter + amount);
        assertEq(ibtBalanceOfRouterBefore + amount, ibtBalanceOfRouterAfter);
    }

    function testTransferFromWithPermit() public {
        uint256 amount = 10e18;

        uint256 privateKey = 0xABCD;
        address owner = vm.addr(privateKey);

        underlying.mint(owner, amount);

        vm.startPrank(owner);
        underlying.approve(address(principalToken), amount);
        uint256 shares = principalToken.deposit(amount, owner);

        bytes32 PERMIT_TYPEHASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );
        uint256 deadline = block.timestamp + 10000;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    principalToken.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(PERMIT_TYPEHASH, owner, address(router), shares, 0, deadline)
                    )
                )
            )
        );

        assertEq(principalToken.allowance(owner, address(router)), 0);

        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.TRANSFER_FROM_WITH_PERMIT)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(address(principalToken), shares, deadline, v, r, s);

        uint256 ptBalanceOfUserBefore = principalToken.balanceOf(owner);
        uint256 ptBalanceOfRouterBefore = principalToken.balanceOf(address(router));

        router.execute(commands, inputs);

        uint256 ptBalanceOfUserAfter = principalToken.balanceOf(owner);
        uint256 ptBalanceOfRouterAfter = principalToken.balanceOf(address(router));

        assertEq(ptBalanceOfUserBefore, ptBalanceOfUserAfter + shares);
        assertEq(ptBalanceOfRouterBefore + shares, ptBalanceOfRouterAfter);

        vm.stopPrank();
    }

    function testSendBackPartFuzz(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 amount
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(
            underlying_decimals,
            ibt_decimals,
            address(curvePool),
            curvePoolParams
        );
        this.prepareTokens();
        amount = bound(amount, 0, FAUCET_AMOUNT_UND);
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.TRANSFER))
        );
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(ibt, amount);
        inputs[1] = abi.encode(ibt, testUser, amount / 5);

        uint256 ibtBalanceOfUserBefore = ibt.balanceOf(testUser);
        uint256 ibtBalanceOfRouterBefore = ibt.balanceOf(address(router));

        router.execute(commands, inputs);

        uint256 ibtBalanceOfUserAfter = ibt.balanceOf(testUser);
        uint256 ibtBalanceOfRouterAfter = ibt.balanceOf(address(router));

        assertEq(ibtBalanceOfUserBefore, ibtBalanceOfUserAfter + amount - (amount / 5));
        assertEq(ibtBalanceOfRouterBefore + amount - (amount / 5), ibtBalanceOfRouterAfter);
    }

    function testSwapIBTToPTFuzz(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 amount
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(
            underlying_decimals,
            ibt_decimals,
            address(curvePool),
            curvePoolParams
        );
        this.prepareTokens();
        amount = bound(amount, IBT_UNIT / 1000, FAUCET_AMOUNT_IBT);
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.CURVE_SWAP_SNG))
        );
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(ibt, amount);
        inputs[1] = abi.encode(
            address(curvePool),
            0,
            1,
            amount,
            0, // No min output
            testUser
        );

        // Expected output
        uint256 dy = curvePool.get_dy(0, 1, amount);

        uint256 ibtBalanceOfUserBefore = ibt.balanceOf(testUser);
        uint256 ibtBalanceOfRouterBefore = ibt.balanceOf(address(router));
        uint256 ptBalanceOfUserBefore = principalToken.balanceOf(testUser);
        uint256 ptBalanceOfRouterBefore = principalToken.balanceOf(address(router));

        router.execute(commands, inputs);

        assertEq(
            ibt.balanceOf(testUser) + amount,
            ibtBalanceOfUserBefore,
            "User's IBT balance after router execution is wrong"
        );
        assertEq(
            ibt.balanceOf(address(router)),
            ibtBalanceOfRouterBefore,
            "Router's IBT balance after router execution is wrong"
        );
        assertEq(
            principalToken.balanceOf(testUser),
            ptBalanceOfUserBefore + dy,
            "User's PT balance after router execution is wrong"
        );
        assertEq(
            principalToken.balanceOf(address(router)),
            ptBalanceOfRouterBefore,
            "Router's PT balance after router execution is wrong"
        );
    }

    function testWrapVaultInAdapterFuzz(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 amount
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(
            underlying_decimals,
            ibt_decimals,
            address(curvePool),
            curvePoolParams
        );
        this.prepareTokens();
        amount = bound(amount, 1, FAUCET_AMOUNT_UND);

        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.WRAP_VAULT_IN_4626_ADAPTER)),
            bytes1(uint8(Commands.TRANSFER))
        );
        bytes[] memory inputs = new bytes[](3);
        inputs[0] = abi.encode(ibt, amount);
        inputs[1] = abi.encode(spectra4626Wrapper, amount, router, 0);
        inputs[2] = abi.encode(spectra4626Wrapper, other, Constants.CONTRACT_BALANCE);

        uint256 ibtBalanceOfUserBefore = ibt.balanceOf(testUser);
        uint256 ibtBalanceOfRouterBefore = ibt.balanceOf(address(router));
        uint256 ibtBalanceOfOtherBefore = ibt.balanceOf(other);

        uint256 wrapperBalanceOfUserBefore = spectra4626Wrapper.balanceOf(testUser);
        uint256 wrapperBalanceOfRouterBefore = spectra4626Wrapper.balanceOf(address(router));
        uint256 wrapperBalanceOfOtherBefore = spectra4626Wrapper.balanceOf(other);

        uint256 expectedWrapperShares = spectra4626Wrapper.previewWrap(amount);

        router.execute(commands, inputs);

        assertEq(
            ibt.balanceOf(testUser) + amount,
            ibtBalanceOfUserBefore,
            "User's IBT balance after router execution is wrong"
        );
        assertEq(
            ibt.balanceOf(address(router)),
            ibtBalanceOfRouterBefore,
            "Router's IBT balance after router execution is wrong"
        );
        assertEq(
            ibt.balanceOf(other),
            ibtBalanceOfOtherBefore,
            "Other's IBT balance after router execution is wrong"
        );

        assertEq(
            spectra4626Wrapper.balanceOf(testUser),
            wrapperBalanceOfUserBefore,
            "User's Wrapper balance after router execution is wrong"
        );
        assertEq(
            spectra4626Wrapper.balanceOf(address(router)),
            wrapperBalanceOfRouterBefore,
            "Router's Wrapper balance after router execution is wrong"
        );
        assertEq(
            spectra4626Wrapper.balanceOf(other),
            wrapperBalanceOfOtherBefore + expectedWrapperShares,
            "Other's Wrapper balance after router execution is wrong"
        );
    }

    function testUnwrapVaultFromAdapterFuzz(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 amount
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(
            underlying_decimals,
            ibt_decimals,
            address(curvePool),
            curvePoolParams
        );
        this.prepareTokens();
        amount = bound(amount, 1, FAUCET_AMOUNT_UND);

        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.UNWRAP_VAULT_FROM_4626_ADAPTER)),
            bytes1(uint8(Commands.TRANSFER))
        );
        bytes[] memory inputs = new bytes[](3);
        inputs[0] = abi.encode(spectra4626Wrapper, amount);
        inputs[1] = abi.encode(spectra4626Wrapper, amount, router, 0);
        inputs[2] = abi.encode(ibt, other, Constants.CONTRACT_BALANCE);

        uint256 ibtBalanceOfUserBefore = ibt.balanceOf(testUser);
        uint256 ibtBalanceOfRouterBefore = ibt.balanceOf(address(router));
        uint256 ibtBalanceOfOtherBefore = ibt.balanceOf(other);

        uint256 wrapperBalanceOfUserBefore = spectra4626Wrapper.balanceOf(testUser);
        uint256 wrapperBalanceOfRouterBefore = spectra4626Wrapper.balanceOf(address(router));
        uint256 wrapperBalanceOfOtherBefore = spectra4626Wrapper.balanceOf(other);

        uint256 expectedVaultShares = spectra4626Wrapper.previewUnwrap(amount);

        router.execute(commands, inputs);

        assertEq(
            ibt.balanceOf(testUser),
            ibtBalanceOfUserBefore,
            "User's IBT balance after router execution is wrong"
        );
        assertEq(
            ibt.balanceOf(address(router)),
            ibtBalanceOfRouterBefore,
            "Router's IBT balance after router execution is wrong"
        );
        assertEq(
            ibt.balanceOf(other),
            ibtBalanceOfOtherBefore + expectedVaultShares,
            "Other's IBT balance after router execution is wrong"
        );

        assertEq(
            spectra4626Wrapper.balanceOf(testUser) + amount,
            wrapperBalanceOfUserBefore,
            "User's Wrapper balance after router execution is wrong"
        );
        assertEq(
            spectra4626Wrapper.balanceOf(address(router)),
            wrapperBalanceOfRouterBefore,
            "Router's Wrapper balance after router execution is wrong"
        );
        assertEq(
            spectra4626Wrapper.balanceOf(other),
            wrapperBalanceOfOtherBefore,
            "Other's Wrapper balance after router execution is wrong"
        );
    }

    function testDepositAssetInIBTFuzz(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 amount
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));

        super.deployProtocol(
            underlying_decimals,
            ibt_decimals,
            address(curvePool),
            curvePoolParams
        );
        this.prepareTokens();

        amount = bound(amount, 1, FAUCET_AMOUNT_UND);
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.DEPOSIT_ASSET_IN_IBT)),
            bytes1(uint8(Commands.TRANSFER))
        );
        bytes[] memory inputs = new bytes[](3);
        inputs[0] = abi.encode(underlying, amount);
        inputs[1] = abi.encode(ibt, amount, router);
        inputs[2] = abi.encode(ibt, other, Constants.CONTRACT_BALANCE);

        uint256 underlyingBalanceOfUserBefore = underlying.balanceOf(testUser);
        uint256 underlyingBalanceOfRouterBefore = underlying.balanceOf(address(router));
        uint256 underlyingBalanceOfOtherBefore = underlying.balanceOf(other);
        uint256 ibtBalanceOfUserBefore = ibt.balanceOf(testUser);
        uint256 ibtBalanceOfRouterBefore = ibt.balanceOf(address(router));
        uint256 ibtBalanceOfOtherBefore = ibt.balanceOf(other);

        router.execute(commands, inputs);

        assertEq(
            underlying.balanceOf(testUser) + amount,
            underlyingBalanceOfUserBefore,
            "User's underlying balance after router execution is wrong"
        );
        assertEq(
            underlying.balanceOf(address(router)),
            underlyingBalanceOfRouterBefore,
            "Router's underlying balance after router execution is wrong"
        );
        assertEq(
            underlying.balanceOf(other),
            underlyingBalanceOfOtherBefore,
            "Other's underlying balance after router execution is wrong"
        );
        assertEq(
            ibt.balanceOf(testUser),
            ibtBalanceOfUserBefore,
            "User's IBT balance after router execution is wrong"
        );
        assertEq(
            ibt.balanceOf(address(router)),
            ibtBalanceOfRouterBefore,
            "Router's IBT balance after router execution is wrong"
        );
        assertEq(
            ibt.balanceOf(other),
            ibtBalanceOfOtherBefore + ibt.convertToShares(amount),
            "Other's IBT balance after router execution is wrong"
        );
    }

    function testRedeemIBTForUnderlyingFuzz(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 amount
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(
            underlying_decimals,
            ibt_decimals,
            address(curvePool),
            curvePoolParams
        );
        this.prepareTokens();

        amount = bound(amount, 1, FAUCET_AMOUNT_UND);
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.REDEEM_IBT_FOR_ASSET)),
            bytes1(uint8(Commands.TRANSFER))
        );
        bytes[] memory inputs = new bytes[](3);
        inputs[0] = abi.encode(ibt, amount);
        inputs[1] = abi.encode(ibt, amount, router);
        inputs[2] = abi.encode(underlying, other, Constants.CONTRACT_BALANCE);

        uint256 underlyingBalanceOfUserBefore = underlying.balanceOf(testUser);
        uint256 underlyingBalanceOfRouterBefore = underlying.balanceOf(address(router));
        uint256 underlyingBalanceOfOtherBefore = underlying.balanceOf(other);
        uint256 ibtBalanceOfUserBefore = ibt.balanceOf(testUser);
        uint256 ibtBalanceOfRouterBefore = ibt.balanceOf(address(router));
        uint256 ibtBalanceOfOtherBefore = ibt.balanceOf(other);

        router.execute(commands, inputs);

        assertEq(
            underlying.balanceOf(testUser),
            underlyingBalanceOfUserBefore,
            "User's underlying balance after router execution is wrong"
        );
        assertEq(
            underlying.balanceOf(address(router)),
            underlyingBalanceOfRouterBefore,
            "Router's underlying balance after router execution is wrong"
        );
        assertEq(
            underlying.balanceOf(other),
            underlyingBalanceOfOtherBefore + ibt.convertToAssets(amount),
            "Other's underlying balance after router execution is wrong"
        );
        assertEq(
            ibtBalanceOfUserBefore,
            ibt.balanceOf(testUser) + amount,
            "User's IBT balance after router execution is wrong"
        );
        assertApproxEqAbs(
            ibt.balanceOf(address(router)),
            ibtBalanceOfRouterBefore,
            1, // May have 1 unit of dust during the redeem
            "Router's IBT balance after router execution is wrong"
        );
        assertEq(
            ibt.balanceOf(other),
            ibtBalanceOfOtherBefore,
            "Other's IBT balance after router execution is wrong"
        );
    }

    function testDepositUnderlyingInRegisteredPTFuzz(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 depositAmount
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(
            underlying_decimals,
            ibt_decimals,
            address(curvePool),
            curvePoolParams
        );
        this.prepareTokens();
        depositAmount = bound(depositAmount, 1000, FAUCET_AMOUNT_UND);
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.DEPOSIT_ASSET_IN_PT))
        );
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(underlying, depositAmount);
        inputs[1] = abi.encode(address(principalToken), depositAmount, testUser, testUser, 0);

        uint256 underlyingBalanceOfUserBefore = underlying.balanceOf(testUser);
        uint256 underlyingBalanceOfRouterBefore = underlying.balanceOf(address(router));
        uint256 ibtBalanceOfUserBefore = ibt.balanceOf(testUser);
        uint256 ibtBalanceOfRouterBefore = ibt.balanceOf(address(router));
        uint256 ptBalanceOfUserBefore = principalToken.balanceOf(testUser);
        uint256 ptBalanceOfRouterBefore = principalToken.balanceOf(address(router));

        assertEq(underlying.allowance(address(router), address(principalToken)), 0);

        router.execute(commands, inputs);

        assertEq(underlying.allowance(address(router), address(principalToken)), type(uint256).max);

        assertEq(
            underlying.balanceOf(testUser) + depositAmount,
            underlyingBalanceOfUserBefore,
            "User's underlying balance after router execution is wrong"
        );
        assertEq(
            underlying.balanceOf(address(router)),
            underlyingBalanceOfRouterBefore,
            "Router's underlying balance after router execution is wrong"
        );
        assertEq(
            ibt.balanceOf(testUser),
            ibtBalanceOfUserBefore,
            "User's IBT balance after router execution is wrong"
        );
        assertEq(
            ibt.balanceOf(address(router)),
            ibtBalanceOfRouterBefore,
            "Router's IBT balance after router execution is wrong"
        );
        assertApproxEqAbs(
            principalToken.balanceOf(testUser),
            ptBalanceOfUserBefore + principalToken.convertToPrincipal(depositAmount),
            100,
            "User's PT balance after router execution is wrong"
        );
        assertEq(
            principalToken.balanceOf(address(router)),
            ptBalanceOfRouterBefore,
            "Router's PT balance after router execution is wrong"
        );
    }

    function testDepositUnderlyingInUnregisteredPTFuzz(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 depositAmount
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(
            underlying_decimals,
            ibt_decimals,
            address(curvePool),
            curvePoolParams
        );
        this.prepareTokens();
        depositAmount = bound(depositAmount, 1000, FAUCET_AMOUNT_UND);

        // unregister PT from Registry
        vm.prank(scriptAdmin);
        registry.removePT(address(principalToken));

        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.DEPOSIT_ASSET_IN_PT))
        );
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(underlying, depositAmount);
        inputs[1] = abi.encode(address(principalToken), depositAmount, testUser, testUser, 0);

        uint256 underlyingBalanceOfUserBefore = underlying.balanceOf(testUser);
        uint256 underlyingBalanceOfRouterBefore = underlying.balanceOf(address(router));
        uint256 ibtBalanceOfUserBefore = ibt.balanceOf(testUser);
        uint256 ibtBalanceOfRouterBefore = ibt.balanceOf(address(router));
        uint256 ptBalanceOfUserBefore = principalToken.balanceOf(testUser);
        uint256 ptBalanceOfRouterBefore = principalToken.balanceOf(address(router));

        assertEq(underlying.allowance(address(router), address(principalToken)), 0);

        router.execute(commands, inputs);

        assertEq(underlying.allowance(address(router), address(principalToken)), 0);

        assertEq(
            underlying.balanceOf(testUser) + depositAmount,
            underlyingBalanceOfUserBefore,
            "User's underlying balance after router execution is wrong"
        );
        assertEq(
            underlying.balanceOf(address(router)),
            underlyingBalanceOfRouterBefore,
            "Router's underlying balance after router execution is wrong"
        );
        assertEq(
            ibt.balanceOf(testUser),
            ibtBalanceOfUserBefore,
            "User's IBT balance after router execution is wrong"
        );
        assertEq(
            ibt.balanceOf(address(router)),
            ibtBalanceOfRouterBefore,
            "Router's IBT balance after router execution is wrong"
        );
        assertApproxEqAbs(
            principalToken.balanceOf(testUser),
            ptBalanceOfUserBefore + principalToken.convertToPrincipal(depositAmount),
            100,
            "User's PT balance after router execution is wrong"
        );
        assertEq(
            principalToken.balanceOf(address(router)),
            ptBalanceOfRouterBefore,
            "Router's PT balance after router execution is wrong"
        );
    }

    function testSwapUnderlyingToPTFuzz(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 swapAmount
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(
            underlying_decimals,
            ibt_decimals,
            address(curvePool),
            curvePoolParams
        );
        this.prepareTokens();
        swapAmount = bound(swapAmount, UNDERLYING_UNIT / 1000, FAUCET_AMOUNT_UND);
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.DEPOSIT_ASSET_IN_IBT)),
            bytes1(uint8(Commands.CURVE_SWAP_SNG))
        );
        bytes[] memory inputs = new bytes[](3);
        inputs[0] = abi.encode(underlying, swapAmount);
        inputs[1] = abi.encode(address(ibt), Constants.CONTRACT_BALANCE, router);
        inputs[2] = abi.encode(
            address(curvePool),
            0,
            1,
            Constants.CONTRACT_BALANCE,
            0, // No min output
            testUser
        );

        uint256 dy = curvePool.get_dy(0, 1, ibt.convertToShares(swapAmount));

        uint256 underlyingBalanceOfUserBefore = underlying.balanceOf(testUser);
        uint256 underlyingBalanceOfRouterBefore = underlying.balanceOf(address(router));
        uint256 ibtBalanceOfUserBefore = ibt.balanceOf(testUser);
        uint256 ibtBalanceOfRouterBefore = ibt.balanceOf(address(router));
        uint256 ptBalanceOfUserBefore = principalToken.balanceOf(testUser);
        uint256 ptBalanceOfRouterBefore = principalToken.balanceOf(address(router));

        router.execute(commands, inputs);

        assertEq(
            underlying.balanceOf(testUser) + swapAmount,
            underlyingBalanceOfUserBefore,
            "User's underlying balance after router execution is wrong"
        );
        assertEq(
            underlying.balanceOf(address(router)),
            underlyingBalanceOfRouterBefore,
            "Router's underlying balance after router execution is wrong"
        );
        assertEq(
            ibt.balanceOf(testUser),
            ibtBalanceOfUserBefore,
            "User's IBT balance after router execution is wrong"
        );
        assertEq(
            ibt.balanceOf(address(router)),
            ibtBalanceOfRouterBefore,
            "Router's IBT balance after router execution is wrong"
        );
        assertEq(
            principalToken.balanceOf(testUser),
            ptBalanceOfUserBefore + dy,
            "User's PT balance after router execution is wrong"
        );
        assertEq(
            principalToken.balanceOf(address(router)),
            ptBalanceOfRouterBefore,
            "Router's PT balance after router execution is wrong"
        );
    }

    function testFlashLoanFuzz(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 borrowAmount
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(
            underlying_decimals,
            ibt_decimals,
            address(curvePool),
            curvePoolParams
        );
        this.prepareTokens();
        borrowAmount = bound(borrowAmount, 0, principalToken.maxFlashLoan(testUser));
        bytes memory flashLoanCommands = abi.encodePacked(bytes1(uint8(Commands.TRANSFER_FROM)));
        bytes[] memory flashLoanInputs = new bytes[](1);
        flashLoanInputs[0] = abi.encode(underlying, FAUCET_AMOUNT_UND);
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.FLASH_LOAN)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(
            address(principalToken),
            address(ibt),
            borrowAmount,
            abi.encode(flashLoanCommands, flashLoanInputs)
        );

        assertEq(underlying.balanceOf(address(this)), FAUCET_AMOUNT_UND);
        assertEq(underlying.balanceOf(address(router)), 0);
        router.execute(commands, inputs);
        assertEq(underlying.balanceOf(address(this)), 0);
        assertEq(underlying.balanceOf(address(router)), FAUCET_AMOUNT_UND);
    }

    function testFlashLoanInvalidLender() public {
        // unregister PT
        vm.prank(scriptAdmin);
        registry.removePT(address(principalToken));

        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.FLASH_LOAN)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(
            address(principalToken),
            address(ibt),
            1e18,
            bytes("") // empty flashloan data
        );

        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("InvalidFlashloanLender(address)")),
            address(principalToken)
        );
        vm.expectRevert(revertData);
        router.execute(commands, inputs);
    }

    function testMinimumBalanceCheckFuzz(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 amount
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(
            underlying_decimals,
            ibt_decimals,
            address(curvePool),
            curvePoolParams
        );
        this.prepareTokens();
        amount = bound(amount, 0, FAUCET_AMOUNT_UND);
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.ASSERT_MIN_BALANCE))
        );
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(ibt, amount);
        inputs[1] = abi.encode(ibt, Constants.ADDRESS_THIS, amount);
        // We send an amount of tokens to the router, then check it has been received within the same execution
        router.execute(commands, inputs);
    }

    function testMinimumBalanceCheckNotReachedFuzz(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 amount
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(
            underlying_decimals,
            ibt_decimals,
            address(curvePool),
            curvePoolParams
        );
        this.prepareTokens();
        amount = bound(amount, 1, FAUCET_AMOUNT_UND);
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.ASSERT_MIN_BALANCE)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ibt, Constants.ADDRESS_THIS, amount);

        vm.expectRevert();
        router.execute(commands, inputs);
    }

    function testInvalidDispatcherCommand() public {
        bytes memory commands = abi.encodePacked(bytes1(uint8(123)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ibt, Constants.ADDRESS_THIS, 1e18);

        vm.expectRevert();
        router.execute(commands, inputs);
    }

    function testSwapIBTToPTBackAndForthFuzz(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 amount
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(
            underlying_decimals,
            ibt_decimals,
            address(curvePool),
            curvePoolParams
        );
        this.prepareTokens();
        amount = bound(amount, IBT_UNIT / 1000, FAUCET_AMOUNT_IBT);
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.CURVE_SWAP_SNG)),
            bytes1(uint8(Commands.CURVE_SWAP_SNG))
        );
        bytes[] memory inputs = new bytes[](3);
        inputs[0] = abi.encode(ibt, amount);
        inputs[1] = abi.encode(
            address(curvePool),
            0, // IBT
            1, // PT
            amount,
            0, // No min output
            Constants.ADDRESS_THIS
        );
        inputs[2] = abi.encode(
            address(curvePool),
            1, // PT
            0, // IBT
            Constants.CONTRACT_BALANCE,
            0, // No min output
            testUser
        );

        uint256 ibtBalanceOfUserBefore = ibt.balanceOf(testUser);
        uint256 ibtBalanceOfRouterBefore = ibt.balanceOf(address(router));
        uint256 ptBalanceOfUserBefore = principalToken.balanceOf(testUser);
        uint256 ptBalanceOfRouterBefore = principalToken.balanceOf(address(router));

        router.execute(commands, inputs);

        assertApproxEqRel(
            ibt.balanceOf(testUser),
            ibtBalanceOfUserBefore,
            curvePool.fee() * 2 * 1e10, // Fee is 1e8 -> bring it to 1e18
            "User's IBT balance after router execution is wrong"
        );
        assertEq(
            ibt.balanceOf(address(router)),
            ibtBalanceOfRouterBefore,
            "Router's IBT balance after router execution is wrong"
        );
        assertEq(
            principalToken.balanceOf(testUser),
            ptBalanceOfUserBefore,
            "User's PT balance after router execution is wrong"
        );
        assertEq(
            principalToken.balanceOf(address(router)),
            ptBalanceOfRouterBefore,
            "Router's PT balance after router execution is wrong"
        );
    }

    // -----------------------
    // ---- PREVIEW TESTS ----
    // -----------------------

    function testPreviewSwapIBTToPTFuzz(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 swapAmount
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(
            underlying_decimals,
            ibt_decimals,
            address(curvePool),
            curvePoolParams
        );
        this.prepareTokens();
        swapAmount = bound(swapAmount, IBT_UNIT, 1000 * IBT_UNIT); // Curve pool reverts when the swap amount is too low or too high due to liquidity
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.CURVE_SWAP_SNG)),
            bytes1(uint8(Commands.ASSERT_MIN_BALANCE))
        );
        bytes[] memory inputs = new bytes[](3);
        inputs[0] = abi.encode(ibt, swapAmount);
        inputs[1] = abi.encode(
            address(curvePool),
            0, // IBT
            1, // PT
            swapAmount,
            0, // No min output
            testUser
        );
        inputs[2] = abi.encode(ibt, Constants.ADDRESS_THIS, swapAmount);

        uint256 outputRate = (curvePool.get_dy(0, 1, swapAmount) * RayMath.RAY_UNIT) / swapAmount;

        uint256 previewRate = router.previewRate(commands, inputs);

        assertEq(previewRate, outputRate);
    }

    function testPreviewDispatcherInvalidCommandFuzz(uint256 swapAmount) public {
        swapAmount = 1e18; // Curve pool reverts when the swap amount is too low or too high due to liquidity
        bytes memory commands = abi.encodePacked(bytes1(uint8(123)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(ibt, other, swapAmount);
        vm.expectRevert();
        router.previewRate(commands, inputs);
    }

    function testPreviewSwapPTToIBTFuzz(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 swapAmount
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(
            underlying_decimals,
            ibt_decimals,
            address(curvePool),
            curvePoolParams
        );
        this.prepareTokens();
        swapAmount = bound(swapAmount, IBT_UNIT, 1000 * IBT_UNIT); // Curve pool reverts when the swap amount is too low or too high due to liquidity
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.CURVE_SWAP_SNG))
        );
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(address(principalToken), swapAmount);
        inputs[1] = abi.encode(
            address(curvePool),
            1, // PT
            0, // IBT
            swapAmount,
            0, // No min output
            testUser
        );

        uint256 outputRate = (curvePool.get_dy(1, 0, swapAmount) * RayMath.RAY_UNIT) / swapAmount;

        uint256 previewRate = router.previewRate(commands, inputs);

        assertEq(previewRate, outputRate);
    }

    function testPreviewSwapUnderlyingToPTFuzz(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 swapAmount
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(
            underlying_decimals,
            ibt_decimals,
            address(curvePool),
            curvePoolParams
        );
        this.prepareTokens();
        swapAmount = bound(swapAmount, UNDERLYING_UNIT / 100, 100 * UNDERLYING_UNIT); // Curve pool reverts when the swap amount is too low or too high due to liquidity
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.DEPOSIT_ASSET_IN_IBT)),
            bytes1(uint8(Commands.CURVE_SWAP_SNG))
        );
        bytes[] memory inputs = new bytes[](3);
        inputs[0] = abi.encode(address(underlying), swapAmount);
        inputs[1] = abi.encode(address(ibt), Constants.CONTRACT_BALANCE, router);
        inputs[2] = abi.encode(
            address(curvePool),
            0,
            1,
            Constants.CONTRACT_BALANCE,
            0, // No min output
            testUser
        );
        uint256 outputRate = (curvePool.get_dy(0, 1, ibt.convertToShares(swapAmount)) *
            RayMath.RAY_UNIT) / swapAmount;

        uint256 previewRate = router.previewRate(commands, inputs);

        // The smaller the swap input, the worse the rate precision gets due to UL -> IBT conversion.
        // We can either increase the delta here, or the minimum swap input
        assertApproxEqRel(previewRate, outputRate, 1e5);
    }

    function testPreviewSpotSwapUnderlyingToPT() public {
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.DEPOSIT_ASSET_IN_IBT)),
            bytes1(uint8(Commands.CURVE_SWAP_SNG))
        );
        bytes[] memory inputs = new bytes[](3);
        inputs[0] = abi.encode(address(underlying), 0);
        inputs[1] = abi.encode(address(ibt), Constants.CONTRACT_BALANCE, router);
        inputs[2] = abi.encode(
            address(curvePool),
            0,
            1,
            Constants.CONTRACT_BALANCE,
            0, // No min output
            testUser
        );

        uint256 spotPrice = (routerUtil.spotExchangeRateSNG(address(curvePool), 0, 1) *
            ibt.convertToShares(Constants.UNIT)) / Constants.UNIT; // We compute the final price ourselves

        uint256 previewRate = router.previewSpotRate(commands, inputs).fromRay(18);

        assertEq(previewRate, spotPrice);
    }

    function testPreviewSpotSwapPTToUnderlyingSNG() public {
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.CURVE_SWAP_SNG)),
            bytes1(uint8(Commands.REDEEM_IBT_FOR_ASSET))
        );
        bytes[] memory inputs = new bytes[](3);
        inputs[0] = abi.encode(principalToken, 0);
        inputs[1] = abi.encode(
            address(curvePool),
            1, // PT
            0, // IBT
            Constants.CONTRACT_BALANCE,
            0, // No min output
            testUser
        );
        inputs[2] = abi.encode(address(ibt), Constants.CONTRACT_BALANCE, testUser);

        uint256 spotPrice = (routerUtil.spotExchangeRateSNG(address(curvePool), 1, 0) *
            ibt.convertToAssets(Constants.UNIT)) / Constants.UNIT; // We compute the final price ourselves

        uint256 previewRate = router.previewSpotRate(commands, inputs).fromRay(18);

        assertEq(previewRate, spotPrice);
    }

    // -----------------------------
    // ---- MISCELLANEOUS TESTS ----
    // -----------------------------

    function testPauseRouter() public {
        bytes memory commands;
        bytes[] memory inputs;

        vm.expectEmit(true, true, true, true);
        emit Paused(scriptAdmin);
        vm.prank(scriptAdmin);
        router.pause();

        bytes memory revertData = abi.encodeWithSignature("EnforcedPause()");

        vm.expectRevert(revertData);
        router.previewRate(commands, inputs);

        vm.expectRevert(revertData);
        router.previewSpotRate(commands, inputs);

        vm.expectRevert(revertData);
        router.execute(commands, inputs);

        vm.expectRevert(revertData);
        router.execute(commands, inputs, block.timestamp + 1000);

        vm.expectEmit(true, true, true, true);
        emit Unpaused(scriptAdmin);
        vm.prank(scriptAdmin);
        router.unPause();

        router.previewRate(commands, inputs);

        router.previewSpotRate(commands, inputs);

        router.execute(commands, inputs);

        router.execute(commands, inputs, block.timestamp + 1000);
    }
}
