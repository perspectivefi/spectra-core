// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "forge-std/Test.sol";

import "src/libraries/RayMath.sol";
import "src/libraries/CurvePoolUtil.sol";

import {RouterBaseTest} from "./RouterBaseTest.t.sol";
import {Commands} from "src/router/Commands.sol";
import {Constants} from "src/router/Constants.sol";

contract ContractRouterTest is RouterBaseTest {
    using RayMath for uint256;

    function setUp() public override {
        super.setUp();
        underlying.mint(testUser, FAUCET_AMOUNT * 2);
        ibt.deposit(FAUCET_AMOUNT, testUser);
    }

    function testHasTokens() public {
        assertEq(ibt.balanceOf(testUser), FAUCET_AMOUNT);
        assertEq(underlying.balanceOf(testUser), FAUCET_AMOUNT);
    }

    function testHasApproved() public {
        assertEq(ibt.allowance(testUser, address(router)), FAUCET_AMOUNT);
        assertEq(underlying.allowance(testUser, address(router)), FAUCET_AMOUNT);
    }

    // -----------------------
    // --- EXECUTION TESTS ---
    // -----------------------

    function testTransferFromFuzz(uint256 amount) public {
        amount = bound(amount, 0, FAUCET_AMOUNT);
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

    function testTransferFromFuzzDeadline(uint256 amount) public {
        amount = bound(amount, 0, FAUCET_AMOUNT);
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

    function testSendBackPartFuzz(uint256 amount) public {
        amount = bound(amount, 0, FAUCET_AMOUNT);
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

    function testSwapIBTToPTFuzz(uint256 amount) public {
        amount = bound(amount, 1e10, FAUCET_AMOUNT);
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.CURVE_SWAP))
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

    function testWrapUnderlyingInIBTFuzz(uint256 amount) public {
        amount = bound(amount, 1, FAUCET_AMOUNT);
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

    function testRedeemIBTForUnderlyingFuzz(uint256 amount) public {
        amount = bound(amount, 1, FAUCET_AMOUNT);
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
            1, // May have 1 unit of dust during the unwrap
            "Router's IBT balance after router execution is wrong"
        );
        assertEq(
            ibt.balanceOf(other),
            ibtBalanceOfOtherBefore,
            "Other's IBT balance after router execution is wrong"
        );
    }

    function testDepositUnderlyingInPTFuzz(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1000, FAUCET_AMOUNT);
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.DEPOSIT_ASSET_IN_PT))
        );
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(underlying, depositAmount);
        inputs[1] = abi.encode(address(principalToken), depositAmount, testUser);

        uint256 underlyingBalanceOfUserBefore = underlying.balanceOf(testUser);
        uint256 underlyingBalanceOfRouterBefore = underlying.balanceOf(address(router));
        uint256 ibtBalanceOfUserBefore = ibt.balanceOf(testUser);
        uint256 ibtBalanceOfRouterBefore = ibt.balanceOf(address(router));
        uint256 ptBalanceOfUserBefore = principalToken.balanceOf(testUser);
        uint256 ptBalanceOfRouterBefore = principalToken.balanceOf(address(router));

        router.execute(commands, inputs);

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

    function testSwapUnderlyingToPTFuzz(uint256 swapAmount) public {
        swapAmount = bound(swapAmount, 1e10, FAUCET_AMOUNT);
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.DEPOSIT_ASSET_IN_IBT)),
            bytes1(uint8(Commands.CURVE_SWAP))
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

    function testFlashLoanFuzz(uint256 borrowAmount) public {
        borrowAmount = bound(borrowAmount, 0, principalToken.maxFlashLoan(testUser));
        bytes memory flashLoanCommands = abi.encodePacked(bytes1(uint8(Commands.TRANSFER_FROM)));
        bytes[] memory flashLoanInputs = new bytes[](1);
        flashLoanInputs[0] = abi.encode(underlying, FAUCET_AMOUNT);
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.FLASH_LOAN)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(
            address(principalToken),
            address(router),
            address(ibt),
            borrowAmount,
            abi.encode(flashLoanCommands, flashLoanInputs)
        );

        assertEq(underlying.balanceOf(address(this)), FAUCET_AMOUNT);
        assertEq(underlying.balanceOf(address(router)), 0);
        router.execute(commands, inputs);
        assertEq(underlying.balanceOf(address(this)), 0);
        assertEq(underlying.balanceOf(address(router)), FAUCET_AMOUNT);
    }

    function testMinimumBalanceCheckFuzz(uint256 amount) public {
        amount = bound(amount, 0, FAUCET_AMOUNT);
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

    function testMinimumBalanceCheckNotReachedFuzz(uint256 amount) public {
        amount = bound(amount, 1, FAUCET_AMOUNT);
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

    function testSwapIBTToPTBackAndForthFuzz(uint256 amount) public {
        amount = bound(amount, 1e10, FAUCET_AMOUNT);
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.CURVE_SWAP)),
            bytes1(uint8(Commands.CURVE_SWAP))
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

    function testPreviewSwapIBTToPTFuzz(uint256 swapAmount) public {
        swapAmount = bound(swapAmount, 1e18, 1e22); // Curve pool reverts when the swap amount is too low or too high due to liquidity
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.CURVE_SWAP)),
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

        uint256 outputRate = (curvePool.get_dy(0, 1, swapAmount) * Constants.UNIT) / swapAmount;

        uint256 previewRate = router.previewRate(commands, inputs).fromRay(
            CurvePoolUtil.CURVE_DECIMALS
        );

        assertEq(previewRate, outputRate);
    }

    function testPreviewSwapIBTToPTFuzz2(uint256 swapAmount) public {
        swapAmount = bound(swapAmount, 1e18, 1e22); // Curve pool reverts when the swap amount is too low or too high due to liquidity
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER)),
            bytes1(uint8(Commands.CURVE_SWAP))
        );
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(ibt, other, swapAmount);
        inputs[1] = abi.encode(
            address(curvePool),
            0, // IBT
            1, // PT
            swapAmount,
            0, // No min output
            testUser
        );

        uint256 outputRate = (curvePool.get_dy(0, 1, swapAmount) * Constants.UNIT) / swapAmount;

        uint256 previewRate = router.previewRate(commands, inputs).fromRay(
            CurvePoolUtil.CURVE_DECIMALS
        );

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

    function testPreviewSwapPTToIBTFuzz(uint256 swapAmount) public {
        swapAmount = bound(swapAmount, 1e18, 1e22); // Curve pool reverts when the swap amount is too low or too high due to liquidity
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.CURVE_SWAP))
        );
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(ibt, swapAmount);
        inputs[1] = abi.encode(
            address(curvePool),
            1, // PT
            0, // IBT
            swapAmount,
            0, // No min output
            testUser
        );

        uint256 outputRate = (curvePool.get_dy(1, 0, swapAmount) * Constants.UNIT) / swapAmount;

        uint256 previewRate = router.previewRate(commands, inputs).fromRay(18);

        assertEq(previewRate, outputRate);
    }

    function testPreviewSwapUnderlyingToPTFuzz(uint256 swapAmount) public {
        swapAmount = bound(swapAmount, 1e15, 1e20); // Curve pool reverts when the swap amount is too low or too high due to liquidity
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.DEPOSIT_ASSET_IN_IBT)),
            bytes1(uint8(Commands.CURVE_SWAP))
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
        uint256 outputRate = (curvePool.get_dy(0, 1, ibt.convertToShares(swapAmount)) *
            Constants.UNIT) / swapAmount;

        uint256 previewRate = router.previewRate(commands, inputs).fromRay(18);

        // The smaller the swap input, the worse the rate precision gets due to UL -> IBT conversion.
        // We can either increase the delta here, or the minimum swap input
        assertApproxEqAbs(previewRate, outputRate, 1e8);
    }

    function testPreviewSpotSwapUnderlyingToPT() public {
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.DEPOSIT_ASSET_IN_IBT)),
            bytes1(uint8(Commands.CURVE_SWAP))
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

        uint256 spotPrice = (routerUtil.spotExchangeRate(address(curvePool), 0, 1) *
            ibt.convertToShares(Constants.UNIT)) / Constants.UNIT; // We compute the final price ourselves

        uint256 previewRate = router.previewSpotRate(commands, inputs).fromRay(18);

        assertEq(previewRate, spotPrice);
    }

    function testPreviewSpotSwapPTToUnderlying() public {
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.CURVE_SWAP)),
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

        uint256 spotPrice = (routerUtil.spotExchangeRate(address(curvePool), 1, 0) *
            ibt.convertToAssets(Constants.UNIT)) / Constants.UNIT; // We compute the final price ourselves

        uint256 previewRate = router.previewSpotRate(commands, inputs).fromRay(18);

        assertEq(previewRate, spotPrice);
    }
}
