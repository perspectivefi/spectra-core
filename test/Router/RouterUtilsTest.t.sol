// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "openzeppelin-math/Math.sol";
import "src/libraries/CurvePoolUtil.sol";
import "../../src/libraries/Roles.sol";
import {RouterBaseTest} from "./RouterBaseTest.t.sol";
import {Commands} from "src/router/Commands.sol";
import {Constants} from "src/router/Constants.sol";
import {ICurvePool} from "src/interfaces/ICurvePool.sol";

contract ContractRouterUtilTest is RouterBaseTest {
    using Math for uint256;

    uint256 public constant ERROR_MARGIN = 1e6;
    uint256 public constant BALANCE_TRADING_FACTOR_PT_IBT = 10;
    uint256 public constant BALANCE_TRADING_FACTOR_IBT_YT = 100;

    function testSpotExchangeRateValidity() public {
        // We verify that the function works correctly using that 1 IBT is worth more than 1 PT
        uint256 ibtInPT = routerUtil.spotExchangeRate(address(curvePool), 0, 1);
        assertTrue(ibtInPT >= CurvePoolUtil.CURVE_UNIT);

        uint256 ptInIBT = routerUtil.spotExchangeRate(address(curvePool), 1, 0);
        assertTrue(ptInIBT <= CurvePoolUtil.CURVE_UNIT);
    }

    // ############################################### getDx tests #######################################################

    function testGetDxPTToIBTFuzz(uint256 amountOfIBTOut) public {
        amountOfIBTOut = bound(amountOfIBTOut, 1 ether, curvePool.balances(1) / 10);
        uint256 amountOfPTIn = CurvePoolUtil.getDx(address(curvePool), 1, 0, amountOfIBTOut);

        uint256 predictedAmountOfIBTOut = curvePool.get_dy(1, 0, amountOfPTIn);

        assertApproxEqRel(amountOfIBTOut, predictedAmountOfIBTOut, ERROR_MARGIN);
    }

    function testGetDxIBTToPTFuzz(uint256 amountOfPTOut) public {
        amountOfPTOut = bound(amountOfPTOut, 1 ether, curvePool.balances(0) / 10);
        uint256 amountOfIBTIn = CurvePoolUtil.getDx(address(curvePool), 0, 1, amountOfPTOut);
        uint256 predictedAmountOfPTOut = curvePool.get_dy(0, 1, amountOfIBTIn);

        assertApproxEqRel(amountOfPTOut, predictedAmountOfPTOut, ERROR_MARGIN);
    }

    //############################################### Preview Flash Swap Tests #######################################################

    function testIBTToExactYTFlashSwapFuzz(uint256 ytWanted) public {
        ytWanted = bound(ytWanted, 1 ether, curvePool.balances(1) / 100);
        uint256 ytUnit = routerUtil.getUnit(address(yt));
        uint256 ytIBTSpot = routerUtil.convertIBTToYTSpot(1 ether, address(curvePool));
        uint256 minAmountOfIBT = ytWanted.mulDiv(ytUnit, ytIBTSpot);

        (uint256 amountIBTNeeded, ) = routerUtil.previewFlashSwapIBTToExactYT(
            address(curvePool),
            ytWanted
        );

        // price impact + swap fees
        uint256 priceImpactPaid = _getCurvePriceImpactLossAndFees(1, 0, ytWanted);

        assertApproxEqAbs(minAmountOfIBT + priceImpactPaid, amountIBTNeeded, 10);
    }

    function testExactYTToIBTFlashSwapFuzz(uint256 inputYTAmount) public {
        inputYTAmount = bound(inputYTAmount, 1 ether, curvePool.balances(0) / 100);

        uint256 ytIBTSpot = routerUtil.convertIBTToYTSpot(1 ether, address(curvePool));
        uint256 ytUnit = routerUtil.getUnit(address(yt));
        uint256 maxIBTReceived = inputYTAmount.mulDiv(ytUnit, ytIBTSpot);

        (uint256 ibtReceived, uint256 borrowedIBTAmount) = routerUtil.previewFlashSwapExactYTToIBT(
            address(curvePool),
            inputYTAmount
        );

        // We need to swap borrowedIBTAmount of IBT to PT. We calculate the price impact and
        // the fees associated to this swap. This amount is in PT, hence we convert using the marginal
        // price of PT/IBT in order to quote the amount in IBT
        uint256 priceImpactAndFees = _getCurvePriceImpactLossAndFees(0, 1, borrowedIBTAmount)
            .mulDiv(
                routerUtil.spotExchangeRate(address(curvePool), 1, 0),
                CurvePoolUtil.CURVE_UNIT
            );

        assertApproxEqRel(maxIBTReceived, ibtReceived + priceImpactAndFees, 10 * ERROR_MARGIN);
    }

    function testSecantMethodPrecisionFuzz(uint256 inputIBTAmount) public {
        inputIBTAmount = bound(inputIBTAmount, 1 ether, curvePool.balances(1) / 10);
        (uint256 outputYTAmount, ) = routerUtil.previewFlashSwapExactIBTToYT(
            address(curvePool),
            inputIBTAmount
        );

        (uint256 inputIBTAmountRequired, ) = routerUtil.previewFlashSwapIBTToExactYT(
            address(curvePool),
            outputYTAmount
        );

        assertApproxEqRel(inputIBTAmount, inputIBTAmountRequired, 1e15);
    }

    function testFlashSwapCycleFuzz(uint256 inputIBTAmount) public {
        inputIBTAmount = bound(inputIBTAmount, 1 ether, curvePool.balances(1) / 100);

        (uint256 outputYTAmount, ) = routerUtil.previewFlashSwapExactIBTToYT(
            address(curvePool),
            inputIBTAmount
        );

        // We swap IBT for PT. We are left with outputYTAmount PT, that we swap back for IBT. We evalute the loss
        // associated to this swap
        uint256 priceImpactAndFees1 = _getCurvePriceImpactLossAndFees(1, 0, outputYTAmount);

        (uint256 outputIBTAmount, uint256 borrowedIBTAmount2) = routerUtil
            .previewFlashSwapExactYTToIBT(address(curvePool), outputYTAmount);

        // We need to swap borrowedIBTAmount2 of IBT to PT. We calculate the price impact and
        // the fees associated to this swap. This amount is in PT, hence we convert using the marginal
        // price of PT/IBT in order to quote the amount in IBT
        uint256 priceImpactAndFees2 = _getCurvePriceImpactLossAndFees(0, 1, borrowedIBTAmount2)
            .mulDiv(
                routerUtil.spotExchangeRate(address(curvePool), 1, 0),
                CurvePoolUtil.CURVE_UNIT
            );

        assertApproxEqRel(
            inputIBTAmount,
            outputIBTAmount + priceImpactAndFees2 + priceImpactAndFees1,
            1e15
        );
    }

    //############################################### Preview Curve Liquidity Tests #######################################################

    function testPreviewAddWithAssetAndRemoveLiquidityFuzz(uint256 amount) public {
        uint256 amountStart = bound(amount, 1e6, 1_000_000 * 1e18);
        uint256 expectedMintAmount = routerUtil.previewAddLiquidityWithAsset(
            address(curvePool),
            amountStart
        );
        uint256 amountEnd = routerUtil.previewRemoveLiquidityForAsset(
            address(curvePool),
            expectedMintAmount
        );
        assertApproxEqRel(amountStart, amountEnd, 1e14);
    }

    function testPreviewAddWithIBTAndRemoveLiquidityFuzz(uint256 amount) public {
        uint256 amountStart = bound(amount, 1e6, 1_000_000 * 1e18);
        uint256 expectedMintAmount = routerUtil.previewAddLiquidityWithIBT(
            address(curvePool),
            amountStart
        );
        uint256 amountEnd = routerUtil.previewRemoveLiquidityForIBT(
            address(curvePool),
            expectedMintAmount
        );
        assertApproxEqRel(amountStart, amountEnd, 1e14);
    }

    function testPreviewAddAndRemoveLiquidityFuzz(uint256 amount) public {
        uint256 amountStart0 = bound(amount, 1e6, 1_000_000 * 1e18);
        uint256 amountStart1 = amountStart0.mulDiv(10, 8); // to match initial pool balance in this test setup
        uint256 expectedMintAmount = routerUtil.previewAddLiquidity(
            address(curvePool),
            [amountStart0, amountStart1]
        );
        uint256[2] memory amountsEnd = routerUtil.previewRemoveLiquidity(
            address(curvePool),
            expectedMintAmount
        );
        assertApproxEqRel(amountStart0, amountsEnd[0], 1e14);
        assertApproxEqRel(amountStart1, amountsEnd[1], 1e14);
    }

    function testPreviewAddAndRemoveLiquidityOneCoin0Fuzz(uint256 amount) public {
        uint256 amountStart0 = bound(amount, 1e6, 500_000 * 1e18);
        uint256 expectedMintAmount = routerUtil.previewAddLiquidity(
            address(curvePool),
            [amountStart0, 0]
        );
        uint256 amountEnd0 = routerUtil.previewRemoveLiquidityOneCoin(
            address(curvePool),
            expectedMintAmount,
            0
        );
        assertApproxEqRel(amountStart0, amountEnd0, 5e15);
    }

    function testPreviewAddAndRemoveLiquidityOneCoin1Fuzz(uint256 amount) public {
        uint256 amountStart1 = bound(amount, 1e6, 500_000 * 1e18);
        uint256 expectedMintAmount = routerUtil.previewAddLiquidity(
            address(curvePool),
            [0, amountStart1]
        );
        uint256 amountEnd1 = routerUtil.previewRemoveLiquidityOneCoin(
            address(curvePool),
            expectedMintAmount,
            1
        );
        assertApproxEqRel(amountStart1, amountEnd1, 5e15);
    }

    //############################################### Internal methods used for testing #######################################################

    /**
     * @param i index of token injected to the pool
     * @param j index of token taken out of the pool
     * @param amountIn amount of token of index i sent into the Curve Pool
     * @return The amount lost due to price impact and fees compared to theoretical marginal price
     */

    function _getCurvePriceImpactLossAndFees(
        uint256 i,
        uint256 j,
        uint256 amountIn
    ) internal view returns (uint256) {
        return
            amountIn.mulDiv(
                routerUtil.spotExchangeRate(address(curvePool), i, j),
                CurvePoolUtil.CURVE_UNIT
            ) - curvePool.get_dy(i, j, amountIn);
    }
}
