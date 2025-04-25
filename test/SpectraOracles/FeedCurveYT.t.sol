// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "./BaseSpectraFeed.t.sol";
import {CurveOracleLib} from "../../src/libraries/CurveOracleLib.sol";
import {AggregatorV3Interface} from "../../src/interfaces/AggregatorV3Interface.sol";
import {MockPriceFeedCurveYTAsset} from "./mocks/cryptoswap-ng/MockPriceFeedCurveYTAsset.sol";
import {MockPriceFeedCurveYTIBT} from "./mocks/cryptoswap-ng/MockPriceFeedCurveYTIBT.sol";
import {IPrincipalToken} from "../../src/interfaces/IPrincipalToken.sol";

contract FeedCurveYTTest is BaseSpectraFeedTest {
    using Math for uint256;

    function setUp() public override {
        network = "MAINNET";
        super.setUp();
    }

    function test_description() public override {
        Init memory init;
        setUpVaultsAndPool(init);
        _priceFeedInAsset_ = address(new MockPriceFeedCurveYTAsset(_pt_, _curvePool_));
        _priceFeedInIBT_ = address(new MockPriceFeedCurveYTIBT(_pt_, _curvePool_));
        assertEq(
            AggregatorV3Interface(_priceFeedInAsset_).description(),
            "IBT/PT Curve Pool Oracle: YT price in asset"
        );
        assertEq(
            AggregatorV3Interface(_priceFeedInIBT_).description(),
            "IBT/PT Curve Pool Oracle: YT price in IBT"
        );
    }

    function test_version() public override {
        Init memory init;
        setUpVaultsAndPool(init);
        _priceFeedInAsset_ = address(new MockPriceFeedCurveYTAsset(_pt_, _curvePool_));
        _priceFeedInIBT_ = address(new MockPriceFeedCurveYTIBT(_pt_, _curvePool_));
        assertEq(AggregatorV3Interface(_priceFeedInAsset_).version(), 1);
        assertEq(AggregatorV3Interface(_priceFeedInIBT_).version(), 1);
    }

    function test_decimals_fuzz(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimalsOffset
    ) public override {
        Init memory init;
        init.underlyingDecimals = _underlyingDecimals;
        init.ibtDecimalsOffset = _ibtDecimalsOffset;
        setUpVaultsAndPool(init);
        _priceFeedInAsset_ = address(new MockPriceFeedCurveYTAsset(_pt_, _curvePool_));
        _priceFeedInIBT_ = address(new MockPriceFeedCurveYTIBT(_pt_, _curvePool_));
        assertEq(
            AggregatorV3Interface(_priceFeedInAsset_).decimals(),
            IERC20Metadata(_underlying_).decimals()
        );
        assertEq(
            AggregatorV3Interface(_priceFeedInIBT_).decimals(),
            IERC20Metadata(_ibt_).decimals()
        );
    }

    function test_getRoundDataAsset_basic_fuzz(Init memory init, uint80 roundId) public override {
        MIN_INITIAL_PRICE = 1e15;
        MAX_INITIAL_PRICE = 1e20;
        setUpVaultsAndPool(init);
        _priceFeedInAsset_ = address(new MockPriceFeedCurveYTAsset(_pt_, _curvePool_));

        uint80 _roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;

        uint256 ptToAssetRateOracle = IPrincipalToken(_pt_).previewRedeem(
            ibtUnit.mulDiv(init.initialPrice, CurveOracleLib.CURVE_UNIT)
        );

        if (ptToAssetRateOracle > underlyingUnit) {
            vm.expectRevert(abi.encodeWithSelector(CurveOracleLib.PoolLiquidityError.selector));
            (, answer, , , ) = AggregatorV3Interface(_priceFeedInAsset_).getRoundData(roundId);
        } else {
            (_roundId, answer, startedAt, updatedAt, answeredInRound) = AggregatorV3Interface(
                _priceFeedInAsset_
            ).getRoundData(roundId);

            assertEq(_roundId, 0);
            assertEq(startedAt, 0);
            assertEq(updatedAt, 0);
            assertEq(answeredInRound, 0);

            if (ptToAssetRateOracle == underlyingUnit) {
                assertEq(uint256(answer), 0);
            } else {
                assertGt(uint256(answer), 0);
                assertApproxEqRel(uint256(answer), underlyingUnit, 1e18);
            }
        }

        skipToPTMaturity();

        (, answer, , , ) = AggregatorV3Interface(_priceFeedInAsset_).getRoundData(roundId);

        assertEq(uint256(answer), 0, "Asset: Answer is not 0 (after expiry)");
    }

    function test_getRoundDataIBT_basic_fuzz(Init memory init, uint80 roundId) public override {
        MIN_INITIAL_PRICE = 1e15;
        MAX_INITIAL_PRICE = 1e20;
        setUpVaultsAndPool(init);
        _priceFeedInIBT_ = address(new MockPriceFeedCurveYTIBT(_pt_, _curvePool_));

        uint80 _roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;

        uint256 ptToIBTRateOracle = ibtUnit.mulDiv(init.initialPrice, CurveOracleLib.CURVE_UNIT);

        if (ptToIBTRateOracle > ibtUnit) {
            vm.expectRevert(abi.encodeWithSelector(CurveOracleLib.PoolLiquidityError.selector));
            (, answer, , , ) = AggregatorV3Interface(_priceFeedInIBT_).getRoundData(roundId);
        } else {
            (_roundId, answer, startedAt, updatedAt, answeredInRound) = AggregatorV3Interface(
                _priceFeedInIBT_
            ).getRoundData(roundId);

            assertEq(_roundId, 0);
            assertEq(startedAt, 0);
            assertEq(updatedAt, 0);
            assertEq(answeredInRound, 0);

            if (ptToIBTRateOracle == ibtUnit) {
                assertEq(uint256(answer), 0);
            } else {
                assertGt(uint256(answer), 0);
                assertApproxEqRel(uint256(answer), ibtUnit, 1e18);
            }
        }

        skipToPTMaturity();

        (, answer, , , ) = AggregatorV3Interface(_priceFeedInIBT_).getRoundData(roundId);

        assertEq(uint256(answer), 0, "IBT: Answer is not 0 (after expiry)");
    }

    function test_latestRoundDataAsset_basic_fuzz(Init memory init) public override {
        MIN_INITIAL_PRICE = 1e15;
        MAX_INITIAL_PRICE = 1e20;
        setUpVaultsAndPool(init);
        _priceFeedInAsset_ = address(new MockPriceFeedCurveYTAsset(_pt_, _curvePool_));

        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;

        uint256 ptToAssetRateOracle = IPrincipalToken(_pt_).previewRedeem(
            ibtUnit.mulDiv(init.initialPrice, CurveOracleLib.CURVE_UNIT)
        );

        if (ptToAssetRateOracle > underlyingUnit) {
            vm.expectRevert(abi.encodeWithSelector(CurveOracleLib.PoolLiquidityError.selector));
            (, answer, , , ) = AggregatorV3Interface(_priceFeedInAsset_).latestRoundData();
        } else {
            (roundId, answer, startedAt, updatedAt, answeredInRound) = AggregatorV3Interface(
                _priceFeedInAsset_
            ).latestRoundData();

            assertEq(roundId, 0);
            assertEq(startedAt, 0);
            assertEq(updatedAt, 0);
            assertEq(answeredInRound, 0);

            if (ptToAssetRateOracle == underlyingUnit) {
                assertEq(uint256(answer), 0);
            } else {
                assertGt(uint256(answer), 0);
                assertApproxEqRel(uint256(answer), underlyingUnit, 1e18);
            }
        }

        skipToPTMaturity();

        (, answer, , , ) = AggregatorV3Interface(_priceFeedInAsset_).latestRoundData();

        assertEq(uint256(answer), 0, "Asset: Answer is not 0 (after expiry)");
    }

    function test_latestRoundDataIBT_basic_fuzz(Init memory init) public override {
        MIN_INITIAL_PRICE = 1e15;
        MAX_INITIAL_PRICE = 1e20;
        setUpVaultsAndPool(init);
        _priceFeedInIBT_ = address(new MockPriceFeedCurveYTIBT(_pt_, _curvePool_));

        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;

        uint256 ptToIBTRateOracle = ibtUnit.mulDiv(init.initialPrice, CurveOracleLib.CURVE_UNIT);

        if (ptToIBTRateOracle > ibtUnit) {
            vm.expectRevert(abi.encodeWithSelector(CurveOracleLib.PoolLiquidityError.selector));
            (, answer, , , ) = AggregatorV3Interface(_priceFeedInIBT_).latestRoundData();
        } else {
            (roundId, answer, startedAt, updatedAt, answeredInRound) = AggregatorV3Interface(
                _priceFeedInIBT_
            ).latestRoundData();

            assertEq(roundId, 0);
            assertEq(startedAt, 0);
            assertEq(updatedAt, 0);
            assertEq(answeredInRound, 0);

            if (ptToIBTRateOracle == ibtUnit) {
                assertEq(uint256(answer), 0);
            } else {
                assertGt(uint256(answer), 0);
                assertApproxEqRel(uint256(answer), ibtUnit, 1e18);
            }
        }

        skipToPTMaturity();

        (, answer, , , ) = AggregatorV3Interface(_priceFeedInIBT_).latestRoundData();

        assertEq(uint256(answer), 0, "IBT: Answer is not 0 (after expiry)");
    }

    function test_latestRoundData_fuzz(
        Init memory init,
        bool swapInputBool,
        uint256 swapInputAmount,
        uint8 swapIterations
    ) public override {
        setUpVaultsAndPool(init);
        setUpIBTYield(init);
        _priceFeedInAsset_ = address(new MockPriceFeedCurveYTAsset(_pt_, _curvePool_));
        _priceFeedInIBT_ = address(new MockPriceFeedCurveYTIBT(_pt_, _curvePool_));

        swapIterations = uint8(bound(swapIterations, 1, 3));
        address swapInputToken = swapInputBool ? _pt_ : _ibt_;
        if (swapInputAmount > 0) {
            for (uint8 i = 0; i < swapIterations; i++) {
                // 2 conditions below prevent Curve pool from reverting on swaps
                if (ICurveNGPool(_curvePool_).last_prices() > 1e18) {
                    break;
                }
                if (i != 0 && ICurveNGPool(_curvePool_).last_prices() > 0.99e18) {
                    break;
                }
                swapInputAmount = bound(
                    swapInputAmount,
                    ibtUnit / 1000,
                    Math.min(
                        IERC20(swapInputToken).balanceOf(address(this)) / swapIterations,
                        IERC20(swapInputToken).balanceOf(_curvePool_) / (10 * swapIterations)
                    )
                );
                _approve(swapInputToken, address(this), _curvePool_, swapInputAmount);
                ICurveNGPool(_curvePool_).exchange(
                    swapInputBool ? 1 : 0,
                    swapInputBool ? 0 : 1,
                    swapInputAmount,
                    0,
                    address(this)
                );
            }
        }

        uint256 ptToIBTRateOracle = ibtUnit.mulDiv(
            ICurveNGPool(_curvePool_).price_oracle(),
            CurveOracleLib.CURVE_UNIT
        );
        uint256 ptToAssetRateOracle = IERC4626(_ibt_).previewRedeem(ptToIBTRateOracle);

        bytes memory revertData = abi.encodeWithSelector(
            CurveOracleLib.PoolLiquidityError.selector
        );

        int256 answer;

        if (ptToAssetRateOracle > IPrincipalToken(_pt_).previewRedeem(ibtUnit)) {
            vm.expectRevert(revertData);
            (, answer, , , ) = AggregatorV3Interface(_priceFeedInAsset_).latestRoundData();
        } else {
            (, answer, , , ) = AggregatorV3Interface(_priceFeedInAsset_).latestRoundData();

            if (init.initialPrice == CurveOracleLib.CURVE_UNIT) {
                assertEq(uint256(answer), 0);
            } else {
                assertApproxEqRel(uint256(answer), underlyingUnit, 1e18);
            }
        }

        if (ptToIBTRateOracle > IPrincipalToken(_pt_).previewRedeemForIBT(ibtUnit)) {
            vm.expectRevert(revertData);
            (, answer, , , ) = AggregatorV3Interface(_priceFeedInIBT_).latestRoundData();
        } else {
            (, answer, , , ) = AggregatorV3Interface(_priceFeedInIBT_).latestRoundData();

            if (init.initialPrice == CurveOracleLib.CURVE_UNIT) {
                assertEq(uint256(answer), 0);
            } else {
                assertApproxEqRel(uint256(answer), ibtUnit, 1e18);
            }
        }

        skipToPTMaturity();

        (, answer, , , ) = AggregatorV3Interface(_priceFeedInAsset_).latestRoundData();

        assertEq(uint256(answer), 0, "Asset: Answer is not 0 (after expiry)");

        (, answer, , , ) = AggregatorV3Interface(_priceFeedInIBT_).latestRoundData();

        assertEq(uint256(answer), 0, "IBT: Answer is not 0 (after expiry)");
    }

    function test_compare_grd_lrd_fuzz(Init memory init, uint80 roundId) public override {
        setUpVaultsAndPool(init);
        setUpIBTYield(init);
        _priceFeedInAsset_ = address(new MockPriceFeedCurveYTAsset(_pt_, _curvePool_));
        _priceFeedInIBT_ = address(new MockPriceFeedCurveYTIBT(_pt_, _curvePool_));

        uint256 ptToIBTRateOracle = ibtUnit.mulDiv(
            ICurveNGPool(_curvePool_).price_oracle(),
            CurveOracleLib.CURVE_UNIT
        );
        uint256 ptToAssetRateOracle = IERC4626(_ibt_).previewRedeem(ptToIBTRateOracle);

        bytes memory revertData = abi.encodeWithSelector(
            CurveOracleLib.PoolLiquidityError.selector
        );

        int256 answer1;
        int256 answer2;

        if (ptToAssetRateOracle > IPrincipalToken(_pt_).previewRedeem(ibtUnit)) {
            vm.expectRevert(revertData);
            (, answer1, , , ) = AggregatorV3Interface(_priceFeedInAsset_).getRoundData(roundId);

            vm.expectRevert(revertData);
            (, answer2, , , ) = AggregatorV3Interface(_priceFeedInAsset_).latestRoundData();
        } else {
            (, answer1, , , ) = AggregatorV3Interface(_priceFeedInAsset_).getRoundData(roundId);

            (, answer2, , , ) = AggregatorV3Interface(_priceFeedInAsset_).latestRoundData();

            assertEq(answer1, answer2, "Asset: equality fails (before expiry)");

            if (init.initialPrice == 1e18) {
                assertEq(uint256(answer1), 0);
            } else {
                assertApproxEqRel(uint256(answer1), underlyingUnit, 1e18);
            }
        }

        if (ptToIBTRateOracle > IPrincipalToken(_pt_).previewRedeemForIBT(ibtUnit)) {
            vm.expectRevert(revertData);
            (, answer1, , , ) = AggregatorV3Interface(_priceFeedInIBT_).getRoundData(roundId);

            vm.expectRevert(revertData);
            (, answer2, , , ) = AggregatorV3Interface(_priceFeedInIBT_).latestRoundData();
        } else {
            (, answer1, , , ) = AggregatorV3Interface(_priceFeedInIBT_).getRoundData(roundId);

            (, answer2, , , ) = AggregatorV3Interface(_priceFeedInIBT_).latestRoundData();

            assertEq(answer1, answer2, "IBT: equality fails (before expiry)");
            if (init.initialPrice == 1e18) {
                assertEq(uint256(answer1), 0);
            } else {
                assertApproxEqRel(uint256(answer1), ibtUnit, 1e18);
            }
        }

        skipToPTMaturity();

        (, answer1, , , ) = AggregatorV3Interface(_priceFeedInAsset_).getRoundData(roundId);

        (, answer2, , , ) = AggregatorV3Interface(_priceFeedInAsset_).latestRoundData();

        assertEq(answer1, answer2, "Asset: equality fails (after expiry)");
        assertEq(uint256(answer1), 0, "Asset: answer is not 0 (after expiry)");

        (, answer1, , , ) = AggregatorV3Interface(_priceFeedInIBT_).getRoundData(roundId);

        (, answer2, , , ) = AggregatorV3Interface(_priceFeedInIBT_).latestRoundData();

        assertEq(answer1, answer2, "IBT: equality fails (after expiry)");
        assertEq(uint256(answer1), 0, "IBT: answer is not 0 (after expiry)");
    }

    function skipToPTMaturity() internal {
        vm.warp(IPrincipalToken(_pt_).maturity());
        vm.roll(block.number + 1);
    }
}
