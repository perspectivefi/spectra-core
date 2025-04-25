// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "forge-std/Test.sol";

import "src/libraries/CurvePoolUtil.sol";

import {RouterSNGBaseTest} from "./RouterSNGBaseTest.t.sol";
import {Commands} from "src/router/Commands.sol";
import {Constants} from "src/router/Constants.sol";
import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {IStableSwapNG} from "src/interfaces/IStableSwapNG.sol";

contract ContractRouterLiquidityTest is RouterSNGBaseTest {
    using Math for uint256;

    struct balancesData {
        // data before
        uint256 assetBalOwnerBefore;
        uint256 assetBalReceiverBefore;
        uint256 ibtBalOwnerBefore;
        uint256 ibtBalReceiverBefore;
        uint256 ptBalOwnerBefore;
        uint256 ytBalOwnerBefore;
        uint256 ptBalReceiverBefore;
        uint256 coinBalOwnerBefore;
        uint256 coinBalReceiverBefore;
        uint256 lpBalOwnerBefore;
        uint256 lpBalReceiverBefore;
        uint256 ibtBalCurvePoolBefore;
        uint256 ptBalCurvePoolBefore;
        uint256 coinBalCurvePoolBefore;
        // data after
        uint256 assetBalOwnerAfter;
        uint256 assetBalReceiverAfter;
        uint256 ibtBalOwnerAfter;
        uint256 ibtBalReceiverAfter;
        uint256 ptBalOwnerAfter;
        uint256 ptBalReceiverAfter;
        uint256 coinBalOwnerAfter;
        uint256 coinBalReceiverAfter;
        uint256 lpBalOwnerAfter;
        uint256 lpBalReceiverAfter;
        uint256 ibtBalCurvePoolAfter;
        uint256 ptBalCurvePoolAfter;
        uint256 coinBalCurvePoolAfter;
    }

    uint256 private constant APPROXIMATION_TOLERANCE = 1e15; // 10 bps
    uint256 private constant NOISE_FEE = 1e13;

    address MOCK_ADDR_1 = 0x0000000000000000000000000000000000000001;
    address MOCK_ADDR_2 = 0x0000000000000000000000000000000000000002;
    address MOCK_ADDR_3 = 0x0000000000000000000000000000000000000003;
    address MOCK_ADDR_4 = 0x0000000000000000000000000000000000000004;

    function setUp() public override {
        super.setUp();
    }

    function testAddLiquidityWithAssetFailSNG(
        uint8 underlying_decimals,
        uint8 ibt_decimals
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(
            underlying_decimals,
            ibt_decimals,
            address(curvePool),
            curvePoolParams
        );
        uint256 assets = 100 * UNDERLYING_UNIT;
        underlying.mint(MOCK_ADDR_1, assets);

        vm.startPrank(MOCK_ADDR_1);
        underlying.approve(address(router), assets);
        uint256 minExpectedLpAmount = routerUtil.previewAddLiquidityWithAssetSNG(
            curvePoolAddr,
            assets
        );
        (bytes memory commands, bytes[] memory inputs) = _buildRouterAddLiquidityWithAssetExecution(
            curvePoolAddr,
            assets,
            minExpectedLpAmount + 1, // too high
            MOCK_ADDR_1
        );
        vm.expectRevert();
        router.execute(commands, inputs);
        vm.stopPrank();
    }

    function testAddLiquidityWithIBTFailSNG(uint8 underlying_decimals, uint8 ibt_decimals) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(
            underlying_decimals,
            ibt_decimals,
            address(curvePool),
            curvePoolParams
        );
        uint256 amount = 1000 * UNDERLYING_UNIT;

        underlying.mint(address(this), amount);
        underlying.approve(address(ibt), amount);
        uint256 ibts = ibt.deposit(amount, MOCK_ADDR_1);

        vm.startPrank(MOCK_ADDR_1);
        ibt.approve(address(router), ibts);
        uint256 minExpectedLpAmount = routerUtil.previewAddLiquidityWithAssetSNG(
            curvePoolAddr,
            ibts
        );

        (bytes memory commands, bytes[] memory inputs) = _buildRouterAddLiquidityWithIBTExecution(
            curvePoolAddr,
            ibts,
            minExpectedLpAmount + 1, // too high
            MOCK_ADDR_1
        );
        vm.expectRevert();
        router.execute(commands, inputs);

        vm.stopPrank();
    }

    function testAddAndRemoveLiquidityPreciseSNG() public {
        uint256 amount = 10_000e15;

        underlying.mint(address(this), amount);
        underlying.approve(address(ibt), amount);
        uint256 ibtsTotal = ibt.deposit(amount, MOCK_ADDR_1);

        vm.startPrank(MOCK_ADDR_1);
        ibt.approve(address(principalToken), ibtsTotal / 2);
        principalToken.depositIBT(ibtsTotal / 2, MOCK_ADDR_1);
        vm.stopPrank();

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 80e15;
        amounts[1] = 100e15;

        uint256 lpTokens = _testAddLiquidity(amounts, MOCK_ADDR_1, MOCK_ADDR_2);
        uint256[2] memory coinsEnd = _testRemoveLiquidity(lpTokens, MOCK_ADDR_2, MOCK_ADDR_3);

        if (amounts[0] < 1e15) {
            assertApproxEqAbs(amounts[0], coinsEnd[0], 50);
        } else {
            assertApproxEqRel(amounts[0], coinsEnd[0], 1e8);
        }

        if (amounts[1] < 1e15) {
            assertApproxEqAbs(amounts[1], coinsEnd[1], 50);
        } else {
            assertApproxEqRel(amounts[1], coinsEnd[1], 1e8);
        }
    }

    function testAddAndRemoveLiquidityOneCoin0FuzzSNG(
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

        amount = bound(amount, 10_000, 1000 * UNDERLYING_UNIT);

        underlying.mint(address(this), amount);
        underlying.approve(address(ibt), amount);
        uint256 ibtsStart = ibt.deposit(amount, MOCK_ADDR_1);

        uint256 lpTokens = _testAddLiquidityOneCoin(ibtsStart, 0, MOCK_ADDR_1, MOCK_ADDR_2);

        _testRemoveLiquidityOneCoin(lpTokens, 0, MOCK_ADDR_2, MOCK_ADDR_3);
    }

    function testAddAndRemoveLiquidityOneCoin1FuzzSNG(
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
        amount = bound(amount, 10_000, 1000 * UNDERLYING_UNIT);

        underlying.mint(address(this), amount);
        underlying.approve(address(principalToken), amount);
        uint256 ptsStart = principalToken.deposit(amount, MOCK_ADDR_1);

        uint256 lpTokens = _testAddLiquidityOneCoin(ptsStart, 1, MOCK_ADDR_1, MOCK_ADDR_2);

        _testRemoveLiquidityOneCoin(lpTokens, 1, MOCK_ADDR_2, MOCK_ADDR_3);
    }

    function testAddAndRemoveLiquidityFuzzSNG(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 amount,
        uint256 yieldFactor
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(
            underlying_decimals,
            ibt_decimals,
            address(curvePool),
            curvePoolParams
        );
        amount = bound(amount, 1000, 100_000_000 * UNDERLYING_UNIT);
        yieldFactor = bound(yieldFactor, 0.1e18, 10e18);

        underlying.mint(address(this), amount);
        underlying.approve(address(ibt), amount);
        uint256 ibtsTotal = ibt.deposit(amount, MOCK_ADDR_1);

        _setYield(yieldFactor);

        uint256 ibtsToTokenize = CurvePoolUtil.calcIBTsToTokenizeForCurvePool(
            ibtsTotal,
            address(curvePool),
            address(principalToken)
        );
        uint256 ibtsStart = ibtsTotal - ibtsToTokenize;

        vm.startPrank(MOCK_ADDR_1);
        ibt.approve(address(principalToken), ibtsToTokenize);
        uint256 ptsStart = principalToken.depositIBT(ibtsToTokenize, MOCK_ADDR_1);
        vm.stopPrank();

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = ibtsStart;
        amounts[1] = ptsStart;

        uint256 lpTokens = _testAddLiquidity(amounts, MOCK_ADDR_1, MOCK_ADDR_2);

        uint256[2] memory coinsEnd = _testRemoveLiquidity(lpTokens, MOCK_ADDR_2, MOCK_ADDR_3);

        if (
            stdMath.percentDelta(
                ibtsStart.mulDiv(1e18, coinsEnd[0]),
                ptsStart.mulDiv(1e18, coinsEnd[1])
            ) < 1e5
        ) {
            assertLe(ibtsStart, coinsEnd[0] + 100, "IBT balance after add+remove is wrong");
            assertLe(ptsStart, coinsEnd[1] + 100, "PT balance after add+remove is wrong");
        }

        if (ibtsStart < 1e15) {
            assertApproxEqAbs(ibtsStart, coinsEnd[0], 50, "IBT balance after add+remove is wrong");
        } else {
            assertApproxEqRel(
                ibtsStart,
                coinsEnd[0],
                1e13,
                "IBT balance after add+remove is wrong"
            );
        }

        if (ptsStart < 1e15) {
            assertApproxEqAbs(ptsStart, coinsEnd[1], 50, "PT balance after add+remove is wrong");
        } else {
            assertApproxEqRel(ptsStart, coinsEnd[1], 1e13, "PT balance after add+remove is wrong");
        }
    }

    function testAddAndRemoveLiquidityWithAssetNoYieldFuzzSNG(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 assets
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(
            underlying_decimals,
            ibt_decimals,
            address(curvePool),
            curvePoolParams
        );

        uint256 assetsStart = bound(assets, 1000, 1_000_000 * UNDERLYING_UNIT);

        underlying.mint(MOCK_ADDR_1, assetsStart);

        uint256 lpTokens = _testAddLiquidityWithAsset(assetsStart, MOCK_ADDR_1, MOCK_ADDR_2);
        uint256 assetsEnd = _testRemoveLiquidityForAsset(lpTokens, MOCK_ADDR_2, MOCK_ADDR_3);
        if (assetsStart < 1e15) {
            assertApproxEqAbs(
                assetsStart,
                assetsEnd,
                20,
                "Asset balance after add+remove is wrong"
            );
        } else {
            assertApproxEqRel(
                assetsStart,
                assetsEnd,
                1e13,
                "Asset balance after add+remove is wrong"
            );
        }
    }

    function testAddAndRemoveLiquidityWithAssetVariableRateFuzzSNG(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 assets,
        uint256 yieldFactor
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(
            underlying_decimals,
            ibt_decimals,
            address(curvePool),
            curvePoolParams
        );

        uint256 assetsStart = bound(assets, 1e5, 1_000_000 * UNDERLYING_UNIT);
        yieldFactor = bound(yieldFactor, 0.1e18, 10e18);

        underlying.mint(MOCK_ADDR_1, assetsStart);

        _setYield(yieldFactor);

        uint256 lpTokens = _testAddLiquidityWithAsset(assetsStart, MOCK_ADDR_1, MOCK_ADDR_2);
        uint256 assetsEnd = _testRemoveLiquidityForAsset(lpTokens, MOCK_ADDR_2, MOCK_ADDR_3);
        assertApproxEqRel(assetsStart, assetsEnd, 1e15, "Asset balance after add+remove is wrong");
    }

    function testAddAndRemoveLiquidityWithIBTNoYieldFuzzSNG(
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
        amount = bound(amount, 10000, 1_000_000 * UNDERLYING_UNIT);

        underlying.mint(address(this), amount);
        underlying.approve(address(ibt), amount);
        uint256 ibtsStart = ibt.deposit(amount, MOCK_ADDR_1);

        uint256 lpTokens = _testAddLiquidityWithIBT(ibtsStart, MOCK_ADDR_1, MOCK_ADDR_2);
        uint256 ibtsEnd = _testRemoveLiquidityForIBT(lpTokens, MOCK_ADDR_2, MOCK_ADDR_3);
        assertApproxEqRel(ibtsStart, ibtsEnd, 1e15, "IBT balance after add+remove is wrong");
    }

    function testAddAndRemoveLiquidityWithIBTVariableRateFuzzSNG(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 amount,
        uint256 yieldFactor
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(
            underlying_decimals,
            ibt_decimals,
            address(curvePool),
            curvePoolParams
        );

        amount = bound(amount, 1e5, 1_000_000 * UNDERLYING_UNIT);
        yieldFactor = bound(yieldFactor, 0.1e18, 10e18);

        underlying.mint(address(this), amount);
        underlying.approve(address(ibt), amount);
        uint256 ibtsStart = ibt.deposit(amount, MOCK_ADDR_1);

        _setYield(yieldFactor);

        uint256 lpTokens = _testAddLiquidityWithIBT(ibtsStart, MOCK_ADDR_1, MOCK_ADDR_2);
        uint256 ibtsEnd = _testRemoveLiquidityForIBT(lpTokens, MOCK_ADDR_2, MOCK_ADDR_3);
        assertApproxEqRel(ibtsStart, ibtsEnd, 1e15, "IBT balance after add+remove is wrong");
    }

    function testAddAndRemoveLiquidityMultipleUsersNoYieldFuzzSNG(
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

        amount = bound(amount, 1000, 1_000_000 * UNDERLYING_UNIT);

        underlying.mint(address(this), amount);
        underlying.approve(address(ibt), amount);
        uint256 ibts = ibt.deposit(amount, MOCK_ADDR_1);
        uint256 lpTokens1 = _testAddLiquidityWithIBT(ibts, MOCK_ADDR_1, MOCK_ADDR_1);

        underlying.mint(MOCK_ADDR_2, amount);
        uint256 lpTokens2 = _testAddLiquidityWithAsset(amount, MOCK_ADDR_2, MOCK_ADDR_2);

        underlying.mint(address(this), amount * 3);
        underlying.approve(address(ibt), amount * 3);
        ibts = ibt.deposit(amount * 3, MOCK_ADDR_3);
        uint256 lpTokens3 = _testAddLiquidityWithIBT(ibts, MOCK_ADDR_3, MOCK_ADDR_3);

        underlying.mint(MOCK_ADDR_4, amount * 100);
        uint256 lpTokens4 = _testAddLiquidityWithAsset(amount * 100, MOCK_ADDR_4, MOCK_ADDR_4);

        _testRemoveLiquidityForAsset(lpTokens1, MOCK_ADDR_1, MOCK_ADDR_1);
        _testRemoveLiquidityForIBT(lpTokens2, MOCK_ADDR_2, MOCK_ADDR_2);
        _testRemoveLiquidityForAsset(lpTokens3, MOCK_ADDR_3, MOCK_ADDR_3);
        _testRemoveLiquidityForIBT(lpTokens4, MOCK_ADDR_4, MOCK_ADDR_4);
    }

    function testAddAndRemoveLiquidityMultipleUsersIncreasingYieldFuzzSNG(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 amount,
        uint256 yieldFactor
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(
            underlying_decimals,
            ibt_decimals,
            address(curvePool),
            curvePoolParams
        );

        amount = bound(amount, UNDERLYING_UNIT, 1_000 * UNDERLYING_UNIT);
        yieldFactor = bound(yieldFactor, 1e18, 10e18);

        underlying.mint(address(this), amount);
        underlying.approve(address(ibt), amount);
        uint256 ibts = ibt.deposit(amount, MOCK_ADDR_1);
        _setYield(yieldFactor);
        uint256 lpTokens1 = _testAddLiquidityWithIBT(ibts, MOCK_ADDR_1, MOCK_ADDR_1);

        underlying.mint(MOCK_ADDR_2, amount);
        _setYield(yieldFactor);
        uint256 lpTokens2 = _testAddLiquidityWithAsset(amount, MOCK_ADDR_2, MOCK_ADDR_2);

        underlying.mint(address(this), amount * 3);
        underlying.approve(address(ibt), amount * 3);
        ibts = ibt.deposit(amount * 3, MOCK_ADDR_3);
        _setYield(yieldFactor);
        uint256 lpTokens3 = _testAddLiquidityWithIBT(ibts, MOCK_ADDR_3, MOCK_ADDR_3);

        _testRemoveLiquidityForAsset(lpTokens1, MOCK_ADDR_1, MOCK_ADDR_1);
        _setYield(yieldFactor);
        _testRemoveLiquidityForIBT(lpTokens2, MOCK_ADDR_2, MOCK_ADDR_2);
        _setYield(yieldFactor);
        _testRemoveLiquidityForAsset(lpTokens3, MOCK_ADDR_3, MOCK_ADDR_3);
    }

    function testYieldGenerationDoesNotChangeLPBalanceFuzzSNG(
        uint8 underlying_decimals,
        uint8 ibt_decimals,
        uint256 amount,
        uint256 yieldFactor
    ) public {
        underlying_decimals = uint8(bound(underlying_decimals, MIN_DECIMALS, MAX_DECIMALS));
        ibt_decimals = uint8(bound(ibt_decimals, underlying_decimals, MAX_DECIMALS));
        super.deployProtocol(
            underlying_decimals,
            ibt_decimals,
            address(curvePool),
            curvePoolParams
        );

        amount = bound(amount, UNDERLYING_UNIT / 1000, 100 * UNDERLYING_UNIT);
        yieldFactor = bound(yieldFactor, 0.1e18, 10e18);

        underlying.mint(address(this), amount);
        underlying.approve(address(ibt), amount);
        uint256 ibts = ibt.deposit(amount, MOCK_ADDR_1);

        _testAddLiquidityWithIBT(ibts, MOCK_ADDR_1, MOCK_ADDR_1);

        uint256 lpBalance = IERC20(lpToken).balanceOf(MOCK_ADDR_1);

        for (uint8 i = 0; i < 10; ++i) {
            _setYield(i * 0.25e18);
            assertTrue(
                IERC20(lpToken).balanceOf(MOCK_ADDR_1) == lpBalance,
                "LP balance should not change"
            );
        }
    }

    /* UTIL FUNCTIONS */

    function _testAddLiquidity(
        uint256[] memory amounts,
        address owner,
        address receiver
    ) internal returns (uint256 lpTokens) {
        balancesData memory data;

        data.ibtBalOwnerBefore = ibt.balanceOf(owner);
        data.ptBalOwnerBefore = principalToken.balanceOf(owner);
        data.lpBalReceiverBefore = lpToken.balanceOf(receiver);
        data.ibtBalCurvePoolBefore = ibt.balanceOf(curvePoolAddr);
        data.ptBalCurvePoolBefore = principalToken.balanceOf(curvePoolAddr);
        uint256 poolRatioBefore = _getPoolRatio(curvePoolAddr);

        vm.startPrank(owner);
        ibt.approve(address(router), amounts[0]);
        principalToken.approve(address(router), amounts[1]);
        uint256 minExpectedLpAmount = _getMinExpectedAmountWithTolerance(
            routerUtil.previewAddLiquiditySNG(curvePoolAddr, amounts)
        );
        {
            (bytes memory commands, bytes[] memory inputs) = _buildRouterAddLiquidityExecution(
                curvePoolAddr,
                amounts,
                minExpectedLpAmount,
                receiver
            );
            // owner adds liquidity for receiver
            router.execute(commands, inputs);
        }
        vm.stopPrank();

        data.ibtBalOwnerAfter = ibt.balanceOf(owner);
        data.ptBalOwnerAfter = principalToken.balanceOf(owner);
        data.lpBalReceiverAfter = lpToken.balanceOf(receiver);
        data.ibtBalCurvePoolAfter = ibt.balanceOf(curvePoolAddr);
        data.ptBalCurvePoolAfter = principalToken.balanceOf(curvePoolAddr);
        uint256 poolRatioAfter = _getPoolRatio(curvePoolAddr);

        lpTokens = data.lpBalReceiverAfter - data.lpBalReceiverBefore;

        assertGe(
            lpTokens,
            minExpectedLpAmount,
            "After adding liquidity, LPToken balance of receiver is too low"
        );
        assertEq(
            data.ibtBalOwnerBefore - data.ibtBalOwnerAfter,
            amounts[0],
            "After adding liquidity, IBT balance of sender is wrong"
        );
        assertEq(
            data.ptBalOwnerBefore - data.ptBalOwnerAfter,
            amounts[1],
            "After adding liquidity, PT balance of sender is wrong"
        );
        assertEq(
            data.ibtBalCurvePoolAfter - data.ibtBalCurvePoolBefore,
            amounts[0],
            "After adding liquidity, IBT balance of curvePool should have increased"
        );
        assertEq(
            data.ptBalCurvePoolAfter - data.ptBalCurvePoolBefore,
            amounts[1],
            "After adding liquidity, PT balance of curvePool should have increased"
        );
        assertApproxEqRel(
            poolRatioBefore,
            poolRatioAfter,
            1e10,
            "After adding liquidity, pool ratio should not have changed"
        );
    }

    function _testAddLiquidityWithAsset(
        uint256 assets,
        address owner,
        address receiver
    ) internal returns (uint256 lpTokens) {
        balancesData memory data;

        data.assetBalOwnerBefore = underlying.balanceOf(owner);
        data.lpBalReceiverBefore = lpToken.balanceOf(receiver);
        data.ibtBalCurvePoolBefore = ibt.balanceOf(curvePoolAddr);
        data.ptBalCurvePoolBefore = principalToken.balanceOf(curvePoolAddr);
        uint256 poolRatioBefore = _getPoolRatio(curvePoolAddr);

        vm.startPrank(owner);
        underlying.approve(address(router), assets);
        uint256 minExpectedLpAmount = _getMinExpectedAmountWithTolerance(
            routerUtil.previewAddLiquidityWithAssetSNG(curvePoolAddr, assets)
        );
        {
            (
                bytes memory commands,
                bytes[] memory inputs
            ) = _buildRouterAddLiquidityWithAssetExecution(
                    curvePoolAddr,
                    assets,
                    minExpectedLpAmount,
                    receiver
                );
            // owner adds liquidity for receiver
            router.execute(commands, inputs);
        }
        vm.stopPrank();

        data.assetBalOwnerAfter = underlying.balanceOf(owner);
        data.lpBalReceiverAfter = lpToken.balanceOf(receiver);
        data.ibtBalCurvePoolAfter = ibt.balanceOf(curvePoolAddr);
        data.ptBalCurvePoolAfter = principalToken.balanceOf(curvePoolAddr);
        uint256 poolRatioAfter = _getPoolRatio(curvePoolAddr);

        lpTokens = data.lpBalReceiverAfter - data.lpBalReceiverBefore;

        assertGe(
            lpTokens,
            minExpectedLpAmount,
            "After adding liquidity, LPToken balance of receiver is too low"
        );
        assertEq(
            data.assetBalOwnerBefore - data.assetBalOwnerAfter,
            assets,
            "After adding liquidity, asset balance of sender is wrong"
        );
        assertGe(
            data.ibtBalCurvePoolAfter,
            data.ibtBalCurvePoolBefore,
            "After adding liquidity, IBT balance of curvePool should have increased"
        );
        assertGe(
            data.ptBalCurvePoolAfter,
            data.ptBalCurvePoolBefore,
            "After adding liquidity, PT balance of curvePool should have increased"
        );
        assertApproxEqRel(
            poolRatioBefore,
            poolRatioAfter,
            1e10,
            "After adding liquidity, pool ratio should not have changed"
        );
    }

    function _testAddLiquidityWithIBT(
        uint256 ibts,
        address owner,
        address receiver
    ) internal returns (uint256 lpTokens) {
        balancesData memory data;

        data.ibtBalOwnerBefore = ibt.balanceOf(owner);
        data.lpBalReceiverBefore = lpToken.balanceOf(receiver);
        data.ibtBalCurvePoolBefore = ibt.balanceOf(curvePoolAddr);
        data.ptBalCurvePoolBefore = principalToken.balanceOf(curvePoolAddr);
        uint256 poolRatioBefore = _getPoolRatio(curvePoolAddr);

        vm.startPrank(owner);
        ibt.approve(address(router), ibts);
        uint256 minExpectedLpAmount = _getMinExpectedAmountWithTolerance(
            routerUtil.previewAddLiquidityWithIBTSNG(curvePoolAddr, ibts)
        );
        {
            (
                bytes memory commands,
                bytes[] memory inputs
            ) = _buildRouterAddLiquidityWithIBTExecution(
                    curvePoolAddr,
                    ibts,
                    minExpectedLpAmount,
                    receiver
                );
            // owner adds liquidity for receiver
            router.execute(commands, inputs);
        }
        vm.stopPrank();

        data.ibtBalOwnerAfter = ibt.balanceOf(owner);
        data.lpBalReceiverAfter = lpToken.balanceOf(receiver);
        data.ibtBalCurvePoolAfter = ibt.balanceOf(curvePoolAddr);
        data.ptBalCurvePoolAfter = principalToken.balanceOf(curvePoolAddr);
        uint256 poolRatioAfter = _getPoolRatio(curvePoolAddr);

        lpTokens = data.lpBalReceiverAfter - data.lpBalReceiverBefore;

        assertGe(
            lpTokens,
            minExpectedLpAmount,
            "After adding liquidity, LPToken balance of receiver is too low"
        );
        assertEq(
            data.ibtBalOwnerBefore - data.ibtBalOwnerAfter,
            ibts,
            "After adding liquidity, IBT balance of sender is wrong"
        );
        assertGt(
            data.ibtBalCurvePoolAfter,
            data.ibtBalCurvePoolBefore,
            "After adding liquidity, IBT balance of curvePool should have increased"
        );
        assertGt(
            data.ptBalCurvePoolAfter,
            data.ptBalCurvePoolBefore,
            "After adding liquidity, PT balance of curvePool should have increased"
        );
        assertApproxEqRel(
            poolRatioBefore,
            poolRatioAfter,
            1e10,
            "After adding liquidity, pool ratio should not have changed"
        );
    }

    function _testAddLiquidityOneCoin(
        uint256 amount,
        uint256 i,
        address owner,
        address receiver
    ) internal returns (uint256 lpTokens) {
        balancesData memory data;

        IERC20 coin = IERC20(ICurvePool(curvePoolAddr).coins(i));

        data.coinBalOwnerBefore = coin.balanceOf(owner);
        data.lpBalReceiverBefore = lpToken.balanceOf(receiver);
        data.coinBalCurvePoolBefore = coin.balanceOf(curvePoolAddr);
        uint256 poolRatioBefore = _getPoolRatio(curvePoolAddr);

        uint256[] memory amounts = new uint256[](2);
        amounts[i] = amount;
        amounts[1 - i] = 0;

        vm.startPrank(owner);
        coin.approve(address(router), amount);
        uint256 minExpectedLpAmount = _getMinExpectedAmountWithTolerance(
            routerUtil.previewAddLiquiditySNG(curvePoolAddr, amounts)
        );
        {
            (bytes memory commands, bytes[] memory inputs) = _buildRouterAddLiquidityExecution(
                curvePoolAddr,
                amounts,
                minExpectedLpAmount,
                receiver
            );
            // owner adds liquidity for receiver
            router.execute(commands, inputs);
        }
        vm.stopPrank();

        data.coinBalOwnerAfter = coin.balanceOf(owner);
        data.lpBalReceiverAfter = lpToken.balanceOf(receiver);
        data.coinBalCurvePoolAfter = coin.balanceOf(curvePoolAddr);
        uint256 poolRatioAfter = _getPoolRatio(curvePoolAddr);

        lpTokens = data.lpBalReceiverAfter - data.lpBalReceiverBefore;

        assertGe(
            lpTokens,
            minExpectedLpAmount,
            "After adding liquidity, LPToken balance of receiver is too low"
        );
        assertEq(
            data.coinBalOwnerBefore - data.coinBalOwnerAfter,
            amounts[i],
            "After adding liquidity (one coin), coin balance of sender is wrong"
        );
        assertEq(
            data.coinBalCurvePoolAfter - data.coinBalCurvePoolBefore,
            amounts[i],
            "After adding liquidity (one coin), coin balance of curvePool should have increased"
        );
        if (i == 0) {
            assertGt(
                poolRatioAfter,
                poolRatioBefore,
                "After adding only IBT, pool ratio should have increased"
            );
        } else {
            assertLt(
                poolRatioAfter,
                poolRatioBefore,
                "After adding only PT, pool ratio should have decreased"
            );
        }
    }

    function _testRemoveLiquidity(
        uint256 lpTokens,
        address owner,
        address receiver
    ) internal returns (uint256[2] memory amounts) {
        balancesData memory data;

        data.lpBalOwnerBefore = lpToken.balanceOf(owner);
        data.ibtBalReceiverBefore = ibt.balanceOf(receiver);
        data.ptBalReceiverBefore = principalToken.balanceOf(receiver);
        data.ibtBalCurvePoolBefore = ibt.balanceOf(curvePoolAddr);
        data.ptBalCurvePoolBefore = principalToken.balanceOf(curvePoolAddr);

        vm.startPrank(owner);
        lpToken.approve(address(router), lpTokens);
        uint256[] memory minExpectedAmounts = routerUtil.previewRemoveLiquiditySNG(
            curvePoolAddr,
            lpTokens
        );

        {
            (bytes memory commands, bytes[] memory inputs) = _buildRouterRemoveLiquidityExecution(
                curvePoolAddr,
                lpTokens,
                minExpectedAmounts,
                receiver
            );
            // owner removes liquidity for receiver
            router.execute(commands, inputs);
        }
        vm.stopPrank();

        data.lpBalOwnerAfter = lpToken.balanceOf(owner);
        data.ibtBalReceiverAfter = ibt.balanceOf(receiver);
        data.ptBalReceiverAfter = principalToken.balanceOf(receiver);
        data.ibtBalCurvePoolAfter = ibt.balanceOf(curvePoolAddr);
        data.ptBalCurvePoolAfter = principalToken.balanceOf(curvePoolAddr);

        amounts[0] = data.ibtBalReceiverAfter - data.ibtBalReceiverBefore;
        amounts[1] = data.ptBalReceiverAfter - data.ptBalReceiverBefore;

        assertGe(
            amounts[0],
            minExpectedAmounts[0],
            "After removing liquidity, IBT balance of receiver is too low"
        );
        assertGe(
            amounts[1],
            minExpectedAmounts[1],
            "After removing liquidity, PT balance of receiver is too low"
        );
        assertEq(
            data.lpBalOwnerBefore - data.lpBalOwnerAfter,
            lpTokens,
            "After removing liquidity, LPToken balance of sender is wrong"
        );
        assertGt(
            data.ibtBalCurvePoolBefore,
            data.ibtBalCurvePoolAfter,
            "After removing liquidity, IBT balance of curvePool should have decreased"
        );
        assertGt(
            data.ptBalCurvePoolBefore,
            data.ptBalCurvePoolAfter,
            "After removing liquidity, PT balance of curvePool should have decreased"
        );
    }

    function _testRemoveLiquidityForAsset(
        uint256 lpTokens,
        address owner,
        address receiver
    ) internal returns (uint256 assets) {
        balancesData memory data;

        data.lpBalOwnerBefore = lpToken.balanceOf(owner);
        data.ytBalOwnerBefore = yt.balanceOf(owner);
        data.assetBalReceiverBefore = underlying.balanceOf(receiver);
        data.ptBalReceiverBefore = principalToken.balanceOf(receiver);
        data.ibtBalCurvePoolBefore = ibt.balanceOf(curvePoolAddr);
        data.ptBalCurvePoolBefore = principalToken.balanceOf(curvePoolAddr);

        vm.startPrank(owner);
        lpToken.approve(address(router), lpTokens);
        uint256[] memory minExpectedAmounts = routerUtil.previewRemoveLiquiditySNG(
            curvePoolAddr,
            lpTokens
        );

        uint256 ytsToSend = Math.min(minExpectedAmounts[1], data.ytBalOwnerBefore);

        uint256 expectedAssets = ibt.previewRedeem(minExpectedAmounts[0]) +
            principalToken.previewRedeem(ytsToSend);

        yt.approve(address(router), ytsToSend);


        {
            (
                bytes memory commands,
                bytes[] memory inputs
            ) = _buildRouterRemoveLiquidityForAssetExecution(
                    curvePoolAddr,
                    lpTokens,
                    minExpectedAmounts,
                    owner,
                    receiver
                );
            // owner removes liquidity for receiver
            router.execute(commands, inputs);
        }
        vm.stopPrank();

        data.lpBalOwnerAfter = lpToken.balanceOf(owner);
        data.assetBalReceiverAfter = underlying.balanceOf(receiver);
        data.ptBalReceiverAfter = principalToken.balanceOf(receiver);
        data.ibtBalCurvePoolAfter = ibt.balanceOf(curvePoolAddr);
        data.ptBalCurvePoolAfter = principalToken.balanceOf(curvePoolAddr);

        assets = data.assetBalReceiverAfter - data.assetBalReceiverBefore;

        assertGe(
            assets,
            expectedAssets,
            "After removing liquidity, asset balance of receiver is too low"
        );
        assertEq(
            data.lpBalOwnerBefore - data.lpBalOwnerAfter,
            lpTokens,
            "After removing liquidity, LPToken balance of sender is wrong"
        );
        assertGt(
            data.ibtBalCurvePoolBefore,
            data.ibtBalCurvePoolAfter,
            "After removing liquidity, IBT balance of curvePool should have decreased"
        );
        assertGt(
            data.ptBalCurvePoolBefore,
            data.ptBalCurvePoolAfter,
            "After removing liquidity, PT balance of curvePool should have decreased"
        );
        assertEq(
            data.ptBalCurvePoolBefore - data.ptBalCurvePoolAfter - ytsToSend,
            data.ptBalReceiverAfter - data.ptBalReceiverBefore,
            "After removing liquidity, leftover PT should be sent to receiver"
        );
    }

    function _testRemoveLiquidityForIBT(
        uint256 lpTokens,
        address owner,
        address receiver
    ) internal returns (uint256 ibts) {
        balancesData memory data;

        data.lpBalOwnerBefore = lpToken.balanceOf(owner);
        data.ytBalOwnerBefore = yt.balanceOf(owner);
        data.ibtBalReceiverBefore = ibt.balanceOf(receiver);
        data.ptBalReceiverBefore = principalToken.balanceOf(receiver);
        data.ibtBalCurvePoolBefore = ibt.balanceOf(curvePoolAddr);
        data.ptBalCurvePoolBefore = principalToken.balanceOf(curvePoolAddr);

        vm.startPrank(owner);
        lpToken.approve(address(router), lpTokens);
        uint256[] memory minExpectedAmounts = routerUtil.previewRemoveLiquiditySNG(
            curvePoolAddr,
            lpTokens
        );

        uint256 ytsToSend = Math.min(minExpectedAmounts[1], data.ytBalOwnerBefore);

        uint256 expectedIBTs = minExpectedAmounts[0] +
            principalToken.previewRedeemForIBT(ytsToSend);

        yt.approve(address(router), ytsToSend);

        {
            (
                bytes memory commands,
                bytes[] memory inputs
            ) = _buildRouterRemoveLiquidityForIBTExecution(
                    curvePoolAddr,
                    lpTokens,
                    minExpectedAmounts,
                    owner,
                    receiver
                );
            // owner removes liquidity for receiver
            router.execute(commands, inputs);
        }
        vm.stopPrank();

        data.lpBalOwnerAfter = lpToken.balanceOf(owner);
        data.ibtBalReceiverAfter = ibt.balanceOf(receiver);
        data.ptBalReceiverAfter = principalToken.balanceOf(receiver);
        data.ibtBalCurvePoolAfter = ibt.balanceOf(curvePoolAddr);
        data.ptBalCurvePoolAfter = principalToken.balanceOf(curvePoolAddr);

        ibts = data.ibtBalReceiverAfter - data.ibtBalReceiverBefore;

        assertGe(
            ibts,
            expectedIBTs,
            "After removing liquidity, IBT balance of receiver is too low"
        );
        assertEq(
            data.lpBalOwnerBefore - data.lpBalOwnerAfter,
            lpTokens,
            "After removing liquidity, LPToken balance of sender is wrong"
        );
        assertGt(
            data.ibtBalCurvePoolBefore,
            data.ibtBalCurvePoolAfter,
            "After removing liquidity, IBT balance of curvePool should have decreased"
        );
        assertGt(
            data.ptBalCurvePoolBefore,
            data.ptBalCurvePoolAfter,
            "After removing liquidity, PT balance of curvePool should have decreased"
        );
        assertEq(
            data.ptBalCurvePoolBefore -
                data.ptBalCurvePoolAfter -
                Math.min(minExpectedAmounts[1], data.ytBalOwnerBefore),
            data.ptBalReceiverAfter - data.ptBalReceiverBefore,
            "After removing liquidity, leftover PT should be sent to receiver"
        );
    }

    function _testRemoveLiquidityOneCoin(
        uint256 lpTokens,
        uint256 i,
        address owner,
        address receiver
    ) internal returns (uint256 amount) {
        balancesData memory data;

        IERC20 coin = IERC20(ICurvePool(curvePoolAddr).coins(i));

        data.lpBalOwnerBefore = lpToken.balanceOf(owner);
        data.coinBalReceiverBefore = coin.balanceOf(receiver);
        data.coinBalCurvePoolBefore = coin.balanceOf(curvePoolAddr);

        vm.startPrank(owner);
        lpToken.approve(address(router), lpTokens);
        uint256 minExpectedAmount = _getMinExpectedAmountWithTolerance(
            routerUtil.previewRemoveLiquidityOneCoinSNG(curvePoolAddr, lpTokens, int128(int256(i)))
        );

        {
            (
                bytes memory commands,
                bytes[] memory inputs
            ) = _buildRouterRemoveLiquidityOneCoinExecution(
                    curvePoolAddr,
                    lpTokens,
                    i,
                    minExpectedAmount,
                    receiver
                );
            // owner removes liquidity for receiver
            router.execute(commands, inputs);
        }
        vm.stopPrank();

        data.lpBalOwnerAfter = lpToken.balanceOf(owner);
        data.coinBalReceiverAfter = coin.balanceOf(receiver);
        data.coinBalCurvePoolAfter = coin.balanceOf(curvePoolAddr);

        amount = data.coinBalReceiverAfter - data.coinBalReceiverBefore;

        assertGe(
            amount,
            minExpectedAmount,
            "After removing liquidity, coin balance of receiver is too low"
        );
        assertEq(
            data.lpBalOwnerBefore - data.lpBalOwnerAfter,
            lpTokens,
            "After removing liquidity, LPToken balance of sender is wrong"
        );
        assertGt(
            data.coinBalCurvePoolBefore,
            data.coinBalCurvePoolAfter,
            "After removing liquidity, coin balance of curvePool should have decreased"
        );
    }

    function _buildRouterAddLiquidityExecution(
        address curvePool,
        uint256[] memory amounts,
        uint256 minMintAmount,
        address receiver
    ) internal view returns (bytes memory commands, bytes[] memory inputs) {
        address ibt = ICurvePool(curvePool).coins(0);
        address pt = ICurvePool(curvePool).coins(1);

        commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.CURVE_ADD_LIQUIDITY_SNG))
        );
        inputs = new bytes[](3);
        uint256[] memory amounts_for_input = new uint256[](2);
        amounts_for_input[0] = Constants.CONTRACT_BALANCE;
        amounts_for_input[1] = Constants.CONTRACT_BALANCE;
        inputs[0] = abi.encode(ibt, amounts[0]);
        inputs[1] = abi.encode(pt, amounts[1]);
        inputs[2] = abi.encode(curvePool, amounts_for_input, minMintAmount, receiver);
        return (commands, inputs);
    }

    function _buildRouterAddLiquidityWithAssetExecution(
        address curvePool,
        uint256 assets,
        uint256 minMintAmount,
        address receiver
    ) internal view returns (bytes memory commands, bytes[] memory inputs) {
        address ibt = ICurvePool(curvePool).coins(0);
        commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.DEPOSIT_ASSET_IN_IBT)),
            bytes1(uint8(Commands.CURVE_SPLIT_IBT_LIQUIDITY_SNG)),
            bytes1(uint8(Commands.CURVE_ADD_LIQUIDITY_SNG))
        );
        inputs = new bytes[](4);
        inputs[0] = abi.encode(underlying, assets);
        inputs[1] = abi.encode(ibt, Constants.CONTRACT_BALANCE, Constants.ADDRESS_THIS);
        inputs[2] = abi.encode(
            curvePool,
            Constants.CONTRACT_BALANCE,
            Constants.ADDRESS_THIS,
            receiver,
            0
        );

        uint256[] memory amounts_for_input = new uint256[](2);
        amounts_for_input[0] = Constants.CONTRACT_BALANCE;
        amounts_for_input[1] = Constants.CONTRACT_BALANCE;
        inputs[3] = abi.encode(curvePool, amounts_for_input, minMintAmount, receiver);
        return (commands, inputs);
    }

    function _buildRouterAddLiquidityWithIBTExecution(
        address curvePool,
        uint256 ibts,
        uint256 minMintAmount,
        address receiver
    ) internal view returns (bytes memory commands, bytes[] memory inputs) {
        address ibt = ICurvePool(curvePool).coins(0);
        commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.CURVE_SPLIT_IBT_LIQUIDITY_SNG)),
            bytes1(uint8(Commands.CURVE_ADD_LIQUIDITY_SNG))
        );
        inputs = new bytes[](3);
        inputs[0] = abi.encode(ibt, ibts);
        inputs[1] = abi.encode(
            curvePool,
            Constants.CONTRACT_BALANCE,
            Constants.ADDRESS_THIS,
            receiver,
            0
        );
        uint256[] memory amounts_for_input = new uint256[](2);
        amounts_for_input[0] = Constants.CONTRACT_BALANCE;
        amounts_for_input[1] = Constants.CONTRACT_BALANCE;
        inputs[2] = abi.encode(curvePool, amounts_for_input, minMintAmount, receiver);
        return (commands, inputs);
    }

    function _buildRouterRemoveLiquidityExecution(
        address curvePool,
        uint256 lpTokens,
        uint256[] memory minAmounts,
        address receiver
    ) internal view returns (bytes memory commands, bytes[] memory inputs) {
        address lpToken = curvePoolAddr;
        commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.CURVE_REMOVE_LIQUIDITY_SNG))
        );
        inputs = new bytes[](2);
        inputs[0] = abi.encode(lpToken, lpTokens);
        inputs[1] = abi.encode(curvePool, Constants.CONTRACT_BALANCE, minAmounts, receiver);
        return (commands, inputs);
    }

    function _buildRouterRemoveLiquidityForIBTExecution(
        address curvePool,
        uint256 lpTokens,
        uint256[] memory minAmounts,
        address owner,
        address receiver
    ) internal view returns (bytes memory commands, bytes[] memory inputs) {
        address ibt = ICurvePool(curvePool).coins(0);
        address pt = ICurvePool(curvePool).coins(1);
        address yt = IPrincipalToken(pt).getYT();
        uint256 ytToSend = Math.min(minAmounts[1], IERC20(yt).balanceOf(owner));
        commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.CURVE_REMOVE_LIQUIDITY_SNG)),
            bytes1(uint8(Commands.REDEEM_PT_FOR_IBT)),
            bytes1(uint8(Commands.TRANSFER)),
            bytes1(uint8(Commands.TRANSFER))
        );
        inputs = new bytes[](6);
        inputs[0] = abi.encode(lpToken, lpTokens);
        inputs[1] = abi.encode(IPrincipalToken(pt).getYT(), ytToSend);
        inputs[2] = abi.encode(
            curvePool,
            Constants.CONTRACT_BALANCE,
            minAmounts,
            Constants.ADDRESS_THIS
        );
        inputs[3] = abi.encode(pt, ytToSend, Constants.ADDRESS_THIS, 0);
        inputs[4] = abi.encode(ibt, receiver, Constants.CONTRACT_BALANCE);
        inputs[5] = abi.encode(pt, receiver, Constants.CONTRACT_BALANCE);

        return (commands, inputs);
    }

    function _buildRouterRemoveLiquidityForAssetExecution(
        address curvePool,
        uint256 lpTokens,
        uint256[] memory minAmounts,
        address owner,
        address receiver
    ) internal view returns (bytes memory commands, bytes[] memory inputs) {
        address ibt = ICurvePool(curvePool).coins(0);
        address pt = ICurvePool(curvePool).coins(1);
        address yt = IPrincipalToken(pt).getYT();
        uint256 ytToSend = Math.min(minAmounts[1], IERC20(yt).balanceOf(owner));
        commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.CURVE_REMOVE_LIQUIDITY_SNG)),
            bytes1(uint8(Commands.REDEEM_PT_FOR_ASSET)),
            bytes1(uint8(Commands.REDEEM_IBT_FOR_ASSET)),
            bytes1(uint8(Commands.TRANSFER))
        );
        inputs = new bytes[](6);
        inputs[0] = abi.encode(lpToken, lpTokens);
        inputs[1] = abi.encode(IPrincipalToken(pt).getYT(), ytToSend);
        inputs[2] = abi.encode(
            curvePool,
            Constants.CONTRACT_BALANCE,
            minAmounts,
            Constants.ADDRESS_THIS
        );
        inputs[3] = abi.encode(pt, ytToSend, receiver, 0);
        inputs[4] = abi.encode(ibt, Constants.CONTRACT_BALANCE, receiver);
        inputs[5] = abi.encode(pt, receiver, Constants.CONTRACT_BALANCE);

        return (commands, inputs);
    }

    function _buildRouterRemoveLiquidityOneCoinExecution(
        address curvePool,
        uint256 lpTokens,
        uint256 i,
        uint256 minAmount,
        address receiver
    ) internal view returns (bytes memory commands, bytes[] memory inputs) {
        commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.CURVE_REMOVE_LIQUIDITY_ONE_COIN_SNG))
        );
        inputs = new bytes[](2);
        inputs[0] = abi.encode(lpToken, lpTokens);
        inputs[1] = abi.encode(curvePool, Constants.CONTRACT_BALANCE, i, minAmount, receiver);

        return (commands, inputs);
    }

    function _getPoolRatio(address curvePool) internal view returns (uint256 ratio) {
        return
            Math.mulDiv(ICurvePool(curvePool).balances(0), 1e27, ICurvePool(curvePool).balances(1));
    }

    /**
     * @dev Internal function that calculates the minimum expected amount with a tolerance.
     * Used when relying on Curve's previews (calc_token_amount() and calc_withdraw_one_coin()) that may not be 100% accurate.
     * @param amount The amount to deposit in the pool for a token.
     */
    function _getMinExpectedAmountWithTolerance(
        uint256 amount
    ) internal pure returns (uint256 minMintAmount) {
        amount = amount.mulDiv(UNIT - APPROXIMATION_TOLERANCE, UNIT);
    }

    /**
     * @param factor The IBT rate change factor. No yield = 1e18, half yield = 0.5e18, double yield = 2e18
     */
    function _setYield(uint256 factor) internal {
        bool isIncrease = factor >= 1e18;
        uint256 rateChange;
        if (isIncrease) {
            rateChange = (factor / 1e16) - 100;
        } else {
            rateChange = (1e18 - factor) / 1e16;
        }
        ibt.changeRate(uint16(rateChange), isIncrease);
    }
}
