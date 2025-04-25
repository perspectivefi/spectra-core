// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "./BaseSpectraFeedSNG.t.sol";
import {CurveOracleLib} from "../../src/libraries/CurveOracleLib.sol";
import {AggregatorV3Interface} from "../../src/interfaces/AggregatorV3Interface.sol";
import {MockPriceFeedCurvePTAssetSNG} from "./mocks/stableswap-ng/MockPriceFeedCurvePTAssetSNG.sol";
import {MockPriceFeedCurvePTIBTSNG} from "./mocks/stableswap-ng/MockPriceFeedCurvePTIBTSNG.sol";
import {IPrincipalToken} from "../../src/interfaces/IPrincipalToken.sol";

contract FeedCurvePTTest is BaseSpectraFeedSNGTest {
    using Math for uint256;

    function setUp() public override {
        network = "MAINNET";
        super.setUp();
    }

    function test_description() public override {
        Init memory init;
        setUpVaultsAndPool(init);
        _priceFeedInAsset_ = address(new MockPriceFeedCurvePTAssetSNG(_pt_, _curvePool_));
        _priceFeedInIBT_ = address(new MockPriceFeedCurvePTIBTSNG(_pt_, _curvePool_));
        assertEq(
            AggregatorV3Interface(_priceFeedInAsset_).description(),
            "IBT/PT Curve Pool Oracle: PT price in asset"
        );
        assertEq(
            AggregatorV3Interface(_priceFeedInIBT_).description(),
            "IBT/PT Curve Pool Oracle: PT price in IBT"
        );
    }

    function test_version() public override {
        Init memory init;
        setUpVaultsAndPool(init);
        _priceFeedInAsset_ = address(new MockPriceFeedCurvePTAssetSNG(_pt_, _curvePool_));
        _priceFeedInIBT_ = address(new MockPriceFeedCurvePTIBTSNG(_pt_, _curvePool_));
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
        _priceFeedInAsset_ = address(new MockPriceFeedCurvePTAssetSNG(_pt_, _curvePool_));
        _priceFeedInIBT_ = address(new MockPriceFeedCurvePTIBTSNG(_pt_, _curvePool_));
        assertEq(
            AggregatorV3Interface(_priceFeedInAsset_).decimals(),
            IERC20Metadata(_underlying_).decimals()
        );
        assertEq(
            AggregatorV3Interface(_priceFeedInIBT_).decimals(),
            IERC20Metadata(_ibt_).decimals()
        );
    }

    function test_getRoundDataAssetSNG_basic_fuzz(
        Init memory init,
        uint80 roundId
    ) public override {
        setUpVaultsAndPool(init);
        _priceFeedInAsset_ = address(new MockPriceFeedCurvePTAssetSNG(_pt_, _curvePool_));
        (
            uint80 _roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = AggregatorV3Interface(_priceFeedInAsset_).getRoundData(roundId);

        assertEq(_roundId, 0);
        assertEq(startedAt, 0);
        assertEq(updatedAt, 0);
        assertEq(answeredInRound, 0);
        // answer is non-zero
        assertGt(answer, 0, "Answer is not greater than 0 before expiry");
        assertApproxEqRel(
            uint256(answer),
            (init.initialPrice).mulDiv(10 ** init.underlyingDecimals, CurveOracleLib.CURVE_UNIT),
            1e15,
            "Answer is not the same as initial price without pool interactions (before expiry)"
        );

        skipToPTMaturity();

        (, answer, , , ) = AggregatorV3Interface(_priceFeedInAsset_).getRoundData(_roundId);

        assertGt(answer, 0, "Answer is not greater than 0 after expiry");
        assertApproxEqRel(
            uint256(answer),
            IPrincipalToken(_pt_).previewRedeem(ibtUnit),
            1e15,
            "Answer is not the same as initial price without pool interactions (after expiry)"
        );
    }

    function test_getRoundDataIBT_basic_fuzz(Init memory init, uint80 roundId) public override {
        setUpVaultsAndPool(init);
        _priceFeedInIBT_ = address(new MockPriceFeedCurvePTIBTSNG(_pt_, _curvePool_));
        (
            uint80 _roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = AggregatorV3Interface(_priceFeedInIBT_).getRoundData(roundId);

        assertEq(_roundId, 0);
        assertEq(startedAt, 0);
        assertEq(updatedAt, 0);
        assertEq(answeredInRound, 0);
        // answer is non-zero
        assertGt(answer, 0, "Answer is not greater than 0 before expiry");
        assertApproxEqRel(
            uint256(answer),
            (init.initialPrice).mulDiv(ibtUnit, CurveOracleLib.CURVE_UNIT),
            1e15,
            "Answer is not the same as initial price without pool interactions (before expiry)"
        );

        skipToPTMaturity();

        (, answer, , , ) = AggregatorV3Interface(_priceFeedInIBT_).getRoundData(roundId);

        assertGt(answer, 0, "Answer is not greater than 0 after expiry");
        assertApproxEqRel(
            uint256(answer),
            IPrincipalToken(_pt_).previewRedeemForIBT(ibtUnit),
            1e15,
            "Answer is not the same as initial price without pool interactions (after expiry)"
        );
    }

    function test_latestRoundDataAssetSNG_basic_fuzz(Init memory init) public override {
        setUpVaultsAndPool(init);
        _priceFeedInAsset_ = address(new MockPriceFeedCurvePTAssetSNG(_pt_, _curvePool_));
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = AggregatorV3Interface(_priceFeedInAsset_).latestRoundData();

        assertEq(roundId, 0);
        assertEq(startedAt, 0);
        assertEq(updatedAt, 0);
        assertEq(answeredInRound, 0);
        // answer is non-zero
        assertGt(answer, 0, "Answer is not greater than 0 before expiry");
        assertApproxEqRel(
            uint256(answer),
            (init.initialPrice).mulDiv(10 ** init.underlyingDecimals, CurveOracleLib.CURVE_UNIT),
            1e15,
            "Answer is not the same as initial price without pool interactions (before expiry)"
        );

        skipToPTMaturity();

        (, answer, , , ) = AggregatorV3Interface(_priceFeedInAsset_).latestRoundData();

        assertGt(answer, 0, "Answer is not greater than 0 after expiry");
        assertApproxEqRel(
            uint256(answer),
            IPrincipalToken(_pt_).previewRedeem(ibtUnit),
            1e15,
            "Answer is not the same as initial price without pool interactions (after expiry)"
        );
    }

    function test_latestRoundDataIBT_basic_fuzz(Init memory init) public override {
        setUpVaultsAndPool(init);
        _priceFeedInIBT_ = address(new MockPriceFeedCurvePTIBTSNG(_pt_, _curvePool_));
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = AggregatorV3Interface(_priceFeedInIBT_).latestRoundData();

        assertEq(roundId, 0);
        assertEq(startedAt, 0);
        assertEq(updatedAt, 0);
        assertEq(answeredInRound, 0);
        // answer is non-zero
        assertGt(answer, 0, "Answer is not greater than 0 before expiry");
        assertApproxEqRel(
            uint256(answer),
            (init.initialPrice).mulDiv(ibtUnit, CurveOracleLib.CURVE_UNIT),
            1e15,
            "Answer is not the same as initial price without pool interactions (before expiry)"
        );

        skipToPTMaturity();

        (, answer, , , ) = AggregatorV3Interface(_priceFeedInIBT_).latestRoundData();

        assertGt(answer, 0, "Answer is not greater than 0 after expiry");
        assertApproxEqRel(
            uint256(answer),
            IPrincipalToken(_pt_).previewRedeemForIBT(ibtUnit),
            1e15,
            "Answer is not the same as initial price without pool interactions (after expiry)"
        );
    }

    function test_latestRoundData_fuzz(
        Init memory init,
        bool swapInputBool,
        uint256 swapInputAmount,
        uint8 swapIterations
    ) public override {
        setUpVaultsAndPool(init);
        setUpIBTYield(init);
        _priceFeedInAsset_ = address(new MockPriceFeedCurvePTAssetSNG(_pt_, _curvePool_));
        _priceFeedInIBT_ = address(new MockPriceFeedCurvePTIBTSNG(_pt_, _curvePool_));

        swapIterations = uint8(bound(swapIterations, 1, 3));
        address swapInputToken = swapInputBool ? _pt_ : _ibt_;
        if (swapInputAmount > 0) {
            for (uint8 i = 0; i < swapIterations; i++) {
                // /// 2 conditions below prevent Curve pool from reverting on swaps
                // if (IStableSwapNG(_curvePool_).last_price(0) > 1e18) {
                //     break;
                // }
                // if (i != 0 && IStableSwapNG(_curvePool_).last_price(0) > 0.99e18) {
                //     break;
                // }
                swapInputAmount = bound(
                    swapInputAmount,
                    ibtUnit / 1000,
                    Math.min(
                        IERC20(swapInputToken).balanceOf(address(this)) / swapIterations,
                        IERC20(swapInputToken).balanceOf(_curvePool_) / (10 * swapIterations)
                    )
                );
                _approve(swapInputToken, address(this), _curvePool_, swapInputAmount);
                IStableSwapNG(_curvePool_).exchange(
                    int128(int8(swapInputBool ? 1 : 0)),
                    int128(int8(swapInputBool ? 0 : 1)),
                    swapInputAmount,
                    0
                );
            }
        }

        (, int256 answer, , , ) = AggregatorV3Interface(_priceFeedInAsset_).latestRoundData();

        assertApproxEqRel(
            uint256(answer),
            (underlyingUnit * IPrincipalToken(_pt_).getIBTRate()) / 1e27,
            1e18,
            "Asset: answer is wrong (before expiry)"
        );

        (, answer, , , ) = AggregatorV3Interface(_priceFeedInIBT_).latestRoundData();

        assertApproxEqRel(uint256(answer), ibtUnit, 1e18, "IBT: answer is wrong (before expiry)");

        skipToPTMaturity();

        (, answer, , , ) = AggregatorV3Interface(_priceFeedInAsset_).latestRoundData();

        assertApproxEqRel(
            uint256(answer),
            IPrincipalToken(_pt_).previewRedeem(ibtUnit),
            1e15,
            "Asset: answer is not the same as expected (after expiry)"
        );

        (, answer, , , ) = AggregatorV3Interface(_priceFeedInIBT_).latestRoundData();

        assertApproxEqRel(
            uint256(answer),
            IPrincipalToken(_pt_).previewRedeemForIBT(ibtUnit),
            1e15,
            "IBT: answer is not the same as expected (after expiry)"
        );
    }

    function test_compare_grd_lrd_fuzz(Init memory init, uint80 roundId) public override {
        setUpVaultsAndPool(init);
        setUpIBTYield(init);
        _priceFeedInAsset_ = address(new MockPriceFeedCurvePTAssetSNG(_pt_, _curvePool_));
        _priceFeedInIBT_ = address(new MockPriceFeedCurvePTIBTSNG(_pt_, _curvePool_));

        (, int256 answer1, , , ) = AggregatorV3Interface(_priceFeedInAsset_).getRoundData(roundId);

        (, int256 answer2, , , ) = AggregatorV3Interface(_priceFeedInAsset_).latestRoundData();

        assertEq(answer1, answer2, "Asset: equality before expiry fails");
        // the equality is tested in the ibt scenario

        if (init.yield > 0) {
            assertGe(
                uint256(answer1),
                (init.initialPrice).mulDiv(
                    10 ** init.underlyingDecimals,
                    CurveOracleLib.CURVE_UNIT
                ) - 10,
                "Asset: Answer is not greater then initial price without pool interactions despite positive yield (before expiry)"
            );
        }

        (, answer1, , , ) = AggregatorV3Interface(_priceFeedInIBT_).getRoundData(roundId);

        (, answer2, , , ) = AggregatorV3Interface(_priceFeedInIBT_).latestRoundData();

        assertEq(answer1, answer2, "IBT: equality before expiry fails");
        assertApproxEqRel(
            uint256(answer1),
            (init.initialPrice).mulDiv(ibtUnit, CurveOracleLib.CURVE_UNIT),
            1e15,
            "IBT: Answer is not the same as initial price without pool interactions (before expiry)"
        );

        skipToPTMaturity();

        (, answer1, , , ) = AggregatorV3Interface(_priceFeedInAsset_).getRoundData(roundId);

        (, answer2, , , ) = AggregatorV3Interface(_priceFeedInAsset_).latestRoundData();

        assertEq(answer1, answer2, "Asset: equality after expiry fails");
        assertApproxEqRel(
            uint256(answer1),
            IPrincipalToken(_pt_).previewRedeem(ibtUnit),
            1e15,
            "Asset: Answer is not the same as initial price without pool interactions (after expiry)"
        );

        (, answer1, , , ) = AggregatorV3Interface(_priceFeedInIBT_).getRoundData(roundId);

        (, answer2, , , ) = AggregatorV3Interface(_priceFeedInIBT_).latestRoundData();

        assertEq(answer1, answer2, "IBT: equality after expiry fails");
        assertApproxEqRel(
            uint256(answer1),
            IPrincipalToken(_pt_).previewRedeemForIBT(ibtUnit),
            1e15,
            "IBT: Answer is not the same as initial price without pool interactions (after expiry)"
        );
    }

    function skipToPTMaturity() internal {
        vm.warp(IPrincipalToken(_pt_).maturity());
        vm.roll(block.number + 1);
    }
}
