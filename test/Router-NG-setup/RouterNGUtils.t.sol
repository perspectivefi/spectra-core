// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "openzeppelin-math/Math.sol";
import "../../src/libraries/Roles.sol";
import "../../src/libraries/CurvePoolUtil.sol";
import {RouterNGBaseTest} from "./RouterNGBase.t.sol";
import {Commands} from "src/router/Commands.sol";
import {Constants} from "src/router/Constants.sol";
import {ICurveNGPool} from "src/interfaces/ICurveNGPool.sol";

contract ContractRouterNGUtilTest is RouterNGBaseTest {
    using Math for uint256;

    uint256 public constant ERROR_MARGIN = 1e9;
    uint256 public constant BALANCE_TRADING_FACTOR_PT_IBT = 10;
    uint256 public constant BALANCE_TRADING_FACTOR_IBT_YT = 100;
    uint256 public constant NOISE_FEE = 1e13;

    function testSpotExchangeRateValidity() public {
        // We verify that the function works correctly using that 1 IBT is worth more than 1 PT

        uint256 ibtInPT = routerUtil.spotExchangeRate(address(curvePool), 0, 1);
        assertTrue(ibtInPT >= CurvePoolUtil.CURVE_UNIT);

        uint256 ptInIBT = routerUtil.spotExchangeRate(address(curvePool), 1, 0);
        assertTrue(ptInIBT <= CurvePoolUtil.CURVE_UNIT);
    }

    // ############################################### get_dx tests #######################################################

    function testGetDxPTToIBTFuzz(uint256 amountOfIBTOut) public {
        amountOfIBTOut = bound(amountOfIBTOut, 10 ** 15, curvePool.balances(1) / 10);

        uint256 amountOfPTIn = curvePool.get_dx(1, 0, amountOfIBTOut);
        uint256 predictedAmountOfIBTOut = curvePool.get_dy(1, 0, amountOfPTIn);

        assertApproxEqRel(amountOfIBTOut, predictedAmountOfIBTOut, ERROR_MARGIN);
    }

    function testGetDxIBTToPTFuzz(uint256 amountOfPTOut) public {
        amountOfPTOut = bound(amountOfPTOut, 10 ** 15, curvePool.balances(0) / 10);

        uint256 amountOfIBTIn = curvePool.get_dx(0, 1, amountOfPTOut);
        uint256 predictedAmountOfPTOut = curvePool.get_dy(0, 1, amountOfIBTIn);

        assertApproxEqRel(amountOfPTOut, predictedAmountOfPTOut, ERROR_MARGIN);
    }

    //############################################### Preview Flash Swap Tests #######################################################

    function testIBTToExactYTFlashSwapFuzz(uint256 ytWanted) public {
        ytWanted = bound(ytWanted, 1 ether, curvePool.balances(1) / 100);
        uint256 ytUnit = routerUtil.getUnit(address(yt));
        uint256 ytIBTSpot = routerUtil.convertIBTToYTSpot(1 ether, address(curvePool));
        uint256 minAmountOfIBT = ytWanted.mulDiv(ytUnit, ytIBTSpot);

        (uint256 amountIBTNeeded, ) = routerUtil.previewNGFlashSwapIBTToExactYT(
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

        (uint256 ibtReceived, uint256 borrowedIBTAmount) = routerUtil
            .previewNGFlashSwapExactYTToIBT(address(curvePool), inputYTAmount);

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
        inputIBTAmount = bound(inputIBTAmount, 1 ether, curvePool.balances(1) / 1000);
        (uint256 outputYTAmount, ) = routerUtil.previewNGFlashSwapExactIBTToYT(
            address(curvePool),
            inputIBTAmount
        );

        (uint256 inputIBTAmountRequired, ) = routerUtil.previewNGFlashSwapIBTToExactYT(
            address(curvePool),
            outputYTAmount
        );

        assertApproxEqRel(inputIBTAmount, inputIBTAmountRequired, 1e15);
    }

    //############################################### Preview Curve Liquidity Tests #######################################################

    function testPreviewAddWithAssetAndRemoveLiquidityFuzz(uint256 amount) public {
        uint256 amountStart = bound(amount, 1e6, 1_000_000 * 1e18);
        uint256 expectedMintAmount = routerUtil.previewNGAddLiquidityWithAsset(
            address(curvePool),
            amountStart
        );
        uint256 amountEnd = routerUtil.previewNGRemoveLiquidityForAsset(
            address(curvePool),
            expectedMintAmount
        );
        assertApproxEqRel(amountStart, amountEnd, 1e14);
    }

    function testPreviewAddWithIBTAndRemoveLiquidityFuzz(uint256 amount) public {
        uint256 amountStart = bound(amount, 1e14, 1_000_000 * 1e18);
        uint256 expectedMintAmount = routerUtil.previewNGAddLiquidityWithIBT(
            address(curvePool),
            amountStart
        );
        uint256 amountEnd = routerUtil.previewNGRemoveLiquidityForIBT(
            address(curvePool),
            expectedMintAmount
        );
        assertApproxEqRel(amountStart, amountEnd, 1e14);
    }

    function testPreviewAddAndRemoveLiquidityFuzz(uint256 amount) public {
        uint256 amountStart0 = bound(amount, 1e6, 1_000_000 * 1e18);
        uint256 amountStart1 = amountStart0.mulDiv(10, 8); // to match initial pool balance in this test setup
        uint256 expectedMintAmount = routerUtil.previewNGAddLiquidity(
            address(curvePool),
            [amountStart0, amountStart1]
        );
        uint256[2] memory amountsEnd = routerUtil.previewNGRemoveLiquidity(
            address(curvePool),
            expectedMintAmount
        );
        assertApproxEqRel(amountStart0, amountsEnd[0], 1e14);
        assertApproxEqRel(amountStart1, amountsEnd[1], 1e14);
    }

    function testPreviewAddAndRemoveLiquidityOneCoin0Fuzz(uint256 amount) public {
        uint256 amountStart0 = bound(amount, 1e14, curvePool.balances(0) / 10);
        uint256 expectedMintAmount = routerUtil.previewNGAddLiquidity(
            address(curvePool),
            [amountStart0, 0]
        );
        uint256 amountEnd0 = routerUtil.previewNGRemoveLiquidityOneCoin(
            address(curvePool),
            expectedMintAmount,
            0
        );

        uint256 fee = _calcNoiseFee(amountEnd0);
        assertGe(amountStart0, amountEnd0, "More LP tokens than before");
        assertApproxEqRel(amountStart0, amountEnd0 + fee, 1e16);
    }

    function testPreviewAddAndRemoveLiquidityOneCoin1Fuzz(uint256 amount) public {
        uint256 amountStart1 = bound(amount, 1e14, curvePool.balances(1) / 10);
        uint256 expectedMintAmount = routerUtil.previewNGAddLiquidity(
            address(curvePool),
            [0, amountStart1]
        );
        uint256 amountEnd1 = routerUtil.previewNGRemoveLiquidityOneCoin(
            address(curvePool),
            expectedMintAmount,
            1
        );
        assertApproxEqRel(amountStart1, amountEnd1, 1e16);
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

    function _calcNoiseFee(uint256 amount) internal pure returns (uint256) {
        return amount.mulDiv(NOISE_FEE, Constants.UNIT) + 1;
    }
}
