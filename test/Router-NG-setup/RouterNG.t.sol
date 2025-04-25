// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "forge-std/Test.sol";

import "src/libraries/RayMath.sol";

import {RouterNGBaseTest} from "./RouterNGBase.t.sol";
import {Commands} from "src/router/Commands.sol";
import {Constants} from "src/router/Constants.sol";

contract ContractRouterNGTest is RouterNGBaseTest {
    using RayMath for uint256;

    function setUp() public override {
        super.setUp();
        underlying.mint(testUser, FAUCET_AMOUNT * 3);
        ibt.deposit(FAUCET_AMOUNT * 2, testUser);

        ibt.approve(address(spectra4626Wrapper), FAUCET_AMOUNT);
        spectra4626Wrapper.wrap(FAUCET_AMOUNT, testUser);
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

    function testSwapIBTToPTFuzz(uint256 amount) public {
        amount = bound(amount, 1e10, FAUCET_AMOUNT);
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.CURVE_NG_SWAP))
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

    function testSwapUnderlyingToPTFuzz(uint256 swapAmount) public {
        swapAmount = bound(swapAmount, 1e10, FAUCET_AMOUNT);
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.DEPOSIT_ASSET_IN_IBT)),
            bytes1(uint8(Commands.CURVE_NG_SWAP))
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

    function testSwapIBTToPTBackAndForthFuzz(uint256 amount) public {
        amount = bound(amount, 1e10, FAUCET_AMOUNT);
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.CURVE_NG_SWAP)),
            bytes1(uint8(Commands.CURVE_NG_SWAP))
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
            bytes1(uint8(Commands.CURVE_NG_SWAP)),
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

    function testPreviewSwapPTToIBTFuzz(uint256 swapAmount) public {
        swapAmount = bound(swapAmount, 1e18, 1e22); // Curve pool reverts when the swap amount is too low or too high due to liquidity
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.CURVE_NG_SWAP))
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

    function testPreviewSwapUnderlyingToPTFuzz(uint256 swapAmount) public {
        swapAmount = bound(swapAmount, 1e15, 1e20); // Curve pool reverts when the swap amount is too low or too high due to liquidity
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.DEPOSIT_ASSET_IN_IBT)),
            bytes1(uint8(Commands.CURVE_NG_SWAP))
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
        assertApproxEqAbs(previewRate, outputRate, 1e8);
    }

    function testPreviewSpotSwapUnderlyingToPTNG() public {
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.DEPOSIT_ASSET_IN_IBT)),
            bytes1(uint8(Commands.CURVE_NG_SWAP))
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
            bytes1(uint8(Commands.CURVE_NG_SWAP)),
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
