// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "openzeppelin-math/Math.sol";
import "src/libraries/CurvePoolUtil.sol";
import "../../src/libraries/Roles.sol";
import {RouterSNGBaseTest} from "./RouterSNGBaseTest.t.sol";
import {Commands} from "src/router/Commands.sol";
import {Constants} from "src/router/Constants.sol";
import {ICurvePool} from "src/interfaces/ICurvePool.sol";

contract ContractRouterUtilSNGTest is RouterSNGBaseTest {
    using Math for uint256;

    uint256 public constant ERROR_MARGIN = 1e15; //@dev allow for 10 bps of error on YT trading
    uint256 public constant BALANCE_TRADING_FACTOR_PT_IBT = 10;
    uint256 public constant BALANCE_TRADING_FACTOR_IBT_YT = 100;

    function testSpotExchangeRateValidity() public {
        // We verify that the function works correctly using that 1 IBT is worth more than 1 PT
        uint256 ibtInPT = routerUtil.spotExchangeRateSNG(address(curvePool), 0, 1);
        assertTrue(ibtInPT >= CurvePoolUtil.CURVE_UNIT);

        uint256 ptInIBT = routerUtil.spotExchangeRateSNG(address(curvePool), 1, 0);
        assertTrue(ptInIBT <= CurvePoolUtil.CURVE_UNIT);
    }

    //############################################### Preview Flash Swap Tests #######################################################

    function testIBTToExactYTFlashSwapFuzzSNG(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 ytWanted
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(underlying_decimals, ibt_decimals, address(factory), curvePoolParams);
        ytWanted = bound(ytWanted, IBT_UNIT, curvePool.balances(1) / 100);
        uint256 ytUnit = routerUtil.getUnit(address(yt));
        uint256 ytIBTSpot = routerUtil.convertIBTToYTSpotSNG(ytUnit, address(curvePool));
        uint256 minAmountOfIBT = ytWanted.mulDiv(ytUnit, ytIBTSpot);

        (uint256 amountIBTNeeded, ) = routerUtil.previewFlashSwapIBTToExactYTSNG(
            address(curvePool),
            ytWanted
        );

        // price impact + swap fees
        uint256 priceImpactPaid = _getCurvePriceImpactLossAndFees(1, 0, ytWanted);

        assertApproxEqRel(minAmountOfIBT + priceImpactPaid, amountIBTNeeded, ERROR_MARGIN);
    }

    function testExactYTToIBTFlashSwapFuzzSNG(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 inputYTAmount
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(underlying_decimals, ibt_decimals, address(factory), curvePoolParams);
        inputYTAmount = bound(inputYTAmount, IBT_UNIT, curvePool.balances(0) / 100);

        uint256 ytIBTSpot = routerUtil.convertIBTToYTSpotSNG(IBT_UNIT, address(curvePool));
        uint256 ytUnit = routerUtil.getUnit(address(yt));
        uint256 maxIBTReceived = inputYTAmount.mulDiv(ytUnit, ytIBTSpot);

        (uint256 ibtReceived, uint256 borrowedIBTAmount) = routerUtil
            .previewFlashSwapExactYTToIBTSNG(address(curvePool), inputYTAmount);

        // We need to swap borrowedIBTAmount of IBT to PT. We calculate the price impact and
        // the fees associated to this swap. This amount is in PT, hence we convert using the marginal
        // price of PT/IBT in order to quote the amount in IBT
        uint256 priceImpactAndFees = _getCurvePriceImpactLossAndFees(0, 1, borrowedIBTAmount)
            .mulDiv(
                routerUtil.spotExchangeRateSNG(address(curvePool), 1, 0),
                CurvePoolUtil.CURVE_UNIT
            );

        // Here we need a larger error margin due to the usage of IStableSwapNG::get_dx
        assertApproxEqRel(maxIBTReceived, ibtReceived + priceImpactAndFees, ERROR_MARGIN);
    }

    function testSecantMethodPrecisionFuzzSNG(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 inputIBTAmount
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(underlying_decimals, ibt_decimals, address(factory), curvePoolParams);
        inputIBTAmount = bound(inputIBTAmount, IBT_UNIT, curvePool.balances(1) / 10);
        (uint256 outputYTAmount, ) = routerUtil.previewFlashSwapExactIBTToYTSNG(
            address(curvePool),
            inputIBTAmount
        );

        (uint256 inputIBTAmountRequired, ) = routerUtil.previewFlashSwapIBTToExactYTSNG(
            address(curvePool),
            outputYTAmount
        );

        assertApproxEqRel(inputIBTAmount, inputIBTAmountRequired, ERROR_MARGIN);
    }

    function testFlashSwapCycleFuzz(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 inputIBTAmount
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(underlying_decimals, ibt_decimals, address(factory), curvePoolParams);
        inputIBTAmount = bound(inputIBTAmount, IBT_UNIT, curvePool.balances(1) / 100);

        (uint256 outputYTAmount, ) = routerUtil.previewFlashSwapExactIBTToYTSNG(
            address(curvePool),
            inputIBTAmount
        );

        // We swap IBT for PT. We are left with outputYTAmount PT, that we swap back for IBT. We evalute the loss
        // associated to this swap
        uint256 priceImpactAndFees1 = _getCurvePriceImpactLossAndFees(1, 0, outputYTAmount);

        (uint256 outputIBTAmount, uint256 borrowedIBTAmount2) = routerUtil
            .previewFlashSwapExactYTToIBTSNG(address(curvePool), outputYTAmount);

        // We need to swap borrowedIBTAmount2 of IBT to PT. We calculate the price impact and
        // the fees associated to this swap. This amount is in PT, hence we convert using the marginal
        // price of PT/IBT in order to quote the amount in IBT
        uint256 priceImpactAndFees2 = _getCurvePriceImpactLossAndFees(0, 1, borrowedIBTAmount2)
            .mulDiv(
                routerUtil.spotExchangeRateSNG(address(curvePool), 1, 0),
                CurvePoolUtil.CURVE_UNIT
            );

        assertApproxEqRel(
            inputIBTAmount,
            outputIBTAmount + priceImpactAndFees2 + priceImpactAndFees1,
            ERROR_MARGIN
        );
    }

    //############################################### Preview Curve Liquidity Tests #######################################################

    function testPreviewAddWithAssetAndRemoveLiquidityFuzz(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 amount
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(underlying_decimals, ibt_decimals, address(factory), curvePoolParams);
        uint256 amountStart = bound(amount, UNDERLYING_UNIT, 1_000_000 * UNDERLYING_UNIT);
        uint256 expectedMintAmount = routerUtil.previewAddLiquidityWithAssetSNG(
            address(curvePool),
            amountStart
        );
        uint256 amountEnd = routerUtil.previewRemoveLiquidityForAssetSNG(
            address(curvePool),
            expectedMintAmount
        );
        assertApproxEqRel(amountStart, amountEnd, ERROR_MARGIN);
    }

    function testPreviewAddWithIBTAndRemoveLiquidityFuzz(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 amount
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(underlying_decimals, ibt_decimals, address(factory), curvePoolParams);
        uint256 amountStart = bound(amount, IBT_UNIT, 1_000_000 * IBT_UNIT);
        uint256 expectedMintAmount = routerUtil.previewAddLiquidityWithIBTSNG(
            address(curvePool),
            amountStart
        );
        uint256 amountEnd = routerUtil.previewRemoveLiquidityForIBTSNG(
            address(curvePool),
            expectedMintAmount
        );
        assertApproxEqRel(amountStart, amountEnd, ERROR_MARGIN);
    }

    function testPreviewAddAndRemoveLiquidityFuzz(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 amount
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(underlying_decimals, ibt_decimals, address(factory), curvePoolParams);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = bound(amount, IBT_UNIT, 1_000_000 * IBT_UNIT);
        amounts[1] = amounts[0].mulDiv(10, 8); // to match initial pool balance in this test setup
        uint256 expectedMintAmount = routerUtil.previewAddLiquiditySNG(address(curvePool), amounts);
        uint256[] memory amountsEnd = routerUtil.previewRemoveLiquiditySNG(
            address(curvePool),
            expectedMintAmount
        );
        assertApproxEqRel(amounts[0], amountsEnd[0], ERROR_MARGIN);
        assertApproxEqRel(amounts[1], amountsEnd[1], ERROR_MARGIN);
    }

    function testPreviewAddAndRemoveLiquidityOneCoin0Fuzz(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 amount
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(underlying_decimals, ibt_decimals, address(factory), curvePoolParams);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = bound(amount, IBT_UNIT, curvePool.balances(0) / 10);
        amounts[1] = 0;
        uint256 expectedMintAmount = routerUtil.previewAddLiquiditySNG(address(curvePool), amounts);
        uint256 amountEnd0 = routerUtil.previewRemoveLiquidityOneCoinSNG(
            address(curvePool),
            expectedMintAmount,
            0
        );
        assertApproxEqRel(amounts[0], amountEnd0, 5e15);
    }

    function testPreviewAddAndRemoveLiquidityOneCoin1Fuzz(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 amount
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(underlying_decimals, ibt_decimals, address(factory), curvePoolParams);
        uint256[] memory amounts = new uint256[](2);
        amounts[1] = bound(amount, IBT_UNIT, curvePool.balances(1) / 10);
        amounts[0] = 0;
        uint256 expectedMintAmount = routerUtil.previewAddLiquiditySNG(address(curvePool), amounts);
        uint256 amountEnd1 = routerUtil.previewRemoveLiquidityOneCoinSNG(
            address(curvePool),
            expectedMintAmount,
            1
        );
        assertApproxEqRel(amounts[1], amountEnd1, 5e15);
    }

    //############################################### Internal methods used for testing #######################################################

    /**
     * @param i index of token injected to the pool
     * @param j index of token taken out of the pool
     * @param amountIn amount of token of index i sent into the Curve Pool
     * @return The amount lost due to price impact and fees compared to theoretical marginal price
     */

    function _getCurvePriceImpactLossAndFees(
        int128 i,
        int128 j,
        uint256 amountIn
    ) internal view returns (uint256) {
        return
            amountIn.mulDiv(
                routerUtil.spotExchangeRateSNG(address(curvePool), i, j),
                CurvePoolUtil.CURVE_UNIT
            ) - curvePool.get_dy(i, j, amountIn);
    }
}
