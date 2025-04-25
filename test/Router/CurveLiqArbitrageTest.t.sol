// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "openzeppelin-math/Math.sol";
import "./RouterBaseTest.t.sol";
import {ICurvePool} from "src/interfaces/ICurvePool.sol";

contract ContractCurveLiqArbitrageTest is RouterBaseTest {
    using Math for uint256;

    struct TestData {
        uint256 baseProportion1;
        uint256 baseProportion2;
        uint256 baseProportion3;
        uint256 lptReceived1;
        uint256 lptReceived12;
        uint256 lptReceived13;
        uint256 lptReceived2;
        uint256 lptReceived3;
        uint256 lptReceived4;
        uint256 ibtReceived;
        uint256 ptReceived;
        uint256 lpAmount1;
        uint256 lpAmount2;
        uint256 lpAmount3;
    }

    uint256 CURVE_UNIT = 1e18;

    function testPreviewUnitaryAddLiquidityFuzz(uint256 ibtAmount) public {
        TestData memory data;
        ibtAmount = bound(ibtAmount, 1e8, 1_000_000_000_000e18);
        data.baseProportion1 = ICurvePool(curvePoolAddr).balances(0).mulDiv(
            CURVE_UNIT,
            ICurvePool(curvePoolAddr).balances(1)
        );
        assertApproxEqRel(data.baseProportion1, 0.8e18, 1e15, "base proportion is wrong");
        // adding in different amount should not result in different result
        data.lptReceived1 = curveLiqArbitrage.previewUnitaryAddLiquidity(
            curvePoolAddr,
            ibtAmount,
            data.baseProportion1
        );
        data.lptReceived12 = curveLiqArbitrage.previewUnitaryAddLiquidity(
            curvePoolAddr,
            ibtAmount / 10,
            data.baseProportion1
        );
        data.lptReceived13 = curveLiqArbitrage.previewUnitaryAddLiquidity(
            curvePoolAddr,
            ibtAmount * 10,
            data.baseProportion1
        );
        assertApproxEqRel(
            data.lptReceived1,
            data.lptReceived12,
            1e15,
            "lpts received different when deposit amount differ (division by 10)"
        );
        assertApproxEqRel(
            data.lptReceived1,
            data.lptReceived13,
            1e15,
            "lpts received different when deposit amount differ (multiplication by 10)"
        );
        // adding in similar proportion should give more LP tokens
        data.lptReceived2 = curveLiqArbitrage.previewUnitaryAddLiquidity(
            curvePoolAddr,
            ibtAmount,
            data.baseProportion1 / 2
        );
        data.lptReceived3 = curveLiqArbitrage.previewUnitaryAddLiquidity(
            curvePoolAddr,
            ibtAmount,
            data.baseProportion1 * 2
        );
        assertGt(
            data.lptReceived1,
            data.lptReceived2,
            "more lpts received with worst proportion (proportion divided) 1"
        );
        assertGt(
            data.lptReceived1,
            data.lptReceived3,
            "more lpts received with worst proportion (proportion multiplied) 1"
        );

        // swap a lot of IBTs for PTs
        underlying.mint(testUser, 500_000e18);
        underlying.approve(address(ibt), 500_000e18);
        data.ibtReceived = ibt.deposit(500_000e18, testUser);
        ibt.approve(curvePoolAddr, data.ibtReceived);
        ICurvePool(curvePoolAddr).exchange(0, 1, data.ibtReceived, 0, false, testUser);
        // proportion should now be greater than before
        data.baseProportion2 = ICurvePool(curvePoolAddr).balances(0).mulDiv(
            CURVE_UNIT,
            ICurvePool(curvePoolAddr).balances(1)
        );
        assertGt(
            data.baseProportion2,
            data.baseProportion1,
            "proportion of ibt in pool should have increased"
        );
        // adding in different amount should not result in different result
        data.lptReceived1 = curveLiqArbitrage.previewUnitaryAddLiquidity(
            curvePoolAddr,
            ibtAmount,
            data.baseProportion2
        );
        data.lptReceived12 = curveLiqArbitrage.previewUnitaryAddLiquidity(
            curvePoolAddr,
            ibtAmount / 10,
            data.baseProportion2
        );
        data.lptReceived13 = curveLiqArbitrage.previewUnitaryAddLiquidity(
            curvePoolAddr,
            ibtAmount * 10,
            data.baseProportion2
        );
        assertApproxEqRel(
            data.lptReceived1,
            data.lptReceived12,
            1e15,
            "lpts received different when deposit amount differ (division by 10)"
        );
        assertApproxEqRel(
            data.lptReceived1,
            data.lptReceived13,
            1e15,
            "lpts received different when deposit amount differ (multiplication by 10)"
        );
        // the current proportion and price of the pool are not really correlated, explaining why this time adding liquidity in a lower proportion (closer to price) can be more rewarding
        // this behaviour will be highlighted in the following test
        data.lptReceived2 = curveLiqArbitrage.previewUnitaryAddLiquidity(
            curvePoolAddr,
            ibtAmount,
            data.baseProportion2 / 2
        );
        data.lptReceived3 = curveLiqArbitrage.previewUnitaryAddLiquidity(
            curvePoolAddr,
            ibtAmount,
            data.baseProportion2 * 2
        );
        assertGt(
            data.lptReceived2,
            data.lptReceived1,
            "more lpts received with different proportion (proportion divided) 2"
        );
        assertGt(
            data.lptReceived1,
            data.lptReceived3,
            "more lpts received with worst proportion (proportion multiplied) 2"
        );

        // swap a lot of PTs for IBTs
        underlying.mint(testUser, 500_000e18);
        underlying.approve(address(principalToken), 500_000e18);
        data.ptReceived = principalToken.deposit(500_000e18, testUser);
        principalToken.approve(curvePoolAddr, data.ptReceived);
        ICurvePool(curvePoolAddr).exchange(1, 0, data.ptReceived, 0, false, testUser);
        // proportion should now be greater than before
        data.baseProportion3 = ICurvePool(curvePoolAddr).balances(0).mulDiv(
            CURVE_UNIT,
            ICurvePool(curvePoolAddr).balances(1)
        );
        assertGt(
            data.baseProportion2,
            data.baseProportion3,
            "proportion of ibt in pool should have decreased"
        );
        // adding in different amount should not result in different result
        data.lptReceived1 = curveLiqArbitrage.previewUnitaryAddLiquidity(
            curvePoolAddr,
            ibtAmount,
            data.baseProportion3
        );
        data.lptReceived12 = curveLiqArbitrage.previewUnitaryAddLiquidity(
            curvePoolAddr,
            ibtAmount / 10,
            data.baseProportion3
        );
        data.lptReceived13 = curveLiqArbitrage.previewUnitaryAddLiquidity(
            curvePoolAddr,
            ibtAmount * 10,
            data.baseProportion3
        );
        assertApproxEqRel(
            data.lptReceived1,
            data.lptReceived12,
            1e15,
            "lpts received different when deposit amount differ (division by 10)"
        );
        assertApproxEqRel(
            data.lptReceived1,
            data.lptReceived13,
            1e15,
            "lpts received different when deposit amount differ (multiplication by 10)"
        );
        // the current proportion and price of the pool are not really correlated, explaining why this time adding liquidity in a lower proportion (closer to price) can be more rewarding
        // this behaviour will be highlighted in the following test
        data.lptReceived2 = curveLiqArbitrage.previewUnitaryAddLiquidity(
            curvePoolAddr,
            ibtAmount,
            data.baseProportion3 / 2
        );
        data.lptReceived3 = curveLiqArbitrage.previewUnitaryAddLiquidity(
            curvePoolAddr,
            ibtAmount,
            data.baseProportion3 * 2
        );
        assertGt(
            data.lptReceived1,
            data.lptReceived3,
            "more lpts received with worst proportion (proportion multiplied) 3"
        );
    }

    function testFindBestProportionOptimalFuzz(
        uint256 ibtAmount,
        uint256 epsilon,
        uint256 randomProp
    ) public {
        ibtAmount = bound(ibtAmount, 1e8, 1e26);
        epsilon = bound(epsilon, 1e3, 1e4);
        randomProp = bound(randomProp, 1e17, 2e18); // bounding using most coherent proportions

        uint256 bestProp = curveLiqArbitrage.findBestProportion(curvePoolAddr, ibtAmount, epsilon);

        // compare the rate of lp tokens obtained through adding liquidity in same amounts as in pool
        // first check tokenization fees are null
        vm.prank(scriptAdmin);
        registry.setTokenizationFee(0);
        assertEq(registry.getTokenizationFee(), 0, "fees were not reset properly to 0");

        uint256 tradePropRate = routerUtil.previewAddLiquidityWithIBT(curvePoolAddr, IBT_UNIT);

        uint256 bestPropRate = curveLiqArbitrage.previewUnitaryAddLiquidity(
            curvePoolAddr,
            ibtAmount,
            bestProp
        );
        assertGt(bestPropRate, tradePropRate, "trade prop rate better than best");
        // check if our method finds a similar tradePropRate
        uint256 expectedPropRate = curveLiqArbitrage.previewUnitaryAddLiquidity(
            curvePoolAddr,
            ibtAmount,
            0.8e18
        );
        assertGe(
            bestPropRate,
            tradePropRate,
            "Trade proportion rate is better than the best prop rate"
        );
        assertApproxEqRel(
            bestPropRate,
            expectedPropRate,
            1e15,
            "Best proportion rate is wrong not best"
        );

        // compare against random proportion (with coherent bounds)
        uint256 randomPropRate = curveLiqArbitrage.previewUnitaryAddLiquidity(
            curvePoolAddr,
            ibtAmount,
            randomProp
        );
        assertGe(
            bestPropRate,
            randomPropRate - (1e15 * randomPropRate) / 1e18,
            "random prop rate better than best"
        );
    }

    function testFindBestProportionFuzz(
        uint256 ibtAmount,
        uint256 epsilon,
        uint256 swapAmount
    ) public {
        // check if only first deposit of liquidity is affected by failing proportion finding
        // adding a second liquidity addition - can be removed later
        // add initial liquidity to curve pool according to initial price
        underlying.mint(testUser, 18e18);
        underlying.approve(address(ibt), 8e18);
        uint256 amountIBT2 = ibt.deposit(8e18, testUser);
        underlying.approve(address(principalToken), 10e18);
        uint256 amountPT2 = principalToken.deposit(10e18, testUser);
        ibt.approve(curvePoolAddr, amountIBT2);
        principalToken.approve(curvePoolAddr, amountPT2);
        (bool success, ) = curvePoolAddr.call(
            abi.encodeWithSelector(0x0b4c7e4d, [amountIBT2, amountPT2], 0)
        );
        if (!success) {
            revert FailedToAddInitialLiquidity();
        }
        // end of second liq addition
        TestData memory data;
        ibtAmount = bound(ibtAmount, 1e8, 1e30); // note test passing with lower bound == 1e8 (Curve limits)
        epsilon = bound(epsilon, 1e2, 1e3);

        data.baseProportion1 = curveLiqArbitrage.findBestProportion(
            curvePoolAddr,
            ibtAmount,
            epsilon
        );
        // compare this best proportion rate against the expected one
        uint256 basePropRate = curveLiqArbitrage.previewUnitaryAddLiquidity(
            curvePoolAddr,
            ibtAmount,
            data.baseProportion1
        );
        uint256 expectedPropRate = curveLiqArbitrage.previewUnitaryAddLiquidity(
            curvePoolAddr,
            ibtAmount,
            0.8e18
        );

        assertApproxEqRel(data.baseProportion1, 0.8e18, 1e15, "base proportion is wrong");
        assertGe(
            basePropRate,
            expectedPropRate - (1e15 * expectedPropRate) / 1e18,
            "best proportion rate is worst than the expected one"
        );

        uint256 amount1 = IBT_UNIT.mulDiv(
            CURVE_UNIT,
            data.baseProportion1 + ICurvePool(curvePoolAddr).last_prices()
        );
        uint256 amount0 = amount1.mulDiv(data.baseProportion1, CURVE_UNIT);
        data.lpAmount1 = ICurvePool(curvePoolAddr).calc_token_amount([amount0, amount1]);
        uint256 swapAmountPreviewed = bound(ibtAmount, 1e8, amount0);
        data.lpAmount2 = ICurvePool(curvePoolAddr).calc_token_amount(
            [
                amount0 - swapAmountPreviewed,
                amount1 + ICurvePool(curvePoolAddr).get_dy(0, 1, swapAmountPreviewed)
            ]
        );
        swapAmountPreviewed = bound(ibtAmount, 1e8, amount1);
        data.lpAmount3 = ICurvePool(curvePoolAddr).calc_token_amount(
            [
                amount0 + ICurvePool(curvePoolAddr).get_dy(1, 0, swapAmountPreviewed),
                amount1 - swapAmountPreviewed
            ]
        );
        assertGe(
            data.lpAmount1,
            data.lpAmount2.mulDiv(9999, 10000),
            "Best proportion found 1 is sub optimal 1"
        );
        assertGe(
            data.lpAmount1,
            data.lpAmount3.mulDiv(9999, 10000),
            "Best proportion found 1 is sub optimal 2"
        );

        // swap IBTs for PTs
        swapAmount = bound(swapAmount, 1e8, ICurvePool(curvePoolAddr).balances(1) / 2);
        underlying.mint(testUser, swapAmount);
        underlying.approve(address(ibt), swapAmount);
        data.ibtReceived = ibt.deposit(swapAmount, testUser);
        ibt.approve(curvePoolAddr, data.ibtReceived);
        ICurvePool(curvePoolAddr).exchange(0, 1, data.ibtReceived, 0, false, testUser);

        data.baseProportion2 = curveLiqArbitrage.findBestProportion(
            curvePoolAddr,
            ibtAmount,
            epsilon
        );
        amount1 = IBT_UNIT.mulDiv(
            CURVE_UNIT,
            data.baseProportion2 + ICurvePool(curvePoolAddr).last_prices()
        );
        amount0 = amount1.mulDiv(data.baseProportion2, CURVE_UNIT);
        data.lpAmount1 = ICurvePool(curvePoolAddr).calc_token_amount([amount0, amount1]);
        swapAmountPreviewed = bound(ibtAmount, 1e8, amount0);
        data.lpAmount2 = ICurvePool(curvePoolAddr).calc_token_amount(
            [
                amount0 - swapAmountPreviewed,
                amount1 + ICurvePool(curvePoolAddr).get_dy(0, 1, swapAmountPreviewed)
            ]
        );
        swapAmountPreviewed = bound(ibtAmount, 1e8, amount1);
        data.lpAmount3 = ICurvePool(curvePoolAddr).calc_token_amount(
            [
                amount0 + ICurvePool(curvePoolAddr).get_dy(1, 0, swapAmountPreviewed),
                amount1 - swapAmountPreviewed
            ]
        );
        assertGe(
            data.lpAmount1,
            data.lpAmount2.mulDiv(9999, 10000),
            "Best proportion found 2 is sub optimal 1"
        );
        assertGe(
            data.lpAmount1,
            data.lpAmount3.mulDiv(9999, 10000),
            "Best proportion found 2 is sub optimal 2"
        );

        // swap PTs for IBTs
        swapAmount = bound(ibtAmount, 1e8, ICurvePool(curvePoolAddr).balances(0) / 2);
        underlying.mint(testUser, swapAmount);
        underlying.approve(address(principalToken), swapAmount);
        data.ptReceived = principalToken.deposit(swapAmount, testUser);
        principalToken.approve(curvePoolAddr, data.ptReceived);
        ICurvePool(curvePoolAddr).exchange(1, 0, data.ptReceived, 0, false, testUser);

        data.baseProportion3 = curveLiqArbitrage.findBestProportion(
            curvePoolAddr,
            ibtAmount,
            epsilon
        );
        amount1 = IBT_UNIT.mulDiv(
            CURVE_UNIT,
            data.baseProportion3 + ICurvePool(curvePoolAddr).last_prices()
        );
        amount0 = amount1.mulDiv(data.baseProportion3, CURVE_UNIT);
        data.lpAmount1 = ICurvePool(curvePoolAddr).calc_token_amount([amount0, amount1]);
        swapAmountPreviewed = bound(ibtAmount, 1e8, amount0);
        data.lpAmount2 = ICurvePool(curvePoolAddr).calc_token_amount(
            [
                amount0 - swapAmountPreviewed,
                amount1 + ICurvePool(curvePoolAddr).get_dy(0, 1, swapAmountPreviewed)
            ]
        );
        swapAmountPreviewed = bound(ibtAmount, 1e8, amount1);
        data.lpAmount3 = ICurvePool(curvePoolAddr).calc_token_amount(
            [
                amount0 + ICurvePool(curvePoolAddr).get_dy(1, 0, swapAmountPreviewed),
                amount1 - swapAmountPreviewed
            ]
        );
        assertGe(
            data.lpAmount1,
            data.lpAmount2.mulDiv(9999, 10000),
            "Best proportion found 3 is sub optimal 1"
        );
        assertGe(
            data.lpAmount1,
            data.lpAmount3.mulDiv(9999, 10000),
            "Best proportion found 3 is sub optimal 2"
        );
    }
}
