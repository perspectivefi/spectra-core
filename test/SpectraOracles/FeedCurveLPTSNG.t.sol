// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "./BaseSpectraFeedSNG.t.sol";
import {AggregatorV3Interface} from "../../src/interfaces/AggregatorV3Interface.sol";
import {MockPriceFeedCurveLPTAssetSNG} from "./mocks/stableswap-ng/MockPriceFeedCurveLPTAssetSNG.sol";
import {MockPriceFeedCurveLPTIBTSNG} from "./mocks/stableswap-ng/MockPriceFeedCurveLPTIBTSNG.sol";
import {IPrincipalToken} from "../../src/interfaces/IPrincipalToken.sol";
import {CurveOracleLib} from "../../src/libraries/CurveOracleLib.sol";

contract FeedCurveLPTTest is BaseSpectraFeedSNGTest {
    using Math for uint256;

    uint256 constant UNIT = 1e18;

    struct AdditionalData {
        uint80 roundId;
        uint256 startedAt;
        uint256 updatedAt;
        int256 answer;
        uint80 answeredInRound;
    }

    function setUp() public override {
        network = "MAINNET";
        super.setUp();
    }

    function test_description() public override {
        Init memory init;
        setUpVaultsAndPool(init);
        _priceFeedInAsset_ = address(new MockPriceFeedCurveLPTAssetSNG(_pt_, _curvePool_));
        _priceFeedInIBT_ = address(new MockPriceFeedCurveLPTIBTSNG(_pt_, _curvePool_));
        assertEq(
            AggregatorV3Interface(_priceFeedInAsset_).description(),
            "IBT/PT Curve Pool Oracle: LPT price in asset"
        );
        assertEq(
            AggregatorV3Interface(_priceFeedInIBT_).description(),
            "IBT/PT Curve Pool Oracle: LPT price in IBT"
        );
    }

    function test_version() public override {
        Init memory init;
        setUpVaultsAndPool(init);
        _priceFeedInAsset_ = address(new MockPriceFeedCurveLPTAssetSNG(_pt_, _curvePool_));
        _priceFeedInIBT_ = address(new MockPriceFeedCurveLPTIBTSNG(_pt_, _curvePool_));
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
        _priceFeedInAsset_ = address(new MockPriceFeedCurveLPTAssetSNG(_pt_, _curvePool_));
        _priceFeedInIBT_ = address(new MockPriceFeedCurveLPTIBTSNG(_pt_, _curvePool_));
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
        uint80 _roundId
    ) public override {
        AdditionalData memory addData;
        setUpVaultsAndPool(init);
        _priceFeedInAsset_ = address(new MockPriceFeedCurveLPTAssetSNG(_pt_, _curvePool_));
        (
            addData.roundId,
            addData.answer,
            addData.startedAt,
            addData.updatedAt,
            addData.answeredInRound
        ) = AggregatorV3Interface(_priceFeedInAsset_).getRoundData(_roundId);

        assertEq(addData.roundId, 0);
        assertEq(addData.startedAt, 0);
        assertEq(addData.updatedAt, 0);
        assertEq(addData.answeredInRound, 0);
        // answer is non-zero
        assertGt(addData.answer, 0, "Answer is not greater than 0 before expiry");
        uint256 poolBalIBT = IStableSwapNG(_curvePool_).balances(0);
        uint256 poolBalPT = IStableSwapNG(_curvePool_).balances(1);
        uint256 supplyLPT = IERC20(_curvePool_).totalSupply();
        assertApproxEqRel(
            uint256(addData.answer),
            IERC4626(_ibt_).previewRedeem(
                (poolBalPT.mulDiv(init.initialPrice, UNIT) + poolBalIBT).mulDiv(UNIT, supplyLPT)
            ),
            1e15,
            "Answer is not the same as initial price without pool interactions nor yield (before expiry)"
        );

        skipToPTMaturity();

        (, addData.answer, , , ) = AggregatorV3Interface(_priceFeedInAsset_).getRoundData(_roundId);

        assertGt(addData.answer, 0, "Answer is not greater than 0 after expiry");
        assertApproxEqRel(
            uint256(addData.answer),
            IERC4626(_ibt_).previewRedeem(
                poolBalIBT.mulDiv(UNIT, supplyLPT) +
                    IPrincipalToken(_pt_).previewRedeemForIBT(poolBalPT.mulDiv(UNIT, supplyLPT))
            ),
            1e15,
            "Answer is not the same as initial price without pool interactions nor yield (after expiry)"
        );
    }

    function test_getRoundDataIBT_basic_fuzz(Init memory init, uint80 _roundId) public override {
        AdditionalData memory addData;
        setUpVaultsAndPool(init);
        _priceFeedInIBT_ = address(new MockPriceFeedCurveLPTIBTSNG(_pt_, _curvePool_));
        (
            addData.roundId,
            addData.answer,
            addData.startedAt,
            addData.updatedAt,
            addData.answeredInRound
        ) = AggregatorV3Interface(_priceFeedInIBT_).getRoundData(_roundId);

        assertEq(addData.roundId, 0);
        assertEq(addData.startedAt, 0);
        assertEq(addData.updatedAt, 0);
        assertEq(addData.answeredInRound, 0);
        // answer is non-zero
        assertGt(addData.answer, 0, "Answer is not greater than 0 before expiry");
        uint256 poolBalIBT = IStableSwapNG(_curvePool_).balances(0);
        uint256 poolBalPT = IStableSwapNG(_curvePool_).balances(1);
        uint256 supplyLPT = IERC20(_curvePool_).totalSupply();
        assertApproxEqRel(
            uint256(addData.answer),
            (poolBalPT.mulDiv(init.initialPrice, UNIT) + poolBalIBT).mulDiv(UNIT, supplyLPT),
            1e15,
            "Answer is not the same as initial price without pool interactions nor yield (before expiry)"
        );

        skipToPTMaturity();

        (, addData.answer, , , ) = AggregatorV3Interface(_priceFeedInIBT_).getRoundData(_roundId);

        assertGt(addData.answer, 0, "Answer is not greater than 0 after expiry");
        assertApproxEqRel(
            uint256(addData.answer),
            poolBalIBT.mulDiv(UNIT, supplyLPT) +
                IPrincipalToken(_pt_).previewRedeemForIBT(poolBalPT.mulDiv(UNIT, supplyLPT)),
            1e15,
            "Answer is not the same as initial price without pool interactions nor yield (after expiry)"
        );
    }

    function test_latestRoundDataAssetSNG_basic_fuzz(Init memory init) public override {
        AdditionalData memory addData;
        setUpVaultsAndPool(init);
        _priceFeedInAsset_ = address(new MockPriceFeedCurveLPTAssetSNG(_pt_, _curvePool_));
        (
            addData.roundId,
            addData.answer,
            addData.startedAt,
            addData.updatedAt,
            addData.answeredInRound
        ) = AggregatorV3Interface(_priceFeedInAsset_).latestRoundData();

        assertEq(addData.roundId, 0);
        assertEq(addData.startedAt, 0);
        assertEq(addData.updatedAt, 0);
        assertEq(addData.answeredInRound, 0);
        // answer is non-zero
        assertGt(addData.answer, 0, "Answer is not greater than 0 before expiry");
        uint256 poolBalIBT = IStableSwapNG(_curvePool_).balances(0);
        uint256 poolBalPT = IStableSwapNG(_curvePool_).balances(1);
        uint256 supplyLPT = IERC20(_curvePool_).totalSupply();
        assertApproxEqRel(
            uint256(addData.answer),
            IERC4626(_ibt_).previewRedeem(
                (poolBalPT.mulDiv(init.initialPrice, UNIT) + poolBalIBT).mulDiv(UNIT, supplyLPT)
            ),
            1e15,
            "Answer is not the same as initial price without pool interactions nor yield (before expiry)"
        );

        skipToPTMaturity();

        (, addData.answer, , , ) = AggregatorV3Interface(_priceFeedInAsset_).latestRoundData();

        assertGt(addData.answer, 0, "Answer is not greater than 0 after expiry");
        assertApproxEqRel(
            uint256(addData.answer),
            IERC4626(_ibt_).previewRedeem(
                poolBalIBT.mulDiv(UNIT, supplyLPT) +
                    IPrincipalToken(_pt_).previewRedeemForIBT(poolBalPT.mulDiv(UNIT, supplyLPT))
            ),
            1e15,
            "Answer is not the same as initial price without pool interactions nor yield (after expiry)"
        );
    }

    function test_latestRoundDataIBT_basic_fuzz(Init memory init) public override {
        AdditionalData memory addData;
        setUpVaultsAndPool(init);
        _priceFeedInIBT_ = address(new MockPriceFeedCurveLPTIBTSNG(_pt_, _curvePool_));
        (
            addData.roundId,
            addData.answer,
            addData.startedAt,
            addData.updatedAt,
            addData.answeredInRound
        ) = AggregatorV3Interface(_priceFeedInIBT_).latestRoundData();

        assertEq(addData.roundId, 0);
        assertEq(addData.startedAt, 0);
        assertEq(addData.updatedAt, 0);
        assertEq(addData.answeredInRound, 0);
        // answer is non-zero
        assertGt(addData.answer, 0, "Answer is not greater than 0 before expiry");
        uint256 poolBalIBT = IStableSwapNG(_curvePool_).balances(0);
        uint256 poolBalPT = IStableSwapNG(_curvePool_).balances(1);
        uint256 supplyLPT = IERC20(_curvePool_).totalSupply();
        assertApproxEqRel(
            uint256(addData.answer),
            (poolBalPT.mulDiv(init.initialPrice, UNIT) + poolBalIBT).mulDiv(UNIT, supplyLPT),
            1e15,
            "Answer is not the same as initial price without pool interactions nor yield (before expiry)"
        );

        skipToPTMaturity();

        (, addData.answer, , , ) = AggregatorV3Interface(_priceFeedInIBT_).latestRoundData();

        assertGt(addData.answer, 0, "Answer is not greater than 0 after expiry");
        assertApproxEqRel(
            uint256(addData.answer),
            poolBalIBT.mulDiv(UNIT, supplyLPT) +
                IPrincipalToken(_pt_).previewRedeemForIBT(poolBalPT.mulDiv(UNIT, supplyLPT)),
            1e15,
            "Answer is not the same as initial price without pool interactions nor yield (after expiry)"
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
        _priceFeedInAsset_ = address(new MockPriceFeedCurveLPTAssetSNG(_pt_, _curvePool_));
        _priceFeedInIBT_ = address(new MockPriceFeedCurveLPTIBTSNG(_pt_, _curvePool_));

        swapIterations = uint8(bound(swapIterations, 1, 3));
        address swapInputToken = swapInputBool ? _pt_ : _ibt_;
        uint256 currentPoolPrice = init.initialPrice;
        if (swapInputAmount > 0) {
            for (uint8 i = 0; i < swapIterations; i++) {
                // // 2 conditions below prevent Curve pool from reverting on swaps
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

        uint256 poolBalIBT = IStableSwapNG(_curvePool_).balances(0);
        uint256 poolBalPT = IStableSwapNG(_curvePool_).balances(1);
        uint256 supplyLPT = IERC20(_curvePool_).totalSupply();

        (, int256 answer, , , ) = AggregatorV3Interface(_priceFeedInAsset_).latestRoundData();

        assertApproxEqRel(
            uint256(answer),
            IERC4626(_ibt_).previewRedeem(
                (poolBalPT.mulDiv(currentPoolPrice, UNIT) + poolBalIBT).mulDiv(UNIT, supplyLPT)
            ),
            1e18,
            "Asset: answer is wrong (before expiry)"
        );

        (, answer, , , ) = AggregatorV3Interface(_priceFeedInIBT_).latestRoundData();

        assertApproxEqRel(
            uint256(answer),
            (poolBalPT.mulDiv(currentPoolPrice, UNIT) + poolBalIBT).mulDiv(UNIT, supplyLPT),
            1e18,
            "IBT: answer is wrong (before expiry)"
        );

        skipToPTMaturity();

        (, answer, , , ) = AggregatorV3Interface(_priceFeedInAsset_).latestRoundData();

        assertApproxEqRel(
            uint256(answer),
            IERC4626(_ibt_).previewRedeem(
                poolBalIBT.mulDiv(UNIT, supplyLPT) +
                    IPrincipalToken(_pt_).previewRedeemForIBT(poolBalPT.mulDiv(UNIT, supplyLPT))
            ),
            1e15,
            "Asset: answer is not the same as expected (after expiry)"
        );

        (, answer, , , ) = AggregatorV3Interface(_priceFeedInIBT_).latestRoundData();

        assertApproxEqRel(
            uint256(answer),
            poolBalIBT.mulDiv(UNIT, supplyLPT) +
                IPrincipalToken(_pt_).previewRedeemForIBT(poolBalPT.mulDiv(UNIT, supplyLPT)),
            1e15,
            "IBT: answer is not the same as expected (after expiry)"
        );
    }

    function test_compare_grd_lrd_fuzz(Init memory init, uint80 _roundId) public override {
        setUpVaultsAndPool(init);
        setUpIBTYield(init);
        _priceFeedInAsset_ = address(new MockPriceFeedCurveLPTAssetSNG(_pt_, _curvePool_));
        _priceFeedInIBT_ = address(new MockPriceFeedCurveLPTIBTSNG(_pt_, _curvePool_));
        (, int256 answer1, , , ) = AggregatorV3Interface(_priceFeedInAsset_).getRoundData(_roundId);
        (, int256 answer2, , , ) = AggregatorV3Interface(_priceFeedInAsset_).latestRoundData();
        assertEq(answer1, answer2, "Asset: equality before expiry fails");
        (, answer1, , , ) = AggregatorV3Interface(_priceFeedInIBT_).getRoundData(_roundId);
        (, answer2, , , ) = AggregatorV3Interface(_priceFeedInIBT_).latestRoundData();
        assertEq(answer1, answer2, "IBT: equality before expiry fails");

        skipToPTMaturity();
        (, answer1, , , ) = AggregatorV3Interface(_priceFeedInAsset_).getRoundData(_roundId);
        (, answer2, , , ) = AggregatorV3Interface(_priceFeedInAsset_).latestRoundData();
        assertEq(answer1, answer2, "Asset: equality after expiry fails");
        (, answer1, , , ) = AggregatorV3Interface(_priceFeedInIBT_).getRoundData(_roundId);
        (, answer2, , , ) = AggregatorV3Interface(_priceFeedInIBT_).latestRoundData();
        assertEq(answer1, answer2, "IBT: equality after expiry fails");
    }

    function skipToPTMaturity() internal {
        vm.warp(IPrincipalToken(_pt_).maturity());
        vm.roll(block.number + 1);
    }
}
