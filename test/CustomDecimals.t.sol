// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "forge-std/Test.sol";

import "script/00_deployAccessManager.s.sol";
import "script/01_deployRegistry.s.sol";
import "script/02_deployPrincipalTokenInstance.s.sol";
import "script/03_deployYTInstance.s.sol";
import "script/04_deployPrincipalTokenBeacon.s.sol";
import "script/05_deployYTBeacon.s.sol";
import "script/06_deployFactory.s.sol";
import "script/07_deployPrincipalToken.s.sol";
import "script/09_deployRouter.s.sol";

import "src/libraries/RayMath.sol";
import "src/router/Commands.sol";
import "src/interfaces/ICurveFactory.sol";
import "src/mocks/MockUnderlyingCustomDecimals.sol";
import "src/mocks/MockIBTCustomDecimals.sol";
import "src/mocks/MockSpectra4626Wrapper.sol";

contract CustomDecimalsLegacy is Test {
    using Math for uint256;
    using RayMath for uint256;

    // ERRORS
    error DeploymentFailed();
    error FailedToAddLiquidity();

    struct CurvePoolParams {
        uint256 A;
        uint256 gamma;
        uint256 mid_fee;
        uint256 out_fee;
        uint256 allowed_extra_profit;
        uint256 fee_gamma;
        uint256 adjustment_step;
        uint256 admin_fee;
        uint256 ma_half_time;
        uint256 initial_price;
    }

    struct ptFunctionsData {
        // data before
        uint256 assetBalBefore;
        uint256 ibtBalBefore;
        uint256 ptBalBefore;
        uint256 ytBalBefore;
        uint256 ptBalBeforeReceiver;
        uint256 ytBalBeforeReceiver;
        uint256 ibtBalPTContractBefore;
        uint256 IBTRateBefore;
        uint256 PTRateBefore;
        // data after
        uint256 assetBalAfter;
        uint256 ibtBalAfter;
        uint256 ptBalAfter;
        uint256 ytBalAfter;
        uint256 ptBalAfterReceiver;
        uint256 ytBalAfterReceiver;
        uint256 ibtBalPTContractAfter;
        uint256 IBTRateAfter;
        uint256 PTRateAfter;
        // data global
        uint256 expectedShares1;
        uint256 expectedShares2;
        uint256 assetsInIBT;
        uint256 expectedAssets1;
        uint256 expectedAssets2;
        uint256 expectedIBTs1;
        uint256 expectedIBTs2;
        uint256 expectedAssets;
        uint256 expectedIbts1;
        uint256 receivedAssets;
        uint256 expectedWrapperShares1;
        uint256 expectedWrapperShares2;
        uint256 unclaimedFees1;
        uint256 unclaimedFees2;
        uint256 redeemedFees1;
        uint256 redeemedFees2;
        uint256 totalFees;
        uint256 oldIbtRate;
        uint256 oldPtRate;
        uint256 newIbtRate;
    }

    struct ptFunctionsData2 {
        // data before
        uint256 assetBalBefore;
        uint256 ibtBalBefore;
        uint256 assetBalBeforeUser1;
        uint256 ibtBalBeforeUser1;
        uint256 ptBalBeforeUser1;
        uint256 ytBalBeforeUser1;
        uint256 assetBalBeforeUser2;
        uint256 ibtBalBeforeUser2;
        uint256 ptBalBeforeUser2;
        uint256 ytBalBeforeUser2;
        uint256 ibtBalPTContractBefore;
        uint256 IBTRateBefore;
        uint256 PTRateBefore;
        // data after
        uint256 assetBalAfter;
        uint256 ibtBalAfter;
        uint256 assetBalAfterUser1;
        uint256 ibtBalAfterUser1;
        uint256 ptBalAfterUser1;
        uint256 ytBalAfterUser1;
        uint256 assetBalAfterUser2;
        uint256 ibtBalAfterUser2;
        uint256 ptBalAfterUser2;
        uint256 ytBalAfterUser2;
        uint256 ibtBalPTContractAfter;
        uint256 IBTRateAfter;
        uint256 PTRateAfter;
        // data global
        uint256 expectedShares1;
        uint256 expectedShares2;
        uint256 assetsInIBT;
    }

    struct usersData {
        uint256 assets0;
        uint256 assets1;
        uint256 assets2;
        uint256 assets3;
        uint256 assets4;
        uint256 ibts0;
        uint256 ibts1;
        uint256 ibts2;
        uint256 ibts3;
        uint256 ibts4;
        uint256 shares0;
        uint256 shares1;
        uint256 shares2;
        uint256 shares3;
        uint256 shares4;
        uint256 yieldIBT0;
        uint256 yieldIBT1;
        uint256 yieldIBT2;
        uint256 yieldIBT3;
        uint256 yieldIBT4;
    }

    struct feesData {
        uint256 tokenizationFee;
        uint256 yieldFee;
        uint256 feeReduction;
        uint256 unclaimedFees;
        uint256 unclaimedFeesInAssets;
        uint256 redeemedFees;
    }

    struct testParametersData {
        uint8 underlyingDecimals;
        uint8 ibtDecimals;
        uint256 amount;
        uint16 ibtRateVar;
        bool isIncrease;
    }

    struct fullCycleInteractionData {
        uint256 feeReduction1;
        uint256 feeReduction2;
        uint256 feeReduction3;
        uint256 feeReduction4;
    }

    struct routerCommandsData {
        // data before
        uint256 assetBalBefore;
        uint256 ibtBalBefore;
        uint256 wrapperBalBefore;
        uint256 ptBalBefore;
        uint256 ytBalBefore;
        uint256 ibtBalPTContractBefore;
        uint256 assetBalRouterContractBefore;
        uint256 ibtBalRouterContractBefore;
        uint256 wrapperBalRouterContractBefore;
        uint256 ptBalRouterContractBefore;
        uint256 ytBalRouterContractBefore;
        // data after
        uint256 assetBalAfter;
        uint256 ibtBalAfter;
        uint256 wrapperBalAfter;
        uint256 ptBalAfter;
        uint256 ytBalAfter;
        uint256 ibtBalPTContractAfter;
        uint256 assetBalRouterContractAfter;
        uint256 ibtBalRouterContractAfter;
        uint256 wrapperBalRouterContractAfter;
        uint256 ptBalRouterContractAfter;
        uint256 ytBalRouterContractAfter;
        // data global
        uint256 assetsInIBT;
        uint256 expected1;
        uint256 expected2;
        uint256 routerPreviewRate;
    }

    struct curveLiqArbitrageData {
        uint256 baseProportion1;
        uint256 baseProportion2;
        uint256 baseProportion3;
        uint256 previewLPTReceived1;
        uint256 previewLPTReceived12;
        uint256 previewLPTReceived13;
        uint256 previewLPTReceived2;
        uint256 previewLPTReceived3;
        uint256 previewLPTReceived4;
        uint256 ibtReceived;
        uint256 ptReceived;
        uint256 lpAmount1;
        uint256 lpAmount2;
        uint256 lpAmount3;
        uint256 lpAmount4;
        uint8 underlyingDecimals;
        uint8 ibtDecimals;
    }

    address public underlying;
    address public ibt;
    address public spectra4626Wrapper;
    address public registry;
    address public factory;
    address payable public router;
    address public routerUtil;
    address public curveLiqArbitrage;
    address public pt;
    address public yt;
    address public curveFactoryAddress;
    address public curvePool;

    uint256 fork;
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    address public scriptAdmin;
    address public testUser;

    address feeCollector = 0x0000000000000000000000000000000000000FEE;
    address MOCK_ADDR_1 = 0x0000000000000000000000000000000000000aaa;
    address MOCK_ADDR_2 = 0x0000000000000000000000000000000000000bBB;
    address MOCK_ADDR_3 = 0x0000000000000000000000000000000000000CcC;
    address MOCK_ADDR_4 = 0x0000000000000000000000000000000000000ddd;

    address FULL_CYCLE_USER_1 = 0x0000000000000000000000000000000000000111;
    address FULL_CYCLE_USER_2 = 0x0000000000000000000000000000000000000222;
    address FULL_CYCLE_USER_3 = 0x0000000000000000000000000000000000000333;
    address FULL_CYCLE_USER_4 = 0x0000000000000000000000000000000000000444;

    uint8 public MIN_DECIMALS = 6;
    uint8 public MAX_DECIMALS = 18;

    uint256 public DURATION = 15724800; // 182 days
    uint256 public TOKENIZATION_FEE = 1e15;
    uint256 public YIELD_FEE = 0;
    uint256 public PT_FLASH_LOAN_FEE = 0;
    uint256 constant MAX_TOKENIZATION_FEE = 1e16;
    uint256 constant MAX_YIELD_FEE = 5e17;
    uint256 constant MAX_PT_FLASH_LOAN_FEE = 1e18;
    uint256 constant FEE_DIVISOR = 1e18;
    uint256 public NOISE_FEE = 1e13;
    uint256 public RAY_UNIT = 1e27;
    uint256 public UNIT = 1e18;
    uint256 public IBT_UNIT;
    uint256 public ASSET_UNIT;

    // Events
    event FeeReduced(address indexed pt, address indexed user, uint256 reduction);

    /**
     * @dev Function called before each test.
     */
    function setUp() public {
        fork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(fork);
        // default account for deploying scripts contracts. refer to line 35 of
        // https://github.com/foundry-rs/foundry/blob/master/evm/src/lib.rs for more details
        scriptAdmin = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
        testUser = address(this); // to reduce number of lines and repeated vm pranks

        curveFactoryAddress = 0x90f584A7AfA70ECa0cf073082Ab0Ec95e5EfE38a;
    }

    /* PRINCIPAL TOKEN TESTS */

    /**
     * @dev Test deposit and redeem with variable amounts, variable IBT rate, and 2 users.
     */
    function testDepositRedeemFuzz(
        uint8 underlyingDecimals,
        uint8 ibtDecimals,
        uint256 amount,
        uint8 _ibtRateVar,
        bool boolFuzz
    ) public {
        underlyingDecimals = uint8(
            bound(uint256(underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );

        ibtDecimals = uint8(
            bound(uint256(ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );
        uint16 ibtRateVar = uint16(bound(_ibtRateVar, 0, 15));
        _deployProtocol(
            underlyingDecimals,
            ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );
        uint256 depositAmount = uint256(bound(amount, 0, 100_000_000 * ASSET_UNIT));

        usersData memory data;

        for (uint16 i; i < 5; i++) {
            uint256 _depositAmount = depositAmount / (i + 1);

            _changeIbtRate(ibtRateVar * i, ((i % 2) == 0) ? boolFuzz : !boolFuzz);

            IERC20(underlying).approve(pt, _depositAmount * 4);
            data.shares1 = _testPTDeposit(_depositAmount, MOCK_ADDR_1);
            data.shares2 = _testPTDeposit(_depositAmount, MOCK_ADDR_2);
            data.shares3 = _testPTDeposit2(_depositAmount, MOCK_ADDR_3, MOCK_ADDR_4);
            data.shares4 = _testPTDeposit3(_depositAmount, MOCK_ADDR_4, MOCK_ADDR_3, true);

            if (data.shares1 < 100_000) {
                assertApproxEqAbs(
                    data.shares1,
                    data.shares2,
                    1,
                    "Shares for users 1 and 2 should be approximately equal"
                );
                assertApproxEqAbs(
                    data.shares1,
                    data.shares3,
                    1,
                    "Shares for users 1 and 3 should be approximately equal"
                );
                assertApproxEqAbs(
                    data.shares1,
                    data.shares4,
                    1,
                    "Shares for users 1 and 4 should be approximately equal"
                );
            } else {
                assertApproxEqRel(
                    data.shares1,
                    data.shares2,
                    1e13,
                    "Shares for users 1 and 2 should be approximately equal"
                );
                assertApproxEqRel(
                    data.shares1,
                    data.shares3,
                    1e13,
                    "Shares for users 1 and 3 should be approximately equal"
                );
                assertApproxEqRel(
                    data.shares1,
                    data.shares4,
                    1e13,
                    "Shares for users 1 and 4 should be approximately equal"
                );
            }
        }

        for (uint16 i; i < 5; i++) {
            _changeIbtRate(ibtRateVar * i, ((i % 2) == 0) ? !boolFuzz : boolFuzz);

            uint256 maxRedeem1 = IPrincipalToken(pt).maxRedeem(MOCK_ADDR_1);
            uint256 maxRedeem2 = IPrincipalToken(pt).maxRedeem(MOCK_ADDR_2);
            uint256 maxRedeem3 = IPrincipalToken(pt).maxRedeem(MOCK_ADDR_3);
            uint256 maxRedeem4 = IPrincipalToken(pt).maxRedeem(MOCK_ADDR_4);

            vm.startPrank(MOCK_ADDR_1);
            data.assets1 = _testPTRedeem(maxRedeem1 / 2, MOCK_ADDR_1);
            vm.stopPrank();

            vm.startPrank(MOCK_ADDR_2);
            data.assets2 = _testPTRedeem(maxRedeem2 / 2, MOCK_ADDR_2);
            vm.stopPrank();

            vm.startPrank(MOCK_ADDR_3);
            data.assets3 = _testPTRedeem2(maxRedeem3 / 2, MOCK_ADDR_3, true);
            vm.stopPrank();

            vm.startPrank(MOCK_ADDR_4);
            data.assets4 = _testPTRedeem2(maxRedeem4 / 2, MOCK_ADDR_4, true);
            vm.stopPrank();

            if (data.assets1 < 100_000) {
                assertApproxEqAbs(
                    data.assets1,
                    data.assets2,
                    10,
                    "Received assets for users 1 and 2 should be equal"
                );
                assertApproxEqAbs(
                    data.assets1,
                    data.assets3,
                    10,
                    "Received assets for users 1 and 3 should be equal"
                );
                assertApproxEqAbs(
                    data.assets1,
                    data.assets4,
                    10,
                    "Received assets for users 1 and 4 should be equal"
                );
            } else {
                assertApproxEqRel(
                    data.assets1,
                    data.assets2,
                    1e13,
                    "Received assets for users 1 and 2 should be equal"
                );
                assertApproxEqRel(
                    data.assets1,
                    data.assets3,
                    1e13,
                    "Received assets for users 1 and 3 should be equal"
                );
                assertApproxEqRel(
                    data.assets1,
                    data.assets4,
                    1e13,
                    "Received assets for users 1 and 4 should be equal"
                );
            }
        }

        if (boolFuzz) {
            _increaseTimeToExpiry();
        }

        vm.startPrank(MOCK_ADDR_1);
        _testPTMaxRedeemAndClaimYield(MOCK_ADDR_1);
        vm.stopPrank();

        vm.startPrank(MOCK_ADDR_2);
        _testPTMaxRedeemAndClaimYield(MOCK_ADDR_2);
        vm.stopPrank();
    }

    /**
     * @dev Test depositIBT and redeemForIBT with variable amounts, variable IBT rate, and 2 users.
     */
    function testDepositRedeemIBTFuzz(
        uint8 underlyingDecimals,
        uint8 ibtDecimals,
        uint256 amount,
        uint8 _ibtRateVar,
        bool boolFuzz
    ) public {
        underlyingDecimals = uint8(
            bound(uint256(underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        ibtDecimals = uint8(
            bound(uint256(ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );
        uint16 ibtRateVar = uint16(bound(_ibtRateVar, 0, 15));
        _deployProtocol(
            underlyingDecimals,
            ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );
        uint256 depositAmount = uint256(bound(amount, 0, 100_000_000 * ASSET_UNIT));

        usersData memory data;

        for (uint16 i; i < 5; i++) {
            uint256 _depositAmount = depositAmount / (i + 1);

            _changeIbtRate(ibtRateVar * i, ((i % 2) == 0) ? boolFuzz : !boolFuzz);

            // deposit assets in IBT
            IERC20(underlying).approve(ibt, _depositAmount * 4);
            data.ibts1 = IERC4626(ibt).deposit(_depositAmount, address(this));
            data.ibts2 = IERC4626(ibt).deposit(_depositAmount, address(this));
            data.ibts3 = IERC4626(ibt).deposit(_depositAmount, address(this));
            data.ibts4 = IERC4626(ibt).deposit(_depositAmount, address(this));
            IERC4626(ibt).approve(pt, data.ibts1 + data.ibts2 + data.ibts3 + data.ibts4);

            data.shares1 = _testPTDepositIBT(data.ibts1, MOCK_ADDR_1);
            data.shares2 = _testPTDepositIBT(data.ibts1, MOCK_ADDR_2);
            data.shares3 = _testPTDepositIBT2(data.ibts3, MOCK_ADDR_3, MOCK_ADDR_4);
            data.shares4 = _testPTDepositIBT3(data.ibts3, MOCK_ADDR_4, MOCK_ADDR_3, true);

            if (data.shares1 < 100_000) {
                assertApproxEqAbs(
                    data.shares1,
                    data.shares2,
                    1,
                    "Shares for users 1 and 2 should be approximately equal"
                );
                assertApproxEqAbs(
                    data.shares1,
                    data.shares3,
                    1,
                    "Shares for users 1 and 3 should be approximately equal"
                );
                assertApproxEqAbs(
                    data.shares1,
                    data.shares4,
                    1,
                    "Shares for users 1 and 4 should be approximately equal"
                );
            } else {
                assertApproxEqRel(
                    data.shares1,
                    data.shares2,
                    1e13,
                    "Shares for users 1 and 2 should be approximately equal"
                );
                assertApproxEqRel(
                    data.shares1,
                    data.shares3,
                    1e13,
                    "Shares for users 1 and 3 should be approximately equal"
                );
                assertApproxEqRel(
                    data.shares1,
                    data.shares4,
                    1e13,
                    "Shares for users 1 and 4 should be approximately equal"
                );
            }
        }

        for (uint16 i; i < 5; i++) {
            _changeIbtRate(ibtRateVar * i, ((i % 2) == 0) ? !boolFuzz : boolFuzz);

            uint256 maxRedeem1 = IPrincipalToken(pt).maxRedeem(MOCK_ADDR_1);
            uint256 maxRedeem2 = IPrincipalToken(pt).maxRedeem(MOCK_ADDR_2);
            uint256 maxRedeem3 = IPrincipalToken(pt).maxRedeem(MOCK_ADDR_3);
            uint256 maxRedeem4 = IPrincipalToken(pt).maxRedeem(MOCK_ADDR_4);

            vm.startPrank(MOCK_ADDR_1);
            data.ibts1 = _testPTRedeemForIBT(maxRedeem1 / 2, MOCK_ADDR_1);
            vm.stopPrank();

            vm.startPrank(MOCK_ADDR_2);
            data.ibts2 = _testPTRedeemForIBT(maxRedeem2 / 2, MOCK_ADDR_2);
            vm.stopPrank();

            vm.startPrank(MOCK_ADDR_3);
            data.ibts3 = _testPTRedeemForIBT(maxRedeem3 / 2, MOCK_ADDR_3);
            vm.stopPrank();

            vm.startPrank(MOCK_ADDR_4);
            data.ibts4 = _testPTRedeemForIBT(maxRedeem4 / 2, MOCK_ADDR_4);
            vm.stopPrank();

            if (data.ibts1 < 100_000) {
                assertApproxEqAbs(
                    data.ibts1,
                    data.ibts2,
                    10,
                    "Received assets for users 1 and 2 should be equal"
                );
                assertApproxEqAbs(
                    data.ibts1,
                    data.ibts3,
                    10,
                    "Received assets for users 1 and 3 should be equal"
                );
                assertApproxEqAbs(
                    data.ibts1,
                    data.ibts4,
                    10,
                    "Received assets for users 1 and 4 should be equal"
                );
            } else {
                assertApproxEqRel(
                    data.ibts1,
                    data.ibts2,
                    1e13,
                    "Received assets for users 1 and 2 should be equal"
                );
                assertApproxEqRel(
                    data.ibts1,
                    data.ibts3,
                    1e13,
                    "Received assets for users 1 and 3 should be equal"
                );
                assertApproxEqRel(
                    data.ibts1,
                    data.ibts4,
                    1e13,
                    "Received assets for users 1 and 4 should be equal"
                );
            }
        }

        if (boolFuzz) {
            _increaseTimeToExpiry();
        }

        vm.startPrank(MOCK_ADDR_1);
        _testPTMaxRedeemAndClaimYieldInIBT(MOCK_ADDR_1);
        vm.stopPrank();

        vm.startPrank(MOCK_ADDR_2);
        _testPTMaxRedeemAndClaimYieldInIBT(MOCK_ADDR_2);
        vm.stopPrank();
    }

    /**
     * @dev Test withdraw with variable amounts, variable IBT rate, and 2 users.
     */
    function testDepositWithdrawFuzz(
        uint8 underlyingDecimals,
        uint8 ibtDecimals,
        uint256 amount,
        uint8 _ibtRateVar,
        bool boolFuzz
    ) public {
        underlyingDecimals = uint8(
            bound(uint256(underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        ibtDecimals = uint8(
            bound(uint256(ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );
        uint16 ibtRateVar = uint16(bound(_ibtRateVar, 0, 10));
        _deployProtocol(
            underlyingDecimals,
            ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );
        uint256 depositAmount = uint256(bound(amount, 0, 100_000_000 * ASSET_UNIT));

        usersData memory data;

        for (uint16 i; i < 5; i++) {
            uint256 _depositAmount = depositAmount / (i + 1);

            _changeIbtRate(ibtRateVar * i, ((i % 2) == 0) ? boolFuzz : !boolFuzz);

            IERC20(underlying).approve(pt, _depositAmount * 4);
            data.shares1 = _testPTDeposit(_depositAmount, MOCK_ADDR_1);
            data.shares2 = _testPTDeposit(_depositAmount, MOCK_ADDR_2);
            data.shares3 = _testPTDeposit2(_depositAmount, MOCK_ADDR_3, MOCK_ADDR_4);
            data.shares4 = _testPTDeposit3(_depositAmount, MOCK_ADDR_3, MOCK_ADDR_4, true);
        }

        uint256 maxWithdraw1;
        uint256 maxWithdraw2;
        uint256 maxWithdraw3;
        uint256 maxWithdraw4;
        for (uint16 i; i < 5; i++) {
            _changeIbtRate(ibtRateVar * i, ((i % 2) == 0) ? !boolFuzz : boolFuzz);

            maxWithdraw1 = IPrincipalToken(pt).maxWithdraw(MOCK_ADDR_1);
            maxWithdraw2 = IPrincipalToken(pt).maxWithdraw(MOCK_ADDR_2);
            maxWithdraw3 = IPrincipalToken(pt).maxWithdraw(MOCK_ADDR_3);
            maxWithdraw4 = IPrincipalToken(pt).maxWithdraw(MOCK_ADDR_4);

            vm.startPrank(MOCK_ADDR_1);
            data.shares1 = _testPTWithdraw(maxWithdraw1 / 2, MOCK_ADDR_1);
            vm.stopPrank();

            vm.startPrank(MOCK_ADDR_2);
            data.shares2 = _testPTWithdraw(maxWithdraw2 / 2, MOCK_ADDR_2);
            vm.stopPrank();

            vm.startPrank(MOCK_ADDR_3);
            data.shares3 = _testPTWithdraw(maxWithdraw3 / 2, MOCK_ADDR_3);
            vm.stopPrank();

            vm.startPrank(MOCK_ADDR_4);
            data.shares4 = _testPTWithdraw(maxWithdraw4 / 2, MOCK_ADDR_4);
            vm.stopPrank();

            if (data.shares1 < 100_000) {
                assertApproxEqAbs(
                    data.shares1,
                    data.shares2,
                    100,
                    "Burnt shares for users 1 and 2 should be equal"
                );
                assertApproxEqAbs(0, data.shares3, 10, "Burnt shares for user 3 should be 0");
                assertApproxEqAbs(0, data.shares4, 10, "Burnt shares for user 4 should be 0");
            } else {
                assertApproxEqRel(
                    data.shares1,
                    data.shares2,
                    1e15,
                    "Burnt shares for users 1 and 2 should be equal"
                );
                assertApproxEqRel(0, data.shares3, 1e13, "Burnt shares for user 3 should be 0");
                assertApproxEqRel(0, data.shares4, 1e13, "Burnt shares for user 4 should be 0");
            }
        }

        if (boolFuzz) {
            _increaseTimeToExpiry();
        }

        vm.startPrank(MOCK_ADDR_1);
        _testPTMaxRedeemAndClaimYield(MOCK_ADDR_1);
        vm.stopPrank();

        vm.startPrank(MOCK_ADDR_2);
        _testPTMaxRedeemAndClaimYield(MOCK_ADDR_2);
        vm.stopPrank();

        vm.startPrank(MOCK_ADDR_3);
        _testPTMaxRedeemAndClaimYield(MOCK_ADDR_3);
        vm.stopPrank();

        vm.startPrank(MOCK_ADDR_4);
        _testPTMaxRedeemAndClaimYield(MOCK_ADDR_4);
        vm.stopPrank();
    }

    /**
     * @dev Test withdrawIBT with variable amounts, variable IBT rate, and 2 users.
     */
    function testDepositWithdrawIBTFuzz(
        uint8 underlyingDecimals,
        uint8 ibtDecimals,
        uint256 amount,
        uint8 _ibtRateVar,
        bool boolFuzz
    ) public {
        underlyingDecimals = uint8(
            bound(uint256(underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        ibtDecimals = uint8(
            bound(uint256(ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );
        uint16 ibtRateVar = uint16(bound(_ibtRateVar, 0, 10));
        _deployProtocol(
            underlyingDecimals,
            ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );
        uint256 depositAmount = uint256(bound(amount, 0, 100_000_000 * ASSET_UNIT));

        usersData memory data;

        for (uint16 i; i < 5; i++) {
            uint256 _depositAmount = depositAmount / (i + 1);

            _changeIbtRate(ibtRateVar * i, ((i % 2) == 0) ? boolFuzz : !boolFuzz);

            // deposit assets in IBT
            IERC20(underlying).approve(ibt, _depositAmount * 4);
            data.ibts1 = IERC4626(ibt).deposit(_depositAmount, address(this));
            data.ibts2 = IERC4626(ibt).deposit(_depositAmount, address(this));
            data.ibts3 = IERC4626(ibt).deposit(_depositAmount, address(this));
            data.ibts4 = IERC4626(ibt).deposit(_depositAmount, address(this));
            IERC4626(ibt).approve(pt, data.ibts1 + data.ibts2 + data.ibts3 + data.ibts4);

            data.shares1 = _testPTDepositIBT(data.ibts1, MOCK_ADDR_1);
            data.shares2 = _testPTDepositIBT(data.ibts1, MOCK_ADDR_2);
            data.shares3 = _testPTDepositIBT2(data.ibts3, MOCK_ADDR_3, MOCK_ADDR_4);
            data.shares4 = _testPTDepositIBT3(data.ibts3, MOCK_ADDR_3, MOCK_ADDR_4, true);
        }

        uint256 maxWithdrawIBT1;
        uint256 maxWithdrawIBT2;
        uint256 maxWithdrawIBT3;
        uint256 maxWithdrawIBT4;
        for (uint16 i; i < 5; i++) {
            _changeIbtRate(ibtRateVar * i, ((i % 2) == 0) ? !boolFuzz : boolFuzz);

            maxWithdrawIBT1 = IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_1);
            maxWithdrawIBT2 = IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_2);
            maxWithdrawIBT3 = IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_3);
            maxWithdrawIBT4 = IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_4);

            vm.startPrank(MOCK_ADDR_1);
            data.shares1 = _testPTWithdrawIBT(maxWithdrawIBT1 / 2, MOCK_ADDR_1);
            vm.stopPrank();

            vm.startPrank(MOCK_ADDR_2);
            data.shares2 = _testPTWithdrawIBT(maxWithdrawIBT2 / 2, MOCK_ADDR_2);
            vm.stopPrank();

            vm.startPrank(MOCK_ADDR_3);
            data.shares3 = _testPTWithdrawIBT(maxWithdrawIBT3 / 2, MOCK_ADDR_3);
            vm.stopPrank();

            vm.startPrank(MOCK_ADDR_4);
            data.shares4 = _testPTWithdrawIBT(maxWithdrawIBT4 / 2, MOCK_ADDR_4);
            vm.stopPrank();

            if (data.shares1 < 100_000) {
                assertApproxEqAbs(
                    data.shares1,
                    data.shares2,
                    10,
                    "Burnt shares for users 1 and 2 should be equal"
                );
                assertApproxEqAbs(0, data.shares3, 10, "Burnt shares for user 3 should be 0");
                assertApproxEqAbs(0, data.shares4, 10, "Burnt shares for user 4 should be 0");
            } else {
                assertApproxEqRel(
                    data.shares1,
                    data.shares2,
                    1e13,
                    "Burnt shares for users 1 and 2 should be equal"
                );
                assertApproxEqRel(0, data.shares3, 1e13, "Burnt shares for user 3 should be 0");
                assertApproxEqRel(0, data.shares4, 1e13, "Burnt shares for user 4 should be 0");
            }
        }

        if (boolFuzz) {
            _increaseTimeToExpiry();
        }

        vm.startPrank(MOCK_ADDR_1);
        _testPTMaxRedeemAndClaimYieldInIBT(MOCK_ADDR_1);
        vm.stopPrank();

        vm.startPrank(MOCK_ADDR_2);
        _testPTMaxRedeemAndClaimYieldInIBT(MOCK_ADDR_2);
        vm.stopPrank();

        vm.startPrank(MOCK_ADDR_3);
        _testPTMaxRedeemAndClaimYieldInIBT(MOCK_ADDR_3);
        vm.stopPrank();

        vm.startPrank(MOCK_ADDR_4);
        _testPTMaxRedeemAndClaimYieldInIBT(MOCK_ADDR_4);
        vm.stopPrank();
    }

    function testMaxWithdrawFuzz(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint256 _amount
    ) public {
        uint8 underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        uint8 ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );
        _deployProtocol(
            underlyingDecimals,
            ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );
        uint256 depositAmount = uint256(bound(_amount, 0, 100_000_000 * ASSET_UNIT));

        // deposit assets in PT
        IERC20(underlying).approve(pt, depositAmount);
        uint256 receivedShares = _testPTDeposit(depositAmount, address(this));

        uint256 maxWithdraw = IPrincipalToken(pt).maxWithdraw(address(this));

        if (receivedShares != 0) {
            assertApproxEqAbs(
                maxWithdraw,
                _amountMinusFee(depositAmount, IRegistry(registry).getTokenizationFee()),
                _getPrecision(ASSET_UNIT)
            );
        }

        // withdraw max assets
        _testPTWithdraw(maxWithdraw, address(this));
    }

    function testMaxWithdrawIBTFuzz(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint256 _amount
    ) public {
        uint8 underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        uint8 ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );
        _deployProtocol(
            underlyingDecimals,
            ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );
        uint256 depositAmount = uint256(bound(_amount, 0, 100_000_000 * ASSET_UNIT));

        // deposit assets in IBT
        IERC20(underlying).approve(ibt, depositAmount);
        uint256 amountIbt = IERC4626(ibt).deposit(depositAmount, address(this));

        // deposit IBTs in PT
        IERC4626(ibt).approve(pt, amountIbt);
        uint256 receivedShares = _testPTDepositIBT(amountIbt, address(this));

        uint256 maxWithdrawIBT = IPrincipalToken(pt).maxWithdrawIBT(address(this));

        if (receivedShares != 0) {
            assertApproxEqAbs(
                maxWithdrawIBT,
                _amountMinusFee(amountIbt, IRegistry(registry).getTokenizationFee()),
                _getPrecision(ASSET_UNIT)
            );
        }

        // withdraw max assets
        _testPTWithdrawIBT(maxWithdrawIBT, address(this));
    }

    function testClaimYieldFuzz(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint256 _amount,
        uint16 _ibtRateVar,
        bool isIncrease
    ) public {
        uint8 underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(18), uint256(MAX_DECIMALS))
        );
        uint8 ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );
        _deployProtocol(
            underlyingDecimals,
            ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );
        uint256 depositAmount = uint256(
            bound(_amount, 0, 100_000_000_000_000_000_000 * ASSET_UNIT)
        );
        uint16 ibtRateVar = uint16(bound(_ibtRateVar, 0, 50));

        IERC20(underlying).approve(pt, 5 * depositAmount);

        for (uint i; i < 5; i++) {
            _changeIbtRate(ibtRateVar, ((i % 2) == 0) ? isIncrease : !isIncrease);
            _testPTDeposit(depositAmount, address(this));
        }

        _changeIbtRate(ibtRateVar, isIncrease);

        uint256 maxRedeem = IPrincipalToken(pt).maxRedeem(address(this));
        // redeem part of PT shares
        uint256 receivedAssets = _testPTRedeem(maxRedeem / 3, address(this));

        for (uint i; i < 4; i++) {
            vm.warp(block.timestamp + (DURATION / 5));

            uint256 ibtBalPTContractBefore = IERC4626(ibt).balanceOf(address(pt));
            uint256 claimedYieldInIBT = IPrincipalToken(pt).claimYieldInIBT(address(this), 0);
            uint256 ibtBalPTContractAfter = IERC4626(ibt).balanceOf(address(pt));
            assertEq(
                ibtBalPTContractBefore - ibtBalPTContractAfter,
                claimedYieldInIBT,
                "Received IBT Yield is wrong"
            );
        }

        _increaseTimeToExpiry();

        uint256 maxRedeemExpiry = IPrincipalToken(pt).maxRedeem(address(this));

        if (receivedAssets != 0) {
            assertEq(maxRedeemExpiry, maxRedeem - (maxRedeem / 3), "maxRedeem is wrong");
        }

        // redeem remaining PT shares and claim yield
        _testPTMaxRedeemAndClaimYield(address(this));
    }

    function testRatesAfterExpiryFuzz(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint256 _amount,
        uint16 _ibtRateVar,
        bool isIncrease,
        bool changeRateBeforeExpiry
    ) public {
        usersData memory data;
        uint8 underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(18), uint256(MAX_DECIMALS))
        );
        uint8 ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );
        uint256 depositAmount = uint256(
            bound(_amount, 0, 100_000_000_000_000_000_000 * ASSET_UNIT)
        );
        uint16 ibtRateVar = uint16(bound(_ibtRateVar, 0, 50));

        _deployProtocolIBTRateFuzzed(
            underlyingDecimals,
            ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE,
            ibtRateVar,
            isIncrease
        );

        IERC20(underlying).approve(pt, 5 * depositAmount);

        for (uint i; i < 5; i++) {
            _changeIbtRate(ibtRateVar, ((i % 2) == 0) ? isIncrease : !isIncrease);
            IERC20(underlying).approve(pt, 4 * depositAmount);
            _testPTDeposit(depositAmount, MOCK_ADDR_1);
            _testPTDeposit(depositAmount, MOCK_ADDR_2);
            _testPTDeposit(depositAmount, MOCK_ADDR_3);
            _testPTDeposit(depositAmount, MOCK_ADDR_4);
        }

        bool sharesReceivedNull = IPrincipalToken(pt).previewDeposit(depositAmount) == 0;
        uint256 ptRate0;
        uint256 ibtRate0;
        uint256 ptRate;
        uint256 ibtRate;
        if (changeRateBeforeExpiry) {
            // get PT Rate and IBT Rate
            ptRate0 = IPrincipalToken(pt).getPTRate();
            ibtRate0 = IPrincipalToken(pt).getIBTRate();

            _changeIbtRate(ibtRateVar, isIncrease);

            // get PT Rate and IBT Rate
            ptRate = IPrincipalToken(pt).getPTRate();
            ibtRate = IPrincipalToken(pt).getIBTRate();

            if (ibtRateVar != 0 && !sharesReceivedNull) {
                if (isIncrease) {
                    assertGe(ibtRate, ibtRate0, "yield increased yet ibt rate did not");
                    assertEq(ptRate0, ptRate, "yield increased yet pt rate changed");
                } else {
                    assertGe(ibtRate0, ibtRate, "yield decreased yet ibt rate did not");
                    assertGe(ptRate0, ptRate, "yield increased yet pt did not");
                }
            } else if (ibtRateVar != 0 && sharesReceivedNull) {
                if (isIncrease) {
                    assertGe(ibtRate, ibtRate0, "yield increased yet ibt rate did not");
                    // here only the preview of the pt rate "increases"
                    // it is made possible since no update of the rates happened in the protocol
                    assertGe(
                        ptRate,
                        ptRate0,
                        "rates have never been stored since init, yield increased so pt rate should also increase"
                    );
                    assertLe(ptRate, RAY_UNIT, "pt rate should never be more than ray unit");
                } else {
                    assertGe(ibtRate0, ibtRate, "yield decreased yet ibt rate did not");
                    assertGe(ptRate0, ptRate, "yield increased yet pt did not");
                }
            }
        }

        _increaseTimeToExpiry();

        // get PT Rate and IBT Rate
        ptRate0 = IPrincipalToken(pt).getPTRate();
        ibtRate0 = IPrincipalToken(pt).getIBTRate();

        _changeIbtRate(ibtRateVar, isIncrease);

        // get PT Rate and IBT Rate
        ptRate = IPrincipalToken(pt).getPTRate();
        ibtRate = IPrincipalToken(pt).getIBTRate();

        if (ibtRateVar != 0 && !sharesReceivedNull) {
            if (isIncrease) {
                assertGe(ibtRate, ibtRate0, "yield increased yet ibt rate did not");
                assertEq(ptRate0, ptRate, "yield increased yet pt rate changed");
            } else {
                assertGe(ibtRate0, ibtRate, "yield decreased yet ibt rate did not");
                assertGe(ptRate0, ptRate, "yield increased yet pt did not");
            }
        } else if (ibtRateVar != 0 && sharesReceivedNull) {
            if (isIncrease) {
                assertGe(ibtRate, ibtRate0, "yield increased yet ibt rate did not");
                // here only the preview of the pt rate "increases"
                // it is made possible since no update of the rates happened in the protocol
                assertGe(
                    ptRate,
                    ptRate0,
                    "rates have never been stored since init, yield increased so pt rate should also increase"
                );
                assertLe(ptRate, RAY_UNIT, "pt rate should never be more than ray unit");
            } else {
                assertGe(ibtRate0, ibtRate, "yield decreased yet ibt rate did not");
                assertGe(ptRate0, ptRate, "yield increased yet pt did not");
            }
        }

        // First interaction
        vm.prank(MOCK_ADDR_1);
        uint256 claimedYield = IPrincipalToken(pt).claimYield(MOCK_ADDR_1, 0);

        assertEq(ptRate, IPrincipalToken(pt).getPTRate());
        assertEq(ibtRate, IPrincipalToken(pt).getIBTRate());

        data.ibts1 = IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_1);
        data.ibts2 = IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_2);
        data.ibts3 = IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_3);
        data.ibts4 = IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_4);

        for (uint i; i < 5; i++) {
            _changeIbtRate(ibtRateVar, ((i % 2) == 0) ? isIncrease : !isIncrease);
        }

        assertEq(data.ibts1, IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_1));
        assertEq(data.ibts2, IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_2));
        assertEq(data.ibts3, IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_3));
        assertEq(data.ibts4, IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_4));
        assertEq(ptRate, IPrincipalToken(pt).getPTRate());
        assertEq(ibtRate, IPrincipalToken(pt).getIBTRate());

        assertEq(data.ibts1, IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_1));
        assertEq(data.ibts2, IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_2));
        assertEq(data.ibts3, IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_3));
        assertEq(data.ibts4, IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_4));
        assertEq(ptRate, IPrincipalToken(pt).getPTRate());
        assertEq(ibtRate, IPrincipalToken(pt).getIBTRate());

        vm.startPrank(MOCK_ADDR_3);
        IERC20(pt).transfer(MOCK_ADDR_1, IERC20(pt).balanceOf(MOCK_ADDR_3));
        vm.stopPrank();

        // MOCK_ADDR_3 sent all its PT to MOCK_ADDR_1 so we adjust the expected amounts
        assertApproxEqAbs(
            data.ibts1 + data.ibts3,
            IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_1),
            1
        );
        assertEq(data.ibts2, IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_2));
        assertEq(0, IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_3));
        assertEq(data.ibts4, IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_4));
        // We reset for the remaining of the operations these amounts should never change.
        // The IBT amount remain constant
        data.ibts1 = IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_1);
        data.ibts2 = IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_2);
        data.ibts3 = IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_3);
        data.ibts4 = IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_4);

        assertEq(ptRate, IPrincipalToken(pt).getPTRate());
        assertEq(ibtRate, IPrincipalToken(pt).getIBTRate());

        vm.prank(MOCK_ADDR_2);
        claimedYield = IPrincipalToken(pt).claimYieldInIBT(MOCK_ADDR_2, 0);

        assertEq(data.ibts1, IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_1));
        assertEq(data.ibts2, IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_2));
        assertEq(data.ibts3, IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_3));
        assertEq(data.ibts4, IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_4));
        assertEq(ptRate, IPrincipalToken(pt).getPTRate());
        assertEq(ibtRate, IPrincipalToken(pt).getIBTRate());

        vm.startPrank(MOCK_ADDR_1);
        uint256 maxRedeem = IPrincipalToken(pt).maxRedeem(MOCK_ADDR_1);
        _testPTRedeem(maxRedeem, MOCK_ADDR_1);
        vm.stopPrank();

        assertEq(data.ibts2, IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_2));
        assertEq(data.ibts3, IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_3));
        assertEq(data.ibts4, IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_4));
        assertEq(ptRate, IPrincipalToken(pt).getPTRate());
        assertEq(ibtRate, IPrincipalToken(pt).getIBTRate());

        vm.startPrank(MOCK_ADDR_2);
        uint256 maxWithdraw = IPrincipalToken(pt).maxWithdraw(MOCK_ADDR_2);
        _testPTWithdraw(maxWithdraw, MOCK_ADDR_2);
        vm.stopPrank();

        assertEq(data.ibts3, IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_3));
        assertEq(data.ibts4, IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_4));
        assertEq(ptRate, IPrincipalToken(pt).getPTRate());
        assertEq(ibtRate, IPrincipalToken(pt).getIBTRate());

        vm.startPrank(MOCK_ADDR_3);
        maxWithdraw = IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_3);
        _testPTWithdrawIBT(maxWithdraw, MOCK_ADDR_3);
        vm.stopPrank();

        assertEq(data.ibts4, IPrincipalToken(pt).maxWithdrawIBT(MOCK_ADDR_4));
        assertEq(ptRate, IPrincipalToken(pt).getPTRate());
        assertEq(ibtRate, IPrincipalToken(pt).getIBTRate());

        vm.startPrank(MOCK_ADDR_4);
        maxRedeem = IPrincipalToken(pt).maxRedeem(MOCK_ADDR_4);
        _testPTRedeemForIBT(maxRedeem, MOCK_ADDR_4);
        vm.stopPrank();

        assertEq(ptRate, IPrincipalToken(pt).getPTRate());
        assertEq(ibtRate, IPrincipalToken(pt).getIBTRate());
    }

    function testPTRedeemMaxAndClaimYieldFuzz(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint256 _amount,
        uint16 _ibtRateVar,
        uint16 _ibtRateVar2,
        bool isIncrease
    ) public {
        uint8 underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        uint8 ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );
        uint16 ibtRateVar = uint16(bound(_ibtRateVar, 0, 50));
        uint16 ibtRateVar2 = uint16(bound(_ibtRateVar2, 0, 50));
        _deployProtocol(
            underlyingDecimals,
            ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );
        uint256 depositAmount = uint256(bound(_amount, 10, 100_000_000 * ASSET_UNIT));

        usersData memory data;

        IERC20(underlying).approve(pt, 4 * depositAmount);
        data.shares0 = _testPTDeposit(depositAmount, address(this));
        data.shares1 = _testPTDeposit(depositAmount, MOCK_ADDR_1);
        data.shares2 = _testPTDeposit(depositAmount, MOCK_ADDR_2);
        data.shares3 = _testPTDeposit(depositAmount, MOCK_ADDR_3);

        // redeem max + claim yield for user 0
        data.yieldIBT0 = IPrincipalToken(pt).getCurrentYieldOfUserInIBT(address(this));
        data.ibts0 = _testPTMaxRedeemAndClaimYieldInIBT(address(this));
        assertEq(data.yieldIBT0, 0, "Yield for user 0 should be 0");

        // user 3 transfers all his YTs to user 4
        vm.startPrank(MOCK_ADDR_3);
        IERC20(yt).transfer(MOCK_ADDR_4, data.shares3);
        vm.stopPrank();

        _changeIbtRate(ibtRateVar, isIncrease);

        // increase time to expiry
        _increaseTimeToExpiry();

        uint256 maxRedeem2 = IPrincipalToken(pt).maxRedeem(MOCK_ADDR_2);

        data.yieldIBT1 = IPrincipalToken(pt).getCurrentYieldOfUserInIBT(MOCK_ADDR_1);
        data.yieldIBT2 = IPrincipalToken(pt).getCurrentYieldOfUserInIBT(MOCK_ADDR_2);

        if (isIncrease) {
            uint256 expectedYield2 = _amountMinusFee(
                _amountMinusFee(depositAmount, TOKENIZATION_FEE).mulDiv(ibtRateVar, 100),
                YIELD_FEE
            );
            uint256 actualYield2 = IERC4626(ibt).previewRedeem(data.yieldIBT2);
            if (depositAmount < ASSET_UNIT) {
                assertApproxEqAbs(expectedYield2, actualYield2, 1000, "Yield for user 2 is wrong");
            } else {
                assertApproxEqRel(expectedYield2, actualYield2, 1e15, "Yield for user 2 is wrong");
            }
        }

        // redeem max + claim yield for user 1
        vm.startPrank(MOCK_ADDR_1);
        data.ibts1 = _testPTMaxRedeemAndClaimYieldInIBT(MOCK_ADDR_1);
        vm.stopPrank();

        // redeem max for user 2
        vm.startPrank(MOCK_ADDR_2);
        data.ibts2 = _testPTRedeemForIBT(maxRedeem2, MOCK_ADDR_2);
        vm.stopPrank();

        assertEq(data.yieldIBT1, data.yieldIBT2, "Yield for user 1 and user 2 should be the same");

        if (isIncrease) {
            assertApproxEqAbs(
                data.ibts1,
                data.ibts2 + data.yieldIBT2,
                10,
                "User 1 and user 2 should be able to receive the same amount of IBT"
            );

            vm.startPrank(MOCK_ADDR_2);
            data.ibts2 += _testPTMaxRedeemAndClaimYieldInIBT(MOCK_ADDR_2);
            vm.stopPrank();
        } else {
            assertEq(data.yieldIBT1, 0, "Yield for user 1 and 2 should be 0");
        }

        assertApproxEqAbs(
            data.ibts1,
            data.ibts2,
            10,
            "User 1 and user 2 should have received the same amount of IBT"
        );

        _changeIbtRate(ibtRateVar2, ibtRateVar2 % 2 == 0);

        data.yieldIBT4 = IPrincipalToken(pt).getCurrentYieldOfUserInIBT(MOCK_ADDR_4);
        vm.startPrank(MOCK_ADDR_4);
        data.ibts4 = _testPTMaxRedeemAndClaimYieldInIBT(MOCK_ADDR_4);
        vm.stopPrank();
        assertEq(data.yieldIBT4, data.ibts4, "user 4 should have received his yield only");
    }

    function testPTTransferAndClaimYieldFuzz(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint256 _amount,
        uint16 _ibtRateVar,
        bool isIncrease
    ) public {
        uint8 underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        uint8 ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );
        uint16 ibtRateVar = uint16(bound(_ibtRateVar, 1, 50));
        _deployProtocol(
            underlyingDecimals,
            ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );
        uint256 depositAmount = uint256(bound(_amount, 100, 100_000_000 * ASSET_UNIT));

        usersData memory data;

        IERC20(underlying).approve(pt, depositAmount);
        data.shares0 = _testPTDeposit(depositAmount, MOCK_ADDR_3);

        // transfer the pts to user 1
        vm.prank(MOCK_ADDR_3);
        IERC20(pt).transfer(MOCK_ADDR_4, data.shares0);

        _changeIbtRate(ibtRateVar, isIncrease);

        // increase time to expiry
        _increaseTimeToExpiry();

        vm.startPrank(MOCK_ADDR_3);
        data.assets0 = _testPTMaxRedeemAndClaimYield(MOCK_ADDR_3);
        vm.stopPrank();

        if (isIncrease) {
            if (data.assets0 < ASSET_UNIT) {
                assertApproxEqAbs(
                    data.assets0,
                    _amountMinusFee(
                        _amountMinusFee(depositAmount, TOKENIZATION_FEE).mulDiv(ibtRateVar, 100),
                        YIELD_FEE
                    ),
                    1000,
                    "Yield for user 3 is wrong"
                );
            } else {
                assertApproxEqRel(
                    data.assets0,
                    _amountMinusFee(
                        _amountMinusFee(depositAmount, TOKENIZATION_FEE).mulDiv(ibtRateVar, 100),
                        YIELD_FEE
                    ),
                    1e14,
                    "Yield for user 3 is wrong"
                );
            }
        } else {
            assertEq(
                data.assets0,
                0,
                "Fees claimed should be 0 since only negative yield happened"
            );
        }
        if (data.assets0 == 0) {
            assertApproxEqAbs(
                IERC4626(ibt).previewRedeem(
                    IPrincipalToken(pt).getCurrentYieldOfUserInIBT(MOCK_ADDR_3)
                ),
                0,
                1000,
                "Yield for user 3 should be 0"
            );
        } else {
            assertEq(
                IPrincipalToken(pt).getCurrentYieldOfUserInIBT(MOCK_ADDR_3),
                0,
                "Yield for user 3 should be 0"
            );
        }

        assertEq(
            IPrincipalToken(pt).getCurrentYieldOfUserInIBT(MOCK_ADDR_4),
            0,
            "Yield for user 4 should be 0"
        );
        assertEq(
            IPrincipalToken(pt).maxRedeem(MOCK_ADDR_4),
            data.shares0,
            "MaxRedeem for user 1 is wrong"
        );

        uint256 expectedRedeemedAssets = IPrincipalToken(pt).previewRedeem(
            IPrincipalToken(pt).maxRedeem(MOCK_ADDR_4)
        );
        vm.startPrank(MOCK_ADDR_4);
        data.assets1 = _testPTMaxRedeemAndClaimYield(MOCK_ADDR_4);
        vm.stopPrank();
        assertApproxEqAbs(
            data.assets1,
            expectedRedeemedAssets,
            100,
            "redeemed assets is different than expected 1"
        );
        if (isIncrease) {
            if (depositAmount < ASSET_UNIT) {
                assertApproxEqAbs(
                    data.assets1,
                    _amountMinusFee(depositAmount, TOKENIZATION_FEE),
                    1000,
                    "redeemed assets is different than expected 2"
                );
            } else {
                assertApproxEqRel(
                    data.assets1,
                    _amountMinusFee(depositAmount, TOKENIZATION_FEE),
                    1e14,
                    "redeemed assets is different than expected 2"
                );
            }
        } else {
            if (depositAmount < ASSET_UNIT) {
                assertApproxEqAbs(
                    data.assets1,
                    (_amountMinusFee(depositAmount, TOKENIZATION_FEE) * (100 - ibtRateVar)) / 100,
                    1000,
                    "redeemed assets is different than expected 2"
                );
            } else {
                assertApproxEqRel(
                    data.assets1,
                    (_amountMinusFee(depositAmount, TOKENIZATION_FEE) * (100 - ibtRateVar)) / 100,
                    1e14,
                    "redeemed assets is different than expected 2"
                );
            }
        }
    }

    function testPTYieldConsistencyFuzz(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint256 _tokenizationFee,
        uint256 _yieldFee,
        uint256 _amount,
        uint16 _ibtRateVar,
        bool _isIncrease
    ) public {
        ptFunctionsData memory data;
        feesData memory fData;
        uint8 underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        uint8 ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );
        uint16 ibtRateVar = uint16(bound(_ibtRateVar, 0, 50));
        _tokenizationFee = bound(_tokenizationFee, 0, MAX_TOKENIZATION_FEE);
        _yieldFee = bound(_yieldFee, 0, MAX_YIELD_FEE);

        _deployProtocol(underlyingDecimals, ibtDecimals, _tokenizationFee, _yieldFee, 0);

        vm.prank(feeCollector);
        IPrincipalToken(pt).claimFees(0);

        // User deposits assets in PT
        uint256 assets = uint256(bound(_amount, 100, 100_000_000_000 * ASSET_UNIT));
        IERC20(underlying).approve(pt, assets);
        data.IBTRateBefore = IERC4626(ibt).previewRedeem(IBT_UNIT);
        uint256 sharesMinted = _testPTDeposit(assets, MOCK_ADDR_4);

        uint256[] memory oldRates = new uint256[](5);
        uint256[] memory newRates = new uint256[](5);
        uint256[] memory yield = new uint256[](5);
        // rate change and another user deposit
        for (uint i; i < 5; i++) {
            data.oldIbtRate = IERC4626(ibt).previewRedeem(IBT_UNIT);
            data.oldPtRate = IPrincipalToken(pt).previewRedeem(IBT_UNIT);
            _changeIbtRate(ibtRateVar, ((i % 2) == 0) ? _isIncrease : !_isIncrease);
            data.newIbtRate = IERC4626(ibt).previewRedeem(IBT_UNIT);
            if (data.newIbtRate > data.oldIbtRate) {
                oldRates[i] = data.oldIbtRate;
                newRates[i] = data.newIbtRate;
                yield[i] = sharesMinted.mulDiv(data.oldPtRate, data.oldIbtRate).mulDiv(
                    data.newIbtRate - data.oldIbtRate,
                    data.newIbtRate
                );
            }
            vm.startPrank(address(1));
            IERC20(underlying).approve(pt, 1000 * ASSET_UNIT);
            IPrincipalToken(pt).deposit(1000 * ASSET_UNIT, address(1));
            vm.stopPrank();
        }
        // before withdraw
        data.assetBalBefore = IERC20(underlying).balanceOf(MOCK_ADDR_4);

        // withdraw max assets and claim yield
        uint256 maxAssets = IPrincipalToken(pt).maxWithdraw(MOCK_ADDR_4);
        vm.startPrank(MOCK_ADDR_4);
        _testPTWithdraw(maxAssets, MOCK_ADDR_4);
        IPrincipalToken(pt).claimYield(MOCK_ADDR_4, 0);
        vm.stopPrank();

        // after withdraw
        data.assetBalAfter = IERC20(underlying).balanceOf(MOCK_ADDR_4);
        data.IBTRateAfter = IPrincipalToken(pt).getIBTRate();

        // Compute expected assets after all rates changes taking fee into account
        fData.tokenizationFee = _calcFees(assets, IRegistry(registry).getTokenizationFee());
        data.oldIbtRate = 0;
        data.newIbtRate = 0;
        for (uint i; i < 5; i++) {
            data.oldIbtRate += oldRates[i];
            data.newIbtRate += newRates[i];
            data.expectedAssets += yield[i];
        }
        data.expectedAssets = _amountMinusFee(
            IERC4626(ibt).previewRedeem(data.expectedAssets),
            IRegistry(registry).getYieldFee()
        );
        data.expectedAssets += IPrincipalToken(pt).previewRedeem(sharesMinted);
        if (data.expectedAssets < ASSET_UNIT) {
            assertApproxEqAbs(
                data.assetBalAfter - data.assetBalBefore,
                data.expectedAssets,
                100,
                "Redeemed assets are not as expected"
            );
        } else {
            assertApproxEqRel(
                data.assetBalAfter - data.assetBalBefore,
                data.expectedAssets,
                1e14,
                "Redeemed assets are not as expected"
            );
        }
    }

    /* PT FEES TESTS */

    function testTokenizationFeesDepositFuzz(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint256 _tokenizationFee,
        uint256 _yieldFee,
        uint256 _amount
    ) public {
        ptFunctionsData memory dataPT;

        uint8 underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        uint8 ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );
        _tokenizationFee = bound(_tokenizationFee, 0, MAX_TOKENIZATION_FEE);
        _yieldFee = bound(_yieldFee, 0, MAX_YIELD_FEE);
        _deployProtocol(underlyingDecimals, ibtDecimals, _tokenizationFee, _yieldFee, 0);
        vm.prank(feeCollector);
        IPrincipalToken(pt).claimFees(0);

        MockUnderlyingCustomDecimals(underlying).mint(MOCK_ADDR_1, 1000000000000e18);

        //pt deposit + check if tokenization fee worked.
        _amount = uint256(bound(_amount, 0, 100_000_000 * ASSET_UNIT));
        if (IPrincipalToken(pt).previewDeposit(_amount) != 0) {
            dataPT.ptBalBefore = IPrincipalToken(pt).balanceOf(MOCK_ADDR_1);
            dataPT.assetBalBefore = MockUnderlyingCustomDecimals(underlying).balanceOf(MOCK_ADDR_1);
            uint256 expectedShares = IPrincipalToken(pt).previewDeposit(_amount);

            vm.startPrank(MOCK_ADDR_1);
            IERC20(underlying).approve(pt, _amount);
            uint256 receivedShares = IPrincipalToken(pt).deposit(_amount, MOCK_ADDR_1);
            vm.stopPrank();

            dataPT.ptBalAfter = IPrincipalToken(pt).balanceOf(MOCK_ADDR_1);
            dataPT.assetBalAfter = MockUnderlyingCustomDecimals(underlying).balanceOf(MOCK_ADDR_1);
            assertEq(
                dataPT.assetBalBefore - dataPT.assetBalAfter,
                _amount,
                "assets balance after deposit should be equal to used amount"
            );
            assertEq(
                dataPT.ptBalAfter - dataPT.ptBalBefore,
                receivedShares,
                "PT balance after deposit does not correspond to received shares"
            );
            if (_amount < ASSET_UNIT / 100) {
                assertApproxEqAbs(
                    dataPT.ptBalAfter - dataPT.ptBalBefore,
                    expectedShares,
                    100,
                    "PT balance after deposit does not correspond to preview"
                );
            } else {
                assertApproxEqRel(
                    dataPT.ptBalAfter - dataPT.ptBalBefore,
                    expectedShares,
                    1e12,
                    "PT balance after deposit does not correspond to preview"
                );
            }
            assertLe(
                expectedShares,
                receivedShares,
                "previewDeposit must return less than deposit"
            );

            uint256 unclaimedFees = IPrincipalToken(pt).getUnclaimedFeesInIBT();
            if (
                _calcFees(IERC4626(ibt).previewDeposit(_amount), _tokenizationFee) < IBT_UNIT / 100
            ) {
                assertApproxEqAbs(
                    unclaimedFees,
                    _calcFees(IERC4626(ibt).previewDeposit(_amount), _tokenizationFee),
                    100,
                    "Fees should correspond to theoretical value"
                );
            } else {
                assertApproxEqRel(
                    unclaimedFees,
                    _calcFees(IERC4626(ibt).previewDeposit(_amount), _tokenizationFee),
                    1e14,
                    "Fees should correspond to theoretical value"
                );
            }
            assertGe(
                unclaimedFees,
                _calcFees(IERC4626(ibt).previewDeposit(_amount), _tokenizationFee),
                "Fees should round up compared to theoretical value"
            );
            uint256 underlyingBalanceFeeCollectorBefore = IERC20(underlying).balanceOf(
                feeCollector
            );
            uint256 previewedFees = IERC4626(ibt).previewRedeem(unclaimedFees);
            vm.prank(feeCollector);
            vm.expectRevert();
            uint256 redeemedFees = IPrincipalToken(pt).claimFees(previewedFees + 1000);
            vm.prank(feeCollector);
            redeemedFees = IPrincipalToken(pt).claimFees(previewedFees);
            uint256 underlyingBalanceFeeCollectorAfter = IERC20(underlying).balanceOf(feeCollector);
            assertEq(
                underlyingBalanceFeeCollectorBefore + redeemedFees,
                underlyingBalanceFeeCollectorAfter,
                "Fee collector did not receive claimed fees"
            );
            if (_amount < ASSET_UNIT / 100) {
                assertApproxEqAbs(
                    redeemedFees,
                    previewedFees,
                    100,
                    "Fees claimed dont correspond to available balance"
                );
            } else {
                assertApproxEqRel(
                    redeemedFees,
                    previewedFees,
                    1e12,
                    "Fees claimed dont correspond to available balance"
                );
            }
        }
    }

    function testTokenizationFeesDepositIBTFuzz(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint256 _tokenizationFee,
        uint256 _yieldFee,
        uint256 _amount
    ) public {
        ptFunctionsData memory dataPT;

        uint8 underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        uint8 ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );
        _tokenizationFee = bound(_tokenizationFee, 0, MAX_TOKENIZATION_FEE);
        _yieldFee = bound(_yieldFee, 0, MAX_YIELD_FEE);
        _deployProtocol(underlyingDecimals, ibtDecimals, _tokenizationFee, _yieldFee, 0);
        vm.prank(feeCollector);
        IPrincipalToken(pt).claimFees(0);

        MockUnderlyingCustomDecimals(underlying).mint(MOCK_ADDR_1, 1000000000000e18);

        _amount = uint256(bound(_amount, 0, 100_000_000 * ASSET_UNIT));
        if (IPrincipalToken(pt).previewDepositIBT(IERC4626(ibt).previewDeposit(_amount)) != 0) {
            vm.startPrank(MOCK_ADDR_1);
            // deposit assets in IBT
            IERC20(underlying).approve(ibt, _amount);
            uint256 amountIbt = IERC4626(ibt).deposit(_amount, MOCK_ADDR_1);
            dataPT.ibtBalBefore = IERC4626(ibt).balanceOf(MOCK_ADDR_1);
            dataPT.ptBalBefore = IPrincipalToken(pt).balanceOf(MOCK_ADDR_1);
            uint256 expectedShares = IPrincipalToken(pt).previewDepositIBT(amountIbt);
            // deposit IBTs in PT
            IERC4626(ibt).approve(pt, amountIbt);
            uint256 receivedShares = IPrincipalToken(pt).depositIBT(amountIbt, MOCK_ADDR_1);
            vm.stopPrank();

            dataPT.ptBalAfter = IPrincipalToken(pt).balanceOf(MOCK_ADDR_1);
            dataPT.ibtBalAfter = IERC4626(ibt).balanceOf(MOCK_ADDR_1);
            assertEq(
                dataPT.ibtBalBefore - dataPT.ibtBalAfter,
                amountIbt,
                "ibt balance after deposit should be equal to used amount"
            );
            assertApproxEqAbs(
                dataPT.ptBalAfter - dataPT.ptBalBefore,
                expectedShares,
                1000,
                "PT balance after deposit does not correspond to expected shares"
            );
            assertEq(
                dataPT.ptBalAfter - dataPT.ptBalBefore,
                receivedShares,
                "PT balance after deposit does not correspond to received shares"
            );
            assertApproxEqAbs(
                receivedShares,
                expectedShares,
                1000,
                "previewDepositIBT should be approximately equal to depositIBT"
            );
            assertLe(expectedShares, receivedShares, "previewDepositIBT should round down");

            uint256 unclaimedFees = IPrincipalToken(pt).getUnclaimedFeesInIBT();
            if (_calcFees(amountIbt, _tokenizationFee) < IBT_UNIT / 10) {
                assertApproxEqAbs(
                    unclaimedFees,
                    _calcFees(amountIbt, _tokenizationFee),
                    100,
                    "fees should correspond to theoretical value"
                );
            } else {
                assertApproxEqRel(
                    unclaimedFees,
                    _calcFees(amountIbt, _tokenizationFee),
                    1e13,
                    "fees should correspond to theoretical value"
                );
            }
            assertLe(
                _calcFees(amountIbt, _tokenizationFee),
                unclaimedFees,
                "Theoretical fees should be lower than unclaimed fees"
            );

            vm.prank(feeCollector);
            uint256 redeemedFees = IPrincipalToken(pt).claimFees(0);
            assertApproxEqRel(
                redeemedFees,
                IERC4626(ibt).convertToAssets(unclaimedFees),
                1e12,
                "fees claimed dont correspond to available balance"
            );
        }
    }

    function testTokenizationFeesDepositYieldFuzz(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint256 _tokenizationFee,
        uint256 _yieldFee,
        uint256 _amount,
        uint16 _ibtRateVar
    ) public {
        ptFunctionsData memory dataPT;
        feesData memory fData;

        uint8 underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        uint8 ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );
        _tokenizationFee = bound(_tokenizationFee, 0, MAX_TOKENIZATION_FEE);
        _yieldFee = bound(_yieldFee, 0, MAX_YIELD_FEE);
        _ibtRateVar = uint16(bound(_ibtRateVar, 0, 99));
        _deployProtocol(underlyingDecimals, ibtDecimals, _tokenizationFee, _yieldFee, 0);
        dataPT.unclaimedFees1 = IPrincipalToken(pt).getUnclaimedFeesInIBT();
        vm.prank(feeCollector);
        dataPT.redeemedFees1 = IPrincipalToken(pt).claimFees(0);

        MockUnderlyingCustomDecimals(underlying).mint(MOCK_ADDR_1, 1000000000000e18);

        _amount = bound(_amount, 0, 100_000_000 * ASSET_UNIT);
        if (IPrincipalToken(pt).previewDeposit(_amount) != 0) {
            vm.startPrank(MOCK_ADDR_1);
            IERC20(underlying).approve(pt, _amount);
            dataPT.PTRateBefore = IPrincipalToken(pt).previewRedeem(IBT_UNIT);
            dataPT.IBTRateBefore = IERC4626(ibt).previewRedeem(IBT_UNIT);
            IPrincipalToken(pt).deposit(_amount, MOCK_ADDR_1);
            vm.stopPrank();

            // generating yield
            _changeIbtRate(_ibtRateVar, _amount % 2 == 0);

            dataPT.PTRateAfter = IPrincipalToken(pt).previewRedeem(IBT_UNIT);
            dataPT.IBTRateAfter = IERC4626(ibt).previewRedeem(IBT_UNIT);

            dataPT.assetBalBefore = MockUnderlyingCustomDecimals(underlying).balanceOf(MOCK_ADDR_1);
            // claims the yield
            uint256 expectedYield;
            if (_amount % 2 == 0) {
                expectedYield = IERC4626(ibt).previewRedeem(
                    (
                        (IYieldToken(yt).actualBalanceOf(MOCK_ADDR_1)).mulDiv(
                            dataPT.PTRateBefore,
                            dataPT.IBTRateBefore
                        )
                    ).mulDiv((dataPT.IBTRateAfter - dataPT.IBTRateBefore), dataPT.IBTRateAfter)
                );
            }
            vm.prank(MOCK_ADDR_1);
            uint256 claimedYield = IPrincipalToken(pt).claimYield(MOCK_ADDR_1, 0);
            dataPT.assetBalAfter = MockUnderlyingCustomDecimals(underlying).balanceOf(MOCK_ADDR_1);
            assertEq(
                dataPT.assetBalAfter - dataPT.assetBalBefore,
                claimedYield,
                "received assets correspond to claimed yield"
            );
            if (_amount % 2 == 0) {
                assertLe(
                    dataPT.IBTRateBefore,
                    dataPT.IBTRateAfter,
                    "IBT rate should have increased"
                );
                assertApproxEqAbs(
                    claimedYield,
                    _amountMinusFee(expectedYield, _yieldFee),
                    1000,
                    "Yield claimed should be approximately as expected"
                );
            } else {
                assertLe(
                    dataPT.IBTRateAfter,
                    dataPT.IBTRateBefore,
                    "IBT rate should have decreased"
                );
                assertEq(
                    claimedYield,
                    0,
                    "Yield claimed should be 0 since only negative yield happened"
                );
            }

            dataPT.unclaimedFees2 = IPrincipalToken(pt).getUnclaimedFeesInIBT();

            fData.tokenizationFee = _calcFees(_amount, _tokenizationFee).mulDiv(
                dataPT.IBTRateAfter,
                dataPT.IBTRateBefore
            );
            fData.yieldFee = _calcFees(expectedYield, _yieldFee);

            if (IERC4626(ibt).previewRedeem(dataPT.unclaimedFees2) < ASSET_UNIT) {
                assertApproxEqAbs(
                    IERC4626(ibt).previewRedeem(dataPT.unclaimedFees2),
                    fData.tokenizationFee + fData.yieldFee,
                    100,
                    "Fees should correspond to theoretical value"
                );
            } else {
                assertApproxEqRel(
                    IERC4626(ibt).previewRedeem(dataPT.unclaimedFees2),
                    fData.tokenizationFee + fData.yieldFee,
                    1e13,
                    "Fees should correspond to theoretical value"
                );
            }

            vm.prank(feeCollector);
            dataPT.redeemedFees2 = IPrincipalToken(pt).claimFees(0);
            dataPT.totalFees = IPrincipalToken(pt).getTotalFeesInIBT();

            assertApproxEqAbs(
                MockUnderlyingCustomDecimals(underlying).balanceOf(feeCollector),
                dataPT.redeemedFees1 + dataPT.redeemedFees2,
                100,
                "Fee collector underlying balance is wrong"
            );
            assertApproxEqAbs(
                dataPT.totalFees,
                dataPT.unclaimedFees1 + dataPT.unclaimedFees2,
                100,
                "Total fee collected in IBT is wrong"
            );
            assertApproxEqAbs(
                dataPT.redeemedFees2,
                IERC4626(ibt).convertToAssets(dataPT.unclaimedFees2),
                1000,
                "fees claimed do not correspond to available balance"
            );
        }
    }

    // Testing the PT flash fee
    function testFlashLoanFeeFuzz(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint256 _tokenizationFee,
        uint256 _ptFlashLoanFee,
        uint256 _amount
    ) public {
        feesData memory data;
        ptFunctionsData memory dataPT;
        uint8 underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        uint8 ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );
        _tokenizationFee = bound(_tokenizationFee, 0, MAX_TOKENIZATION_FEE);
        _ptFlashLoanFee = bound(_ptFlashLoanFee, 0, MAX_PT_FLASH_LOAN_FEE);
        _deployProtocol(underlyingDecimals, ibtDecimals, _tokenizationFee, 0, _ptFlashLoanFee);
        vm.prank(feeCollector);
        IPrincipalToken(pt).claimFees(0);
        _amount = bound(_amount, 0, 100_000_000_000_000_000 * ASSET_UNIT);
        MockUnderlyingCustomDecimals(underlying).mint(
            address(this),
            100_000_000_000_000_000 * ASSET_UNIT
        );
        IERC20(underlying).approve(ibt, _amount);
        IERC4626(ibt).deposit(_amount, address(this));

        //seed the pt
        IERC20(underlying).approve(pt, 100_000_000 * ASSET_UNIT);
        data.tokenizationFee = _calcFees(
            IERC4626(ibt).convertToShares(100_000_000 * ASSET_UNIT),
            _tokenizationFee
        );
        IPrincipalToken(pt).deposit(100_000_000 * ASSET_UNIT, address(this));

        //approve the router
        IERC4626(ibt).approve(address(router), _amount);
        IERC20(underlying).approve(address(router), ASSET_UNIT);

        //Execute flash loan + a simple transfer
        bytes memory flashLoanCommands = abi.encodePacked(bytes1(uint8(Commands.TRANSFER_FROM)));
        bytes[] memory flashLoanInputs = new bytes[](1);
        flashLoanInputs[0] = abi.encode(underlying, ASSET_UNIT);
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.FLASH_LOAN)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(pt, ibt, _amount, abi.encode(flashLoanCommands, flashLoanInputs));

        dataPT.ibtBalBefore = IERC4626(ibt).balanceOf(address(this));

        if (_amount > IERC4626(ibt).balanceOf(address(pt))) {
            bytes memory revertData = abi.encodeWithSignature("FlashLoanExceedsMaxAmount()");
            vm.expectRevert(revertData);
            Router(router).execute(commands, inputs);
        } else {
            Router(router).execute(commands, inputs);
            assertApproxEqAbs(
                dataPT.ibtBalBefore - IERC4626(ibt).balanceOf(address(this)),
                _calcFees(_amount, _ptFlashLoanFee),
                10,
                "User is missing only the fee"
            );
            //Lets check the fees were well collected
            data.unclaimedFees = IPrincipalToken(pt).getUnclaimedFeesInIBT();
            data.unclaimedFeesInAssets = IERC4626(ibt).previewRedeem(data.unclaimedFees);
            if (data.unclaimedFees < IBT_UNIT) {
                assertApproxEqAbs(
                    data.unclaimedFees,
                    _calcFees(_amount, _ptFlashLoanFee) + data.tokenizationFee,
                    10,
                    "fees should correspond to theoretical value"
                );
                assertGe(
                    data.unclaimedFees,
                    _calcFees(_amount, _ptFlashLoanFee) + data.tokenizationFee,
                    "fees should round up compared to theoretical value"
                );
            } else {
                assertApproxEqRel(
                    data.unclaimedFees,
                    _calcFees(_amount, _ptFlashLoanFee) + data.tokenizationFee,
                    1e13,
                    "fees should correspond to theoretical value"
                );
                assertGe(
                    data.unclaimedFees,
                    _calcFees(_amount, _ptFlashLoanFee) + data.tokenizationFee,
                    "fees should round up compared to theoretical value"
                );
            }
            vm.prank(feeCollector);
            data.redeemedFees = IPrincipalToken(pt).claimFees(0);
            assertApproxEqRel(
                data.redeemedFees,
                data.unclaimedFeesInAssets,
                10,
                "fees claimed dont correspond to available balance"
            );
        }
    }

    // Testing the tokenization fee and fee reduction without fuzzing the reduction and with no yield
    function testFixedFeeReductionFuzz(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint256 _tokenizationFee,
        uint256 _yieldFee,
        uint256 _amount
    ) public {
        ptFunctionsData memory dataPT;

        uint8 underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        uint8 ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );
        _tokenizationFee = bound(_tokenizationFee, 0, MAX_TOKENIZATION_FEE);
        _yieldFee = bound(_yieldFee, 0, MAX_YIELD_FEE);
        _deployProtocol(underlyingDecimals, ibtDecimals, _tokenizationFee, _yieldFee, 0);
        vm.prank(feeCollector);
        IPrincipalToken(pt).claimFees(0);

        uint256 userFeeReduction = IRegistry(registry).getFeeReduction(pt, MOCK_ADDR_1);
        assertEq(userFeeReduction, 0, "user should not have any reduction by default");
        uint256 userFeeReduction2 = IRegistry(registry).getFeeReduction(pt, MOCK_ADDR_2);
        assertEq(userFeeReduction2, 0, "user 2 should not have any reduction by default");

        vm.prank(scriptAdmin);
        IRegistry(registry).reduceFee(pt, MOCK_ADDR_1, 5e17);
        userFeeReduction = IRegistry(registry).getFeeReduction(pt, MOCK_ADDR_1);
        assertEq(userFeeReduction, 5e17, "user should have 50% reduction");

        MockUnderlyingCustomDecimals(underlying).mint(MOCK_ADDR_1, 1000000000000e18);

        _amount = uint256(bound(_amount, 0, 100_000_000 * IBT_UNIT));
        if (IPrincipalToken(pt).previewDeposit(_amount) != 0) {
            dataPT.ptBalBefore = IPrincipalToken(pt).balanceOf(MOCK_ADDR_1);
            dataPT.assetBalBefore = MockUnderlyingCustomDecimals(underlying).balanceOf(MOCK_ADDR_1);

            vm.startPrank(MOCK_ADDR_1);
            uint256 expectedShares = IPrincipalToken(pt).previewDeposit(_amount);
            IERC20(underlying).approve(pt, _amount);
            IPrincipalToken(pt).deposit(_amount, MOCK_ADDR_1);
            vm.stopPrank();

            dataPT.ptBalAfter = IPrincipalToken(pt).balanceOf(MOCK_ADDR_1);
            dataPT.assetBalAfter = MockUnderlyingCustomDecimals(underlying).balanceOf(MOCK_ADDR_1);
            assertEq(
                dataPT.assetBalBefore - dataPT.assetBalAfter,
                _amount,
                "assets balance after deposit should be equal to used amount"
            );
            assertApproxEqRel(
                dataPT.ptBalAfter - dataPT.ptBalBefore,
                expectedShares,
                1e5,
                "PT balance after deposit does not correspond to preview"
            );

            assertLe(
                expectedShares,
                dataPT.ptBalAfter - dataPT.ptBalBefore,
                "previewDeposit should round down"
            );

            uint256 unclaimedFees = IPrincipalToken(pt).getUnclaimedFeesInIBT();
            if (unclaimedFees < 1e11) {
                assertApproxEqAbs(
                    unclaimedFees,
                    _calcFees(IERC4626(ibt).previewDeposit(_amount), _tokenizationFee) / 2,
                    10,
                    "fees should correspond to theoretical value"
                );
                assertGe(
                    unclaimedFees,
                    _calcFees(IERC4626(ibt).previewDeposit(_amount), _tokenizationFee) / 2,
                    "fees should round up compared to theoretical value"
                );
            } else {
                assertApproxEqRel(
                    unclaimedFees,
                    _calcFees(IERC4626(ibt).previewDeposit(_amount), _tokenizationFee) / 2,
                    1e12,
                    "fees should correspond to theoretical value"
                );
            }

            uint256 expectedFees = IERC4626(ibt).previewRedeem(unclaimedFees);
            vm.prank(feeCollector);
            uint256 redeemedFees = IPrincipalToken(pt).claimFees(0);
            assertApproxEqRel(
                redeemedFees,
                expectedFees,
                1e12,
                "fees claimed dont correspond to available balance"
            );
        }
    }

    // Testing the tokenization fee and fee reduction fuzzed, without yield
    function testFeeReductionFuzz(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint256 _tokenizationFee,
        uint256 _yieldFee,
        uint256 _amount,
        uint256 _reduction
    ) public {
        ptFunctionsData memory dataPT;

        uint8 underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        uint8 ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );
        _tokenizationFee = bound(_tokenizationFee, 0, MAX_TOKENIZATION_FEE);
        _yieldFee = bound(_yieldFee, 0, MAX_YIELD_FEE);
        _deployProtocol(underlyingDecimals, ibtDecimals, _tokenizationFee, _yieldFee, 0);
        vm.prank(feeCollector);
        IPrincipalToken(pt).claimFees(0);

        _reduction = bound(_reduction, 0, FEE_DIVISOR);

        uint256 userFeeReduction = IRegistry(registry).getFeeReduction(pt, MOCK_ADDR_1);
        assertEq(userFeeReduction, 0, "user should not have any reduction by default");

        vm.prank(scriptAdmin);
        IRegistry(registry).reduceFee(pt, MOCK_ADDR_1, _reduction);
        userFeeReduction = IRegistry(registry).getFeeReduction(pt, MOCK_ADDR_1);
        assertEq(userFeeReduction, _reduction, "user should have the fuzzed reduction");

        MockUnderlyingCustomDecimals(underlying).mint(MOCK_ADDR_1, 1000000000000e18);

        _amount = uint256(bound(_amount, 0, 100_000_000 * IBT_UNIT));
        if (IPrincipalToken(pt).previewDeposit(_amount) != 0) {
            dataPT.ptBalBefore = IPrincipalToken(pt).balanceOf(MOCK_ADDR_1);
            dataPT.assetBalBefore = MockUnderlyingCustomDecimals(underlying).balanceOf(MOCK_ADDR_1);

            vm.startPrank(MOCK_ADDR_1);
            uint256 expectedShares = IPrincipalToken(pt).previewDeposit(_amount);
            IERC20(underlying).approve(pt, _amount);
            IPrincipalToken(pt).deposit(_amount, MOCK_ADDR_1);
            vm.stopPrank();

            dataPT.ptBalAfter = IPrincipalToken(pt).balanceOf(MOCK_ADDR_1);
            dataPT.assetBalAfter = MockUnderlyingCustomDecimals(underlying).balanceOf(MOCK_ADDR_1);
            assertEq(
                dataPT.assetBalBefore - dataPT.assetBalAfter,
                _amount,
                "assets balance after deposit should be equal to used amount"
            );
            assertApproxEqRel(
                dataPT.ptBalAfter - dataPT.ptBalBefore,
                expectedShares,
                1e5,
                "PT balance after deposit does not correspond to preview"
            );

            assertLe(
                expectedShares,
                dataPT.ptBalAfter - dataPT.ptBalBefore,
                "previewDeposit should round down"
            );

            uint256 unclaimedFees = IPrincipalToken(pt).getUnclaimedFeesInIBT();
            assertApproxEqAbs(
                unclaimedFees,
                _calcFees(IERC4626(ibt).previewDeposit(_amount), _tokenizationFee) -
                    (
                        _reduction.mulDiv(
                            _calcFees(IERC4626(ibt).previewDeposit(_amount), _tokenizationFee),
                            FEE_DIVISOR,
                            Math.Rounding.Ceil
                        )
                    ),
                10,
                "fees should correspond to theoretical value"
            );
            assertGe(
                unclaimedFees,
                _calcFees(IERC4626(ibt).previewDeposit(_amount), _tokenizationFee) -
                    (
                        _reduction.mulDiv(
                            _calcFees(IERC4626(ibt).previewDeposit(_amount), _tokenizationFee),
                            FEE_DIVISOR,
                            Math.Rounding.Ceil
                        )
                    ),
                "fees should round up compared to theoretical value"
            );

            uint256 expectedFees = IERC4626(ibt).previewRedeem(unclaimedFees);
            vm.prank(feeCollector);
            uint256 redeemedFees = IPrincipalToken(pt).claimFees(0);
            assertApproxEqRel(
                redeemedFees,
                expectedFees,
                1e10,
                "fees claimed do not correspond to expected balance"
            );
        }
    }

    // Testing the fee reduction and fuzzing the reduction and with yield
    function testFeeReductionWithYieldFuzz(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint256 _tokenizationFee,
        uint256 _yieldFee,
        uint256 _amount,
        uint256 _reduction,
        uint16 _ibtRateVar
    ) public {
        feesData memory fData;
        ptFunctionsData memory dataPT;

        uint8 underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        uint8 ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );
        _tokenizationFee = bound(_tokenizationFee, 0, MAX_TOKENIZATION_FEE);
        _yieldFee = bound(_yieldFee, 0, MAX_YIELD_FEE);
        _deployProtocol(underlyingDecimals, ibtDecimals, _tokenizationFee, _yieldFee, 0);
        vm.prank(feeCollector);
        IPrincipalToken(pt).claimFees(0);

        _reduction = bound(_reduction, 0, FEE_DIVISOR);

        uint256 userFeeReduction = IRegistry(registry).getFeeReduction(pt, MOCK_ADDR_1);
        assertEq(userFeeReduction, 0, "user should not have any reduction by default");

        vm.prank(scriptAdmin);
        IRegistry(registry).reduceFee(pt, MOCK_ADDR_1, _reduction);
        userFeeReduction = IRegistry(registry).getFeeReduction(pt, MOCK_ADDR_1);
        assertEq(userFeeReduction, _reduction, "user should have fuzzed reduction");

        MockUnderlyingCustomDecimals(underlying).mint(MOCK_ADDR_1, 1000000000000e18);

        _amount = uint256(bound(_amount, 0, 100_000_000 * IBT_UNIT));
        _ibtRateVar = uint16(bound(_ibtRateVar, 0, 100));

        if (IPrincipalToken(pt).previewDeposit(_amount) != 0) {
            dataPT.ptBalBefore = IPrincipalToken(pt).balanceOf(MOCK_ADDR_1);
            dataPT.assetBalBefore = MockUnderlyingCustomDecimals(underlying).balanceOf(MOCK_ADDR_1);

            vm.startPrank(MOCK_ADDR_1);
            uint256 expectedShares = IPrincipalToken(pt).previewDeposit(_amount);
            IERC20(underlying).approve(pt, _amount);
            IPrincipalToken(pt).deposit(_amount, MOCK_ADDR_1);
            vm.stopPrank();

            // Compute expected assets after all rates changes taking fee into account
            fData.tokenizationFee =
                _calcFees(IERC4626(ibt).previewDeposit(_amount), _tokenizationFee) -
                (
                    _reduction.mulDiv(
                        _calcFees(IERC4626(ibt).previewDeposit(_amount), _tokenizationFee),
                        FEE_DIVISOR,
                        Math.Rounding.Ceil
                    )
                );

            _changeIbtRate(_ibtRateVar, true);

            dataPT.ptBalAfter = IPrincipalToken(pt).balanceOf(MOCK_ADDR_1);
            dataPT.assetBalAfter = MockUnderlyingCustomDecimals(underlying).balanceOf(MOCK_ADDR_1);
            assertEq(
                dataPT.assetBalBefore - dataPT.assetBalAfter,
                _amount,
                "assets balance after deposit should be equal to used amount"
            );
            assertApproxEqRel(
                dataPT.ptBalAfter - dataPT.ptBalBefore,
                expectedShares,
                1e5,
                "PT balance after deposit dont correspond to preview"
            );

            assertLe(
                expectedShares,
                dataPT.ptBalAfter - dataPT.ptBalBefore,
                "previewDeposit should round down"
            );

            uint256 unclaimedFees = IPrincipalToken(pt).getUnclaimedFeesInIBT();
            assertApproxEqAbs(
                unclaimedFees,
                fData.tokenizationFee,
                10,
                "fees should correspond to theoretical value"
            );
            assertGe(
                unclaimedFees,
                fData.tokenizationFee,
                "fees should round up compared to theoretical value"
            );

            uint256 expectedFees = IERC4626(ibt).previewRedeem(unclaimedFees);
            vm.prank(feeCollector);
            uint256 redeemedFees = IPrincipalToken(pt).claimFees(0);
            assertApproxEqRel(
                redeemedFees,
                expectedFees,
                1e10,
                "fees claimed do not correspond to expected value"
            );
        }
    }

    /* PT FULL CYCLE TEST */

    function testPTFullCycle(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint256 _amount,
        uint16 _ibtRateVar,
        bool _isIncrease
    ) public {
        testParametersData memory tData;
        feesData memory fData;
        fullCycleInteractionData memory fciData;

        tData.underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        tData.ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(tData.underlyingDecimals), uint256(MAX_DECIMALS))
        );
        tData.ibtRateVar = uint16(bound(_ibtRateVar, 0, 100));
        fData.tokenizationFee = bound(_amount, 0, MAX_TOKENIZATION_FEE);
        fData.yieldFee = bound(
            uint256(_ibtRateVar) * (MAX_YIELD_FEE / 10) + _amount / 10,
            0,
            MAX_YIELD_FEE
        );
        fData.feeReduction = bound(
            _amount / 100 + uint256(_ibtDecimals) * uint256(_ibtRateVar) * (FEE_DIVISOR / 10),
            0,
            FEE_DIVISOR
        );

        _deployProtocol(
            tData.underlyingDecimals,
            tData.ibtDecimals,
            fData.tokenizationFee,
            fData.yieldFee,
            0 // flash loan fees not tested here
        );

        /// setting fee reductions for all users ///
        // trying with a reduction bigger than 100%
        bytes memory revertData = abi.encodeWithSignature("ReductionTooBig()");
        vm.expectRevert(revertData);
        vm.prank(scriptAdmin);
        IRegistry(registry).reduceFee(pt, FULL_CYCLE_USER_1, FEE_DIVISOR + 1);
        // checking that reduction start at 0 by default
        assertEq(
            IRegistry(registry).getFeeReduction(pt, FULL_CYCLE_USER_1),
            0,
            "user 1 should have no reduction by default"
        );
        assertEq(
            IRegistry(registry).getFeeReduction(pt, FULL_CYCLE_USER_2),
            0,
            "user 2 should have no reduction by default"
        );
        assertEq(
            IRegistry(registry).getFeeReduction(pt, FULL_CYCLE_USER_3),
            0,
            "user 3 should have no reduction by default"
        );
        assertEq(
            IRegistry(registry).getFeeReduction(pt, FULL_CYCLE_USER_4),
            0,
            "user 4 should have no reduction by default"
        );
        // actually reducing fees
        vm.startPrank(scriptAdmin);
        fciData.feeReduction1 = fData.feeReduction;
        vm.expectEmit(true, true, true, false);
        emit FeeReduced(pt, FULL_CYCLE_USER_1, fciData.feeReduction1);
        IRegistry(registry).reduceFee(pt, FULL_CYCLE_USER_1, fciData.feeReduction1);
        fciData.feeReduction2 = _isIncrease ? 1 : 0;
        fciData.feeReduction2 = fciData.feeReduction2 * fciData.feeReduction1;
        IRegistry(registry).reduceFee(pt, FULL_CYCLE_USER_2, fciData.feeReduction2);
        fciData.feeReduction3 =
            fciData.feeReduction1 /
            (tData.ibtDecimals - tData.underlyingDecimals + 1);
        IRegistry(registry).reduceFee(pt, FULL_CYCLE_USER_3, fciData.feeReduction3);
        fciData.feeReduction4 = fciData.feeReduction1 - fciData.feeReduction3;
        IRegistry(registry).reduceFee(pt, FULL_CYCLE_USER_4, fciData.feeReduction4);
        vm.stopPrank();
        // checking the fee reductions have been correctly set
        // checking that reduction start at 0 by default
        assertEq(
            IRegistry(registry).getFeeReduction(pt, FULL_CYCLE_USER_1),
            fciData.feeReduction1,
            "user 1 fee reduction is wrong"
        );
        assertEq(
            IRegistry(registry).getFeeReduction(pt, FULL_CYCLE_USER_2),
            fciData.feeReduction2,
            "user 2 fee reduction is wrong"
        );
        assertEq(
            IRegistry(registry).getFeeReduction(pt, FULL_CYCLE_USER_3),
            fciData.feeReduction3,
            "user 3 fee reduction is wrong"
        );
        assertEq(
            IRegistry(registry).getFeeReduction(pt, FULL_CYCLE_USER_4),
            fciData.feeReduction4,
            "user 4 fee reduction is wrong"
        );

        // MockUnderlyingCustomDecimals(underlying).mint(address(this), 1);
    }

    /* ROUTER TESTS */

    /// Curve Liquidity Arbitrage Tests

    function testCurveLiqArbitrageFuzz(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint256 _amount,
        uint256 _swapAmount
    ) public {
        uint8 underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        uint8 ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );
        _deployProtocol(
            underlyingDecimals,
            ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );
        uint256 minDeposit;
        if (ibtDecimals >= 14) {
            minDeposit = 10 ** (ibtDecimals / 2);
        } else if (ibtDecimals >= 11) {
            minDeposit = 10 ** ((ibtDecimals * 2) / 3);
        } else if (ibtDecimals >= 7) {
            minDeposit = 10 ** ibtDecimals;
        } else {
            minDeposit = 2 * 10 ** ibtDecimals;
        }
        uint256 depositAmount = uint256(bound(_amount, minDeposit, 100_000_000 * IBT_UNIT));

        curveLiqArbitrageData memory data;

        data.baseProportion1 = CurveLiqArbitrage(curveLiqArbitrage).findBestProportion(
            curvePool,
            depositAmount,
            1e5
        );

        uint256 amount1 = IBT_UNIT.mulDiv(
            UNIT,
            data.baseProportion1 + ICurvePool(curvePool).last_prices()
        );
        uint256 amount0 = amount1.mulDiv(data.baseProportion1, UNIT);
        data.lpAmount1 = ICurvePool(curvePool).calc_token_amount([amount0, amount1]);
        uint256 swapAmountPreviewed = bound(_amount, 10 ** (ibtDecimals / 2), amount0);
        data.lpAmount2 = ICurvePool(curvePool).calc_token_amount(
            [
                amount0 - swapAmountPreviewed,
                amount1 + ICurvePool(curvePool).get_dy(0, 1, swapAmountPreviewed)
            ]
        );
        swapAmountPreviewed = bound(_amount, 10 ** (ibtDecimals / 2), amount1);
        data.lpAmount3 = ICurvePool(curvePool).calc_token_amount(
            [
                amount0 + ICurvePool(curvePool).get_dy(1, 0, swapAmountPreviewed),
                amount1 - swapAmountPreviewed
            ]
        );
        data.lpAmount4 = CurveLiqArbitrage(curveLiqArbitrage).previewUnitaryAddLiquidity(
            curvePool,
            depositAmount,
            0.8e18
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
        assertGe(
            data.lpAmount1,
            data.lpAmount4.mulDiv(999, 1000),
            "Best proportion found 1 is sub optimal 3"
        );

        // swap IBTs for PTs
        uint256 swapAmount = bound(
            _swapAmount,
            10 ** (underlyingDecimals / 2),
            ICurvePool(curvePool).balances(1).mulDiv(ASSET_UNIT, 2 * IBT_UNIT)
        );
        MockUnderlyingCustomDecimals(underlying).mint(testUser, swapAmount);
        IERC20(underlying).approve(address(ibt), swapAmount);
        data.ibtReceived = IERC4626(ibt).deposit(swapAmount, testUser);
        IERC20(ibt).approve(curvePool, data.ibtReceived);
        ICurvePool(curvePool).exchange(0, 1, data.ibtReceived, 0, false, testUser);

        data.baseProportion2 = CurveLiqArbitrage(curveLiqArbitrage).findBestProportion(
            curvePool,
            depositAmount,
            1e5
        );
        amount1 = IBT_UNIT.mulDiv(UNIT, data.baseProportion2 + ICurvePool(curvePool).last_prices());
        amount0 = amount1.mulDiv(data.baseProportion2, UNIT);
        data.lpAmount1 = ICurvePool(curvePool).calc_token_amount([amount0, amount1]);
        swapAmountPreviewed = bound(
            _amount / 2 + _swapAmount / 2,
            10 ** (ibtDecimals / 2),
            amount0
        );
        data.lpAmount2 = ICurvePool(curvePool).calc_token_amount(
            [
                amount0 - swapAmountPreviewed,
                amount1 + ICurvePool(curvePool).get_dy(0, 1, swapAmountPreviewed)
            ]
        );
        swapAmountPreviewed = bound(
            _amount / 2 + _swapAmount / 2,
            10 ** (ibtDecimals / 2),
            amount1
        );
        data.lpAmount3 = ICurvePool(curvePool).calc_token_amount(
            [
                amount0 + ICurvePool(curvePool).get_dy(1, 0, swapAmountPreviewed),
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
        swapAmount = bound(
            _swapAmount,
            10 ** (underlyingDecimals / 2),
            ICurvePool(curvePool).balances(0).mulDiv(ASSET_UNIT, 2 * IBT_UNIT)
        );
        MockUnderlyingCustomDecimals(underlying).mint(testUser, swapAmount);
        IERC20(underlying).approve(address(IPrincipalToken(pt)), swapAmount);
        data.ptReceived = IPrincipalToken(pt).deposit(swapAmount, testUser);
        IPrincipalToken(pt).approve(curvePool, data.ptReceived);
        ICurvePool(curvePool).exchange(1, 0, data.ptReceived, 0, false, testUser);

        data.baseProportion3 = CurveLiqArbitrage(curveLiqArbitrage).findBestProportion(
            curvePool,
            depositAmount,
            1e5
        );
        amount1 = IBT_UNIT.mulDiv(UNIT, data.baseProportion3 + ICurvePool(curvePool).last_prices());
        amount0 = amount1.mulDiv(data.baseProportion3, UNIT);
        data.lpAmount1 = ICurvePool(curvePool).calc_token_amount([amount0, amount1]);
        swapAmountPreviewed = bound(_swapAmount, 10 ** (ibtDecimals / 2), amount0);
        data.lpAmount2 = ICurvePool(curvePool).calc_token_amount(
            [
                amount0 - swapAmountPreviewed,
                amount1 + ICurvePool(curvePool).get_dy(0, 1, swapAmountPreviewed)
            ]
        );
        swapAmountPreviewed = bound(_swapAmount, 10 ** (ibtDecimals / 2), amount1);
        data.lpAmount3 = ICurvePool(curvePool).calc_token_amount(
            [
                amount0 + ICurvePool(curvePool).get_dy(1, 0, swapAmountPreviewed),
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

    /**
     * @dev Test adapted for custom decimals. CD stands for Custom Decimals.
     */
    function testCDPreviewUnitaryAddLiquidityFuzz(
        uint256 ibtAmount,
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals
    ) public {
        curveLiqArbitrageData memory data;
        uint8 underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        uint8 ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );
        _deployProtocol(
            underlyingDecimals,
            ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );
        ibtAmount = bound(ibtAmount, 1e8, 1_000_000_000_000 * IBT_UNIT);
        data.baseProportion1 = ICurvePool(curvePool).balances(0).mulDiv(
            UNIT,
            ICurvePool(curvePool).balances(1)
        );
        assertApproxEqRel(data.baseProportion1, 0.8e18, 5e15, "base proportion is wrong");
        // adding in different amount should not result in different result
        data.previewLPTReceived1 = CurveLiqArbitrage(curveLiqArbitrage).previewUnitaryAddLiquidity(
            curvePool,
            ibtAmount,
            data.baseProportion1
        );
        data.previewLPTReceived12 = CurveLiqArbitrage(curveLiqArbitrage).previewUnitaryAddLiquidity(
            curvePool,
            ibtAmount / 10,
            data.baseProportion1
        );
        data.previewLPTReceived13 = CurveLiqArbitrage(curveLiqArbitrage).previewUnitaryAddLiquidity(
            curvePool,
            ibtAmount * 10,
            data.baseProportion1
        );
        assertApproxEqRel(
            data.previewLPTReceived1,
            data.previewLPTReceived12,
            1e15,
            "lpts received different when deposit amount differ (division by 10)"
        );
        assertApproxEqRel(
            data.previewLPTReceived1,
            data.previewLPTReceived13,
            1e15,
            "lpts received different when deposit amount differ (multiplication by 10)"
        );
        // adding in different proportion (worst) should give less LP tokens
        data.previewLPTReceived2 = CurveLiqArbitrage(curveLiqArbitrage).previewUnitaryAddLiquidity(
            curvePool,
            ibtAmount,
            data.baseProportion1 / 2
        );
        data.previewLPTReceived3 = CurveLiqArbitrage(curveLiqArbitrage).previewUnitaryAddLiquidity(
            curvePool,
            ibtAmount,
            data.baseProportion1 * 2
        );
        assertGt(
            data.previewLPTReceived1,
            data.previewLPTReceived2,
            "more lpts received with worst proportion (proportion divided) 1"
        );
        assertGt(
            data.previewLPTReceived1,
            data.previewLPTReceived3,
            "more lpts received with worst proportion (proportion multiplied) 1"
        );

        // swap a lot of IBTs for PTs
        MockUnderlyingCustomDecimals(underlying).mint(testUser, 500_000 * ASSET_UNIT);
        IERC20(underlying).approve(ibt, 500_000 * ASSET_UNIT);
        data.ibtReceived = IERC4626(ibt).deposit(500_000 * ASSET_UNIT, testUser);
        IERC20(ibt).approve(curvePool, data.ibtReceived);
        ICurvePool(curvePool).exchange(0, 1, data.ibtReceived, 0, false, testUser);
        // proportion should now be greater than before
        data.baseProportion2 = ICurvePool(curvePool).balances(0).mulDiv(
            UNIT,
            ICurvePool(curvePool).balances(1)
        );
        assertGt(
            data.baseProportion2,
            data.baseProportion1,
            "proportion of ibt in pool should have increased"
        );
        // adding in different amount should not result in different result
        data.previewLPTReceived1 = CurveLiqArbitrage(curveLiqArbitrage).previewUnitaryAddLiquidity(
            curvePool,
            ibtAmount,
            data.baseProportion2
        );
        data.previewLPTReceived12 = CurveLiqArbitrage(curveLiqArbitrage).previewUnitaryAddLiquidity(
            curvePool,
            ibtAmount / 10,
            data.baseProportion2
        );
        data.previewLPTReceived13 = CurveLiqArbitrage(curveLiqArbitrage).previewUnitaryAddLiquidity(
            curvePool,
            ibtAmount * 10,
            data.baseProportion2
        );
        assertApproxEqRel(
            data.previewLPTReceived1,
            data.previewLPTReceived12,
            1e15,
            "lpts received different when deposit amount differ (division by 10)"
        );
        assertApproxEqRel(
            data.previewLPTReceived1,
            data.previewLPTReceived13,
            1e15,
            "lpts received different when deposit amount differ (multiplication by 10)"
        );
        // the current proportion and price of the pool are not really correlated, explaining why this time adding liquidity in a lower proportion (closer to price) can be more rewarding
        // this behaviour will be highlighted in the following test
        data.previewLPTReceived2 = CurveLiqArbitrage(curveLiqArbitrage).previewUnitaryAddLiquidity(
            curvePool,
            ibtAmount,
            data.baseProportion2 / 2
        );
        data.previewLPTReceived3 = CurveLiqArbitrage(curveLiqArbitrage).previewUnitaryAddLiquidity(
            curvePool,
            ibtAmount,
            data.baseProportion2 * 2
        );
        assertGt(
            data.previewLPTReceived2,
            data.previewLPTReceived1,
            "more lpts received with different proportion (proportion divided) 2"
        );
        assertGt(
            data.previewLPTReceived1,
            data.previewLPTReceived3,
            "more lpts received with worst proportion (proportion multiplied) 2"
        );

        // swap a lot of PTs for IBTs
        MockUnderlyingCustomDecimals(underlying).mint(testUser, 500_000 * ASSET_UNIT);
        IERC20(underlying).approve(address(IPrincipalToken(pt)), 500_000 * ASSET_UNIT);
        data.ptReceived = IPrincipalToken(pt).deposit(500_000 * ASSET_UNIT, testUser);
        IPrincipalToken(pt).approve(curvePool, data.ptReceived);
        ICurvePool(curvePool).exchange(1, 0, data.ptReceived, 0, false, testUser);
        // proportion should now be greater than before
        data.baseProportion3 = ICurvePool(curvePool).balances(0).mulDiv(
            UNIT,
            ICurvePool(curvePool).balances(1)
        );
        assertGt(
            data.baseProportion2,
            data.baseProportion3,
            "proportion of ibt in pool should have decreased"
        );
        // adding in different amount should not result in different result
        data.previewLPTReceived1 = CurveLiqArbitrage(curveLiqArbitrage).previewUnitaryAddLiquidity(
            curvePool,
            ibtAmount,
            data.baseProportion3
        );
        data.previewLPTReceived12 = CurveLiqArbitrage(curveLiqArbitrage).previewUnitaryAddLiquidity(
            curvePool,
            ibtAmount / 10,
            data.baseProportion3
        );
        data.previewLPTReceived13 = CurveLiqArbitrage(curveLiqArbitrage).previewUnitaryAddLiquidity(
            curvePool,
            ibtAmount * 10,
            data.baseProportion3
        );
        assertApproxEqRel(
            data.previewLPTReceived1,
            data.previewLPTReceived12,
            1e15,
            "lpts received different when deposit amount differ (division by 10)"
        );
        assertApproxEqRel(
            data.previewLPTReceived1,
            data.previewLPTReceived13,
            1e15,
            "lpts received different when deposit amount differ (multiplication by 10)"
        );
        // the current proportion and price of the pool are not really correlated, explaining why this time adding liquidity in a lower proportion (closer to price) can be more rewarding
        // this behaviour will be highlighted in the following test
        data.previewLPTReceived2 = CurveLiqArbitrage(curveLiqArbitrage).previewUnitaryAddLiquidity(
            curvePool,
            ibtAmount,
            data.baseProportion3 / 2
        );
        data.previewLPTReceived3 = CurveLiqArbitrage(curveLiqArbitrage).previewUnitaryAddLiquidity(
            curvePool,
            ibtAmount,
            data.baseProportion3 * 2
        );
        assertGt(
            data.previewLPTReceived1,
            data.previewLPTReceived2 - (1e15 * data.previewLPTReceived2) / 1e18,
            "more lpts received with worst proportion (proportion divided) 3"
        );
        assertGt(
            data.previewLPTReceived1,
            data.previewLPTReceived3,
            "more lpts received with worst proportion (proportion multiplied) 3"
        );
    }

    /**
     * @dev Test adapted for custom decimals. CD stands for Custom Decimals.
     */
    function testCDFindBestProportionOptimalFuzz(
        uint256 ibtAmount,
        uint256 epsilon,
        uint256 randomProp,
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals
    ) public {
        curveLiqArbitrageData memory data;
        data.underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        data.ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(data.underlyingDecimals), uint256(MAX_DECIMALS))
        );
        _deployProtocol(
            data.underlyingDecimals,
            data.ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );

        if (data.ibtDecimals <= 9) {
            ibtAmount = bound(
                ibtAmount,
                10 ** (data.ibtDecimals / 2 + 2),
                100_000_000_000 * IBT_UNIT
            );
        } else {
            ibtAmount = bound(
                ibtAmount,
                10 ** (data.ibtDecimals / 2 + 1),
                100_000_000_000 * IBT_UNIT
            );
        }

        epsilon = bound(epsilon, 1e3, 1e4);
        randomProp = bound(randomProp, 1e17, 2e18); // bounding using most coherent proportions

        uint256 bestProp = CurveLiqArbitrage(curveLiqArbitrage).findBestProportion(
            curvePool,
            ibtAmount,
            epsilon
        );

        // compare the rate of lp tokens obtained through adding liquidity in same amounts as in pool
        uint256 tradePropRate = RouterUtil(routerUtil).previewAddLiquidityWithIBT(
            curvePool,
            IBT_UNIT
        );

        uint256 bestPropRate = CurveLiqArbitrage(curveLiqArbitrage).previewUnitaryAddLiquidity(
            curvePool,
            ibtAmount,
            bestProp
        );
        assertGt(bestPropRate, tradePropRate, "trade prop rate better than best");
        // check if our method finds a similar tradePropRate
        uint256 expectedPropRate = CurveLiqArbitrage(curveLiqArbitrage).previewUnitaryAddLiquidity(
            curvePool,
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
        uint256 randomPropRate = CurveLiqArbitrage(curveLiqArbitrage).previewUnitaryAddLiquidity(
            curvePool,
            ibtAmount,
            randomProp
        );
        assertGe(
            bestPropRate,
            randomPropRate - (1e15 * randomPropRate) / 1e18,
            "random prop rate better than best"
        );
    }

    /**
     * @dev Test adapted for custom decimals. CD stands for Custom Decimals.
     */
    function testCDFindBestProportionFuzz(
        uint256 ibtAmount,
        uint256 epsilon,
        uint256 swapAmount,
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals
    ) public {
        curveLiqArbitrageData memory data;
        data.underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        data.ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(data.underlyingDecimals), uint256(MAX_DECIMALS))
        );
        _deployProtocol(
            data.underlyingDecimals,
            data.ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );

        {
            // check if only first deposit of liquidity is affected by failing proportion finding
            // adding a second liquidity addition - can be removed later
            // add initial liquidity to curve pool according to initial price
            MockUnderlyingCustomDecimals(underlying).mint(testUser, 18 * ASSET_UNIT);
            IERC20(underlying).approve(address(ibt), 8 * ASSET_UNIT);
            uint256 amountIBT2 = IERC4626(ibt).deposit(8 * ASSET_UNIT, testUser);
            IERC20(underlying).approve(address(IPrincipalToken(pt)), 10 * ASSET_UNIT);
            uint256 amountPT2 = IPrincipalToken(pt).deposit(10 * ASSET_UNIT, testUser);
            IERC20(ibt).approve(curvePool, amountIBT2);
            IPrincipalToken(pt).approve(curvePool, amountPT2);
            (bool success, ) = curvePool.call(
                abi.encodeWithSelector(0x0b4c7e4d, [amountIBT2, amountPT2], 0)
            );
            if (!success) {
                revert FailedToAddLiquidity();
            }
            // end of second liq addition
        }
        // note test passing with lower bound == 1e8 (Curve limits)
        if (data.ibtDecimals <= 11) {
            ibtAmount = bound(
                ibtAmount,
                10 ** (data.ibtDecimals / 2 + 3),
                100_000_000_000 * IBT_UNIT
            );
        } else if (data.ibtDecimals <= 13) {
            ibtAmount = bound(
                ibtAmount,
                10 ** (data.ibtDecimals / 2 + 2),
                100_000_000_000 * IBT_UNIT
            );
        } else {
            ibtAmount = bound(
                ibtAmount,
                10 ** (data.ibtDecimals / 2 + 1),
                100_000_000_000 * IBT_UNIT
            );
        }
        epsilon = bound(epsilon, 1e2, 1e3);

        data.baseProportion1 = CurveLiqArbitrage(curveLiqArbitrage).findBestProportion(
            curvePool,
            ibtAmount,
            epsilon
        );

        // compare this best proportion rate against the expected one
        uint256 basePropRate = CurveLiqArbitrage(curveLiqArbitrage).previewUnitaryAddLiquidity(
            curvePool,
            ibtAmount,
            data.baseProportion1
        );

        uint256 expectedPropRate = CurveLiqArbitrage(curveLiqArbitrage).previewUnitaryAddLiquidity(
            curvePool,
            ibtAmount,
            0.8e18
        );

        assertGe(
            basePropRate,
            expectedPropRate - (1e15 * expectedPropRate) / 1e18,
            "best proportion rate is worst than the expected one"
        );

        uint256 amount1 = IBT_UNIT.mulDiv(
            UNIT,
            data.baseProportion1 + ICurvePool(curvePool).last_prices()
        );

        uint256 amount0 = amount1.mulDiv(data.baseProportion1, UNIT);
        data.lpAmount1 = ICurvePool(curvePool).calc_token_amount([amount0, amount1]);
        uint256 swapAmountPreviewed = bound(
            ibtAmount,
            amount0 / (10 ** (data.ibtDecimals / 2)),
            amount0
        );
        data.lpAmount2 = ICurvePool(curvePool).calc_token_amount(
            [
                amount0 - swapAmountPreviewed,
                amount1 + ICurvePool(curvePool).get_dy(0, 1, swapAmountPreviewed)
            ]
        );
        swapAmountPreviewed = bound(ibtAmount, amount1 / (10 ** (data.ibtDecimals / 2)), amount1);
        data.lpAmount3 = ICurvePool(curvePool).calc_token_amount(
            [
                amount0 + ICurvePool(curvePool).get_dy(1, 0, swapAmountPreviewed),
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
        swapAmount = bound(
            swapAmount,
            ICurvePool(curvePool).balances(1) / (10 ** (data.ibtDecimals / 2)),
            ICurvePool(curvePool).balances(1) / 2
        );
        swapAmount = swapAmount.mulDiv(ASSET_UNIT, IBT_UNIT);
        MockUnderlyingCustomDecimals(underlying).mint(testUser, swapAmount);
        IERC20(underlying).approve(address(ibt), swapAmount);
        data.ibtReceived = IERC4626(ibt).deposit(swapAmount, testUser);
        IERC20(ibt).approve(curvePool, data.ibtReceived);
        ICurvePool(curvePool).exchange(0, 1, data.ibtReceived, 0, false, testUser);

        data.baseProportion2 = CurveLiqArbitrage(curveLiqArbitrage).findBestProportion(
            curvePool,
            ibtAmount,
            epsilon
        );
        amount1 = IBT_UNIT.mulDiv(UNIT, data.baseProportion2 + ICurvePool(curvePool).last_prices());
        amount0 = amount1.mulDiv(data.baseProportion2, UNIT);
        data.lpAmount1 = ICurvePool(curvePool).calc_token_amount([amount0, amount1]);
        swapAmountPreviewed = bound(ibtAmount, amount0 / (10 ** (data.ibtDecimals / 2)), amount0);
        data.lpAmount2 = ICurvePool(curvePool).calc_token_amount(
            [
                amount0 - swapAmountPreviewed,
                amount1 + ICurvePool(curvePool).get_dy(0, 1, swapAmountPreviewed)
            ]
        );
        swapAmountPreviewed = bound(ibtAmount, amount1 / (10 ** (data.ibtDecimals / 2)), amount1);
        data.lpAmount3 = ICurvePool(curvePool).calc_token_amount(
            [
                amount0 + ICurvePool(curvePool).get_dy(1, 0, swapAmountPreviewed),
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
        swapAmount = bound(
            ibtAmount,
            ICurvePool(curvePool).balances(0) / (10 ** (data.ibtDecimals / 2)),
            ICurvePool(curvePool).balances(0) / 2
        );
        swapAmount = swapAmount.mulDiv(ASSET_UNIT, IBT_UNIT);
        MockUnderlyingCustomDecimals(underlying).mint(testUser, swapAmount);
        IERC20(underlying).approve(address(IPrincipalToken(pt)), swapAmount);
        data.ptReceived = IPrincipalToken(pt).deposit(swapAmount, testUser);
        IPrincipalToken(pt).approve(curvePool, data.ptReceived);
        if (data.ptReceived < ICurvePool(curvePool).balances(1) / 10) {
            ICurvePool(curvePool).exchange(1, 0, data.ptReceived, 0, false, testUser);
        } else {
            ICurvePool(curvePool).exchange(
                1,
                0,
                ICurvePool(curvePool).balances(1) / 10,
                0,
                false,
                testUser
            );
        }

        data.baseProportion3 = CurveLiqArbitrage(curveLiqArbitrage).findBestProportion(
            curvePool,
            ibtAmount,
            epsilon
        );
        amount1 = IBT_UNIT.mulDiv(UNIT, data.baseProportion3 + ICurvePool(curvePool).last_prices());
        amount0 = amount1.mulDiv(data.baseProportion3, UNIT);
        data.lpAmount1 = ICurvePool(curvePool).calc_token_amount([amount0, amount1]);
        swapAmountPreviewed = bound(ibtAmount, amount0 / (10 ** (data.ibtDecimals / 2)), amount0);
        data.lpAmount2 = ICurvePool(curvePool).calc_token_amount(
            [
                amount0 - swapAmountPreviewed,
                amount1 + ICurvePool(curvePool).get_dy(0, 1, swapAmountPreviewed)
            ]
        );
        swapAmountPreviewed = bound(ibtAmount, amount1 / (10 ** (data.ibtDecimals / 2)), amount1);
        data.lpAmount3 = ICurvePool(curvePool).calc_token_amount(
            [
                amount0 + ICurvePool(curvePool).get_dy(1, 0, swapAmountPreviewed),
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

    function testRouterWrapVaultInAdapterFuzz(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint256 _amount
    ) public {
        uint8 underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        uint8 ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );
        _deployProtocol(
            underlyingDecimals,
            ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );
        uint256 depositAmount = uint256(bound(_amount, 0, 100_000_000 * ASSET_UNIT));

        IERC20(underlying).approve(ibt, depositAmount);
        uint256 amountIbt = IERC4626(ibt).deposit(depositAmount, address(this));

        IERC20(ibt).approve(router, amountIbt);
        _testRouterWrapVaultInAdapter(amountIbt);
    }

    function testRouterUnwrapVaultFromAdapterFuzz(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint256 _amount
    ) public {
        uint8 underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        uint8 ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );
        _deployProtocol(
            underlyingDecimals,
            ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );
        uint256 depositAmount = uint256(bound(_amount, 0, 100_000_000 * ASSET_UNIT));

        IERC20(underlying).approve(ibt, depositAmount);
        uint256 amountIbt = IERC4626(ibt).deposit(depositAmount, address(this));

        IERC20(ibt).approve(spectra4626Wrapper, amountIbt);
        uint256 receivedShares = ISpectra4626Wrapper(spectra4626Wrapper).wrap(
            amountIbt,
            address(this),
            0
        );

        IERC20(spectra4626Wrapper).approve(router, receivedShares);
        _testRouterUnwrapVaultFromAdapter(receivedShares);
    }

    function testRouterDepositAssetInIBTFuzz(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint256 _amount
    ) public {
        uint8 underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        uint8 ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );
        _deployProtocol(
            underlyingDecimals,
            ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );
        uint256 depositAmount = uint256(bound(_amount, 0, 100_000_000 * ASSET_UNIT));

        IERC20(underlying).approve(router, depositAmount);
        _testRouterDepositAssetInIBT(depositAmount);
    }

    function testRouterDepositAssetInPTFuzz(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint256 _amount
    ) public {
        uint8 underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        uint8 ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );
        _deployProtocol(
            underlyingDecimals,
            ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );
        uint256 depositAmount = uint256(bound(_amount, 0, 100_000_000 * ASSET_UNIT));

        IERC20(underlying).approve(router, depositAmount);
        _testRouterDepositAssetInPT(depositAmount);
    }

    function testRouterDepositIBTInPTFuzz(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint256 _amount
    ) public {
        uint8 underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), 18, uint256(MAX_DECIMALS))
        );
        uint8 ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );

        _deployProtocol(
            underlyingDecimals,
            ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );
        uint256 depositAmount = uint256(bound(_amount, 0, 100_000_000 * IBT_UNIT));

        IERC20(underlying).approve(ibt, depositAmount);
        uint256 amountIbt = IERC4626(ibt).deposit(depositAmount, address(this));

        IERC4626(ibt).approve(router, amountIbt);
        _testRouterDepositIBTInPT(amountIbt);
    }

    function testRouterRedeemIBTForAssetFuzz(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint256 _amount
    ) public {
        uint8 underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        uint8 ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );
        _deployProtocol(
            underlyingDecimals,
            ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );
        uint256 depositAmount = uint256(bound(_amount, 0, 100_000_000 * ASSET_UNIT));

        IERC20(underlying).approve(ibt, depositAmount);
        uint256 amountIbt = IERC4626(ibt).deposit(depositAmount, address(this));

        IERC4626(ibt).approve(router, amountIbt);
        _testRouterRedeemIBTForAsset(amountIbt);
    }

    function testRouterRedeemPTForAssetFuzz(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint256 _amount
    ) public {
        uint8 underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        uint8 ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );
        _deployProtocol(
            underlyingDecimals,
            ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );
        uint256 depositAmount = uint256(bound(_amount, 0, 100_000_000 * ASSET_UNIT));

        IERC20(underlying).approve(pt, depositAmount);
        uint256 receivedShares = _testPTDeposit(depositAmount, address(this));

        IPrincipalToken(pt).approve(router, receivedShares);
        IYieldToken(yt).approve(router, receivedShares);
        _testRouterRedeemPTForAsset(receivedShares);
    }

    function testRouterRedeemPTForIBTFuzz(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint256 _amount
    ) public {
        uint8 underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        uint8 ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );
        _deployProtocol(
            underlyingDecimals,
            ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );
        uint256 depositAmount = uint256(bound(_amount, 0, 100_000_000 * ASSET_UNIT));

        IERC20(underlying).approve(pt, depositAmount);
        uint256 receivedShares = _testPTDeposit(depositAmount, address(this));

        IPrincipalToken(pt).approve(router, receivedShares);
        IYieldToken(yt).approve(router, receivedShares);
        _testRouterRedeemPTForIBT(receivedShares);
    }

    function testRouterSwapFuzz(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint256 _amount,
        bool _direction
    ) public {
        uint8 underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        uint8 ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );
        _deployProtocol(
            underlyingDecimals,
            ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );

        uint256 depositAmount = uint256(bound(_amount, ASSET_UNIT / 1000, 10_000_000 * ASSET_UNIT));
        uint256 i = _direction ? 0 : 1;
        uint256 j = _direction ? 1 : 0;

        _testAddLiquiditytoCurvePool(100_000_000 * ASSET_UNIT, 100_000_000 * ASSET_UNIT);

        uint256 amountIn;
        if (i == 0) {
            IERC4626(underlying).approve(ibt, depositAmount);
            amountIn = IERC4626(ibt).deposit(depositAmount, address(this));
            IERC4626(ibt).approve(router, amountIn);
        } else {
            IERC4626(underlying).approve(pt, depositAmount);
            amountIn = _testPTDeposit(depositAmount, address(this));
            IPrincipalToken(pt).approve(router, amountIn);
        }

        _testRouterSwap(amountIn, i, j);
    }

    function testSwapUnderlyingToPTFuzz(
        uint256 swapAmount,
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals
    ) public {
        uint8 underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        uint8 ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );
        _deployProtocol(
            underlyingDecimals,
            ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );
        _testAddLiquiditytoCurvePool(
            (1_000_000 * ASSET_UNIT * 0.8e18) / 1e18,
            1_000_000 * ASSET_UNIT
        );
        swapAmount = bound(swapAmount, ASSET_UNIT, 100_000 * ASSET_UNIT);

        IERC20(underlying).approve(router, swapAmount);
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.DEPOSIT_ASSET_IN_IBT)),
            bytes1(uint8(Commands.CURVE_SWAP))
        );
        bytes[] memory inputs = new bytes[](3);
        inputs[0] = abi.encode(underlying, swapAmount);
        inputs[1] = abi.encode(ibt, Constants.CONTRACT_BALANCE, router);
        inputs[2] = abi.encode(
            curvePool,
            0,
            1,
            Constants.CONTRACT_BALANCE,
            0, // No min output
            testUser
        );

        uint256 dy = ICurvePool(curvePool).get_dy(0, 1, IERC4626(ibt).convertToShares(swapAmount));
        routerCommandsData memory data;
        data.assetBalBefore = IERC20(underlying).balanceOf(testUser);
        data.assetBalRouterContractBefore = IERC20(underlying).balanceOf(address(router));
        data.ibtBalBefore = IERC20(ibt).balanceOf(testUser);
        data.ibtBalRouterContractBefore = IERC20(ibt).balanceOf(address(router));
        data.ptBalBefore = IERC20(pt).balanceOf(testUser);
        data.ptBalRouterContractBefore = IERC20(pt).balanceOf(address(router));

        uint256 expectedPT = swapAmount.mulDiv(IRouter(router).previewRate(commands, inputs), 1e27);
        IRouter(router).execute(commands, inputs);

        assertEq(
            IERC20(underlying).balanceOf(testUser) + swapAmount,
            data.assetBalBefore,
            "Underlying balance after execution is wrong"
        );
        assertEq(
            IERC20(underlying).balanceOf(router),
            data.assetBalRouterContractBefore,
            "Underlying balance of Router contract after execution is wrong"
        );
        assertEq(
            IERC20(ibt).balanceOf(testUser),
            data.ibtBalBefore,
            "IBT balance after execution is wrong"
        );
        assertEq(
            IERC20(ibt).balanceOf(router),
            data.ibtBalRouterContractBefore,
            "IBT balance of Router contract after execution is wrong"
        );
        assertApproxEqRel(
            expectedPT,
            IERC20(pt).balanceOf(testUser) - data.ptBalBefore,
            1e13,
            "Router previewRate is wrong"
        );
        assertEq(
            IERC20(pt).balanceOf(testUser),
            data.ptBalBefore + dy,
            "PT balance after execution is wrong"
        );
        assertEq(
            IERC20(pt).balanceOf(router),
            data.ptBalRouterContractBefore,
            "PT balance of Router contract after execution is wrong"
        );
    }

    function testFlashSwapIBTToExactYTFuzz(
        uint256 outputYTAmount,
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals
    ) public {
        uint8 underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        uint8 ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );
        _deployProtocol(
            underlyingDecimals,
            ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );
        _testAddLiquiditytoCurvePool(
            (1_000_000 * ASSET_UNIT * 0.8e18) / 1e18,
            1_000_000 * ASSET_UNIT
        );

        ERC20(underlying).approve(ibt, 1_000_000 * ASSET_UNIT);
        IERC4626(ibt).deposit(1_000_000 * ASSET_UNIT, address(this));

        outputYTAmount = bound(outputYTAmount, IBT_UNIT, ICurvePool(curvePool).balances(1) / 10);

        // * Pre-compute input values
        (uint256 inputIBTAmount, uint256 borrowedIBTAmount) = RouterUtil(routerUtil)
            .previewFlashSwapIBTToExactYT(curvePool, outputYTAmount);

        // vm.assume(inputIBTAmount > 1e12 && inputIBTAmount <= FAUCET_AMOUNT);

        // * Prepare inputs
        bytes memory flashLoanCommands = abi.encodePacked(
            bytes1(uint8(Commands.DEPOSIT_IBT_IN_PT)),
            bytes1(uint8(Commands.CURVE_SWAP))
        );
        bytes[] memory flashLoanInputs = new bytes[](2);
        // Tokenize IBT into PrincipalToken:YieldToken
        flashLoanInputs[0] = abi.encode(
            pt,
            Constants.CONTRACT_BALANCE,
            Constants.ADDRESS_THIS,
            Constants.ADDRESS_THIS,
            0
        );
        // Swap principalToken for IBT
        flashLoanInputs[1] = abi.encode(
            curvePool,
            1,
            0,
            Constants.CONTRACT_BALANCE,
            0,
            Constants.ADDRESS_THIS
        );
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.FLASH_LOAN)),
            bytes1(uint8(Commands.TRANSFER))
        );
        bytes[] memory inputs = new bytes[](2);
        // Borrow IBT
        inputs[0] = abi.encode(
            pt,
            ibt,
            borrowedIBTAmount,
            abi.encode(flashLoanCommands, flashLoanInputs)
        );
        // Send YieldToken
        inputs[1] = abi.encode(yt, address(this), Constants.CONTRACT_BALANCE);

        IERC20(yt).transfer(address(1), IERC20(yt).balanceOf(testUser)); // burn YTs
        assertEq(IERC20(yt).balanceOf(testUser), 0);
        IERC20(ibt).approve(address(router), inputIBTAmount);
        IRouter(router).execute(commands, inputs);
        assertEq(IERC20(yt).balanceOf(address(this)), outputYTAmount);
    }

    function testFlashSwapExactIBTToYTFuzz(
        uint256 inputIBTAmount,
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals
    ) public {
        _underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        _ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(_underlyingDecimals), uint256(MAX_DECIMALS))
        );
        _deployProtocol(
            _underlyingDecimals,
            _ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );
        _testAddLiquiditytoCurvePool(
            (1_000_000 * ASSET_UNIT * 0.8e18) / 1e18,
            1_000_000 * ASSET_UNIT
        );

        ERC20(underlying).approve(ibt, 1_000_000 * ASSET_UNIT);
        IERC4626(ibt).deposit(1_000_000 * ASSET_UNIT, address(this));

        inputIBTAmount = bound(inputIBTAmount, IBT_UNIT, ICurvePool(curvePool).balances(0) / 10);

        // * Pre-compute input values
        (uint256 outputYTAmount, uint256 borrowedIBTAmount) = RouterUtil(routerUtil)
            .previewFlashSwapExactIBTToYT(curvePool, inputIBTAmount);

        // * Prepare inputs
        bytes memory flashLoanCommands = abi.encodePacked(
            bytes1(uint8(Commands.DEPOSIT_IBT_IN_PT)),
            bytes1(uint8(Commands.CURVE_SWAP))
        );
        bytes[] memory flashLoanInputs = new bytes[](2);
        {
            // Tokenize IBT into PrincipalToken:YieldToken
            flashLoanInputs[0] = abi.encode(
                pt,
                Constants.CONTRACT_BALANCE,
                Constants.ADDRESS_THIS,
                Constants.ADDRESS_THIS,
                0
            );
            // Swap principalToken for IBT
            flashLoanInputs[1] = abi.encode(
                curvePool,
                1,
                0,
                Constants.CONTRACT_BALANCE,
                0,
                Constants.ADDRESS_THIS
            );
        }
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.FLASH_LOAN)),
            bytes1(uint8(Commands.TRANSFER))
        );
        bytes[] memory inputs = new bytes[](2);
        {
            // Borrow IBT
            inputs[0] = abi.encode(
                pt,
                ibt,
                borrowedIBTAmount,
                abi.encode(flashLoanCommands, flashLoanInputs)
            );
            // Send YieldToken
            inputs[1] = abi.encode(yt, address(this), Constants.CONTRACT_BALANCE);
        }

        IERC20(yt).transfer(address(1), IERC20(yt).balanceOf(testUser)); // burn YTs
        assertEq(IERC20(yt).balanceOf(testUser), 0);
        IERC20(ibt).approve(router, inputIBTAmount);
        uint256 ibtBalBefore = IERC20(ibt).balanceOf(testUser);
        IRouter(router).execute(commands, inputs);
        assertApproxEqRel(ibtBalBefore - IERC20(ibt).balanceOf(testUser), inputIBTAmount, 1e14);
        assertEq(IERC20(yt).balanceOf(testUser), outputYTAmount);
    }

    function testFlashSwapExactYTToIBTFuzz(
        uint256 inputYTAmount,
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals
    ) public {
        uint8 underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        uint8 ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );
        _deployProtocol(
            underlyingDecimals,
            ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );
        _testAddLiquiditytoCurvePool(
            (1_000_000 * ASSET_UNIT * 0.8e18) / 1e18,
            1_000_000 * ASSET_UNIT
        );
        inputYTAmount = bound(inputYTAmount, IBT_UNIT, ICurvePool(curvePool).balances(1) / 10);

        // * Pre-compute input values
        (uint256 outputIBTAmount, uint256 borrowedIBTAmount) = RouterUtil(routerUtil)
            .previewFlashSwapExactYTToIBT(curvePool, inputYTAmount);

        assertEq(IERC20(ibt).balanceOf(address(router)), 0);
        assertEq(IERC20(pt).balanceOf(address(router)), 0);
        assertEq(IERC20(yt).balanceOf(address(router)), 0);

        // * Prepare inputs
        bytes memory flashLoanCommands = abi.encodePacked(
            bytes1(uint8(Commands.CURVE_SWAP)),
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.REDEEM_PT_FOR_IBT))
        );
        bytes[] memory flashLoanInputs = new bytes[](3);
        {
            // Swap IBT for principalToken
            flashLoanInputs[0] = abi.encode(
                curvePool,
                0,
                1,
                Constants.CONTRACT_BALANCE,
                0,
                Constants.ADDRESS_THIS
            );
            // Collect input YieldToken
            flashLoanInputs[1] = abi.encode(yt, inputYTAmount);
            // Withdraw principalToken:YieldToken for IBT
            flashLoanInputs[2] = abi.encode(
                pt,
                Constants.CONTRACT_BALANCE,
                Constants.ADDRESS_THIS,
                0
            );
        }
        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.FLASH_LOAN)),
            bytes1(uint8(Commands.TRANSFER))
        );
        bytes[] memory inputs = new bytes[](2);
        {
            // Borrow IBT
            inputs[0] = abi.encode(
                pt,
                ibt,
                borrowedIBTAmount,
                abi.encode(flashLoanCommands, flashLoanInputs)
            );
            // Send remaining IBT
            inputs[1] = abi.encode(ibt, address(1111), Constants.CONTRACT_BALANCE);
        }

        assertEq(IERC20(ibt).balanceOf(address(1111)), 0);
        uint256 ytBalanceBefore = IERC20(yt).balanceOf(testUser);
        IERC20(yt).approve(address(router), inputYTAmount);
        IERC20(ibt).approve(
            address(router),
            IPrincipalToken(pt).flashFee(address(ibt), borrowedIBTAmount)
        );
        IRouter(router).execute(commands, inputs);
        assertEq(
            ytBalanceBefore - IERC20(yt).balanceOf(testUser),
            inputYTAmount, // amount spent
            "YT amount received is wrong"
        );
        assertApproxEqRel(
            IERC20(ibt).balanceOf(address(1111)),
            outputIBTAmount,
            1e13,
            "IBT amount received is wrong"
        );
    }

    /* ROUTER UTIL TESTS */

    function testSecantMethodPrecisionCustomDecimalsFuzz(
        uint256 inputIBTAmount,
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals
    ) public {
        _underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        _ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(_underlyingDecimals), uint256(MAX_DECIMALS))
        );
        _deployProtocol(
            _underlyingDecimals,
            _ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );
        _testAddLiquiditytoCurvePool(
            (1_000_000 * ASSET_UNIT * 0.8e18) / 1e18,
            1_000_000 * ASSET_UNIT
        );

        inputIBTAmount = bound(inputIBTAmount, IBT_UNIT, ICurvePool(curvePool).balances(1) / 10);
        (uint256 outputYTAmount, ) = RouterUtil(routerUtil).previewFlashSwapExactIBTToYT(
            curvePool,
            inputIBTAmount
        );

        (uint256 inputIBTAmountRequired, ) = RouterUtil(routerUtil).previewFlashSwapIBTToExactYT(
            curvePool,
            outputYTAmount
        );

        assertApproxEqRel(inputIBTAmount, inputIBTAmountRequired, 1e15);
    }

    function testGetDxPTToIBTCustomDecimalsFuzz(
        uint256 amountOfIBTOut,
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals
    ) public {
        _underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        _ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(_underlyingDecimals), uint256(MAX_DECIMALS))
        );
        _deployProtocol(
            _underlyingDecimals,
            _ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );
        _testAddLiquiditytoCurvePool(
            (1_000_000 * ASSET_UNIT * 0.8e18) / 1e18,
            1_000_000 * ASSET_UNIT
        );

        amountOfIBTOut = bound(amountOfIBTOut, IBT_UNIT, ICurvePool(curvePool).balances(1) / 10);
        uint256 amountOfPTIn = CurvePoolUtil.getDx(curvePool, 1, 0, amountOfIBTOut);
        uint256 predictedAmountOfIBTOut = ICurvePool(curvePool).get_dy(1, 0, amountOfPTIn);
        assertApproxEqRel(amountOfIBTOut, predictedAmountOfIBTOut, 1e13);
    }

    function testGetDxIBTToPTCustomDecimalsFuzz(
        uint256 amountOfPTOut,
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals
    ) public {
        _underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        _ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(_underlyingDecimals), uint256(MAX_DECIMALS))
        );
        _deployProtocol(
            _underlyingDecimals,
            _ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );
        _testAddLiquiditytoCurvePool(
            (1_000_000 * ASSET_UNIT * 0.8e18) / 1e18,
            1_000_000 * ASSET_UNIT
        );

        amountOfPTOut = bound(amountOfPTOut, IBT_UNIT, ICurvePool(curvePool).balances(0) / 10);
        uint256 amountOfIBTIn = CurvePoolUtil.getDx(curvePool, 0, 1, amountOfPTOut);
        uint256 predictedAmountOfPTOut = ICurvePool(curvePool).get_dy(0, 1, amountOfIBTIn);
        assertApproxEqRel(amountOfPTOut, predictedAmountOfPTOut, 1e13);
    }

    function testIBTToExactYTFlashSwapCustomDecimalsFuzz(
        uint256 ytWanted,
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals
    ) public {
        _underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        _ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(_underlyingDecimals), uint256(MAX_DECIMALS))
        );
        _deployProtocol(
            _underlyingDecimals,
            _ibtDecimals,
            0, // remove tokenization fee for this test
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );
        _testAddLiquiditytoCurvePool(
            (1_000_000 * ASSET_UNIT * 0.8e18) / 1e18,
            1_000_000 * ASSET_UNIT
        );

        ytWanted = bound(ytWanted, IBT_UNIT, ICurvePool(curvePool).balances(1) / 100);
        uint256 ytIBTSpot = RouterUtil(routerUtil).convertIBTToYTSpot(IBT_UNIT, curvePool);
        uint256 minAmountOfIBT = ytWanted.mulDiv(IBT_UNIT, ytIBTSpot);

        (uint256 amountIBTNeeded, ) = RouterUtil(routerUtil).previewFlashSwapIBTToExactYT(
            curvePool,
            ytWanted
        );

        // Also takes into account the fees
        uint256 priceImpactPaid = _getCurvePriceImpactLossAndFees(1, 0, ytWanted);

        // With tokenization fees omitted, both values should match
        assertApproxEqRel(minAmountOfIBT + priceImpactPaid, amountIBTNeeded, 1e13);
    }

    function testExactYTToIBTFlashSwapCustomDecimalsFuzz(
        uint256 inputYTAmount,
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals
    ) public {
        _underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        _ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(_underlyingDecimals), uint256(MAX_DECIMALS))
        );
        _deployProtocol(
            _underlyingDecimals,
            _ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );
        _testAddLiquiditytoCurvePool(
            (1_000_000 * ASSET_UNIT * 0.8e18) / 1e18,
            1_000_000 * ASSET_UNIT
        );

        inputYTAmount = bound(inputYTAmount, IBT_UNIT, ICurvePool(curvePool).balances(0) / 100);
        uint256 ytIBTSpot = RouterUtil(routerUtil).convertIBTToYTSpot(IBT_UNIT, curvePool);
        uint256 maxIBTReceived = inputYTAmount.mulDiv(IBT_UNIT, ytIBTSpot);

        (uint256 ibtReceived, uint256 borrowedIBTAmount) = RouterUtil(routerUtil)
            .previewFlashSwapExactYTToIBT(curvePool, inputYTAmount);

        // Price impact and fees quoted in IBT
        uint256 priceImpactAndFees = _getCurvePriceImpactLossAndFees(0, 1, borrowedIBTAmount)
            .mulDiv(
                RouterUtil(routerUtil).spotExchangeRate(curvePool, 1, 0),
                CurvePoolUtil.CURVE_UNIT
            );

        assertApproxEqRel(maxIBTReceived, ibtReceived + priceImpactAndFees, 1e13);
    }

    function testFlashSwapCycleCustomDecimalsFuzz(
        uint256 inputIBTAmount,
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals
    ) public {
        _underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        _ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(_underlyingDecimals), uint256(MAX_DECIMALS))
        );
        _deployProtocol(
            _underlyingDecimals,
            _ibtDecimals,
            0, // remove tokenization fee for this test
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );
        _testAddLiquiditytoCurvePool(
            (1_000_000 * ASSET_UNIT * 0.8e18) / 1e18,
            1_000_000 * ASSET_UNIT
        );

        inputIBTAmount = bound(inputIBTAmount, IBT_UNIT, ICurvePool(curvePool).balances(1) / 100);

        (uint256 outputYTAmount, ) = RouterUtil(routerUtil).previewFlashSwapExactIBTToYT(
            curvePool,
            inputIBTAmount
        );

        // quoted in IBT
        uint256 priceImpactAndFees1 = _getCurvePriceImpactLossAndFees(
            1,
            0,
            outputYTAmount.mulDiv(RAY_UNIT, IPrincipalToken(pt).getIBTRate())
        );

        (uint256 outputIBTAmount, uint256 borrowedIBTAmount2) = RouterUtil(routerUtil)
            .previewFlashSwapExactYTToIBT(curvePool, outputYTAmount);

        uint256 priceImpactAndFees2 = _getCurvePriceImpactLossAndFees(0, 1, borrowedIBTAmount2)
            .mulDiv(RouterUtil(routerUtil).spotExchangeRate(curvePool, 1, 0), UNIT);

        // With tokenization fees omitted, both values should match
        assertApproxEqRel(
            inputIBTAmount,
            outputIBTAmount + priceImpactAndFees2 + priceImpactAndFees1,
            1e15
        );
    }

    /* INTERNAL */

    /* PROTOCOL DEPLOYMENT */

    function _deployProtocol(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint256 _tokenizationFee,
        uint256 _yieldFee,
        uint256 _ptFlashLoanFee
    ) internal {
        // deploy underlying, IBT and wrapper
        _deployTokens(_underlyingDecimals, _ibtDecimals, 0, false);

        // deploy Spectra core contracts
        _deployCore(_tokenizationFee, _yieldFee, _ptFlashLoanFee);

        // deploy curve pool
        CurvePoolParams memory curvePoolDeploymentData;
        curvePoolDeploymentData.A = 4e9;
        curvePoolDeploymentData.gamma = 2e16;
        curvePoolDeploymentData.mid_fee = 5000000;
        curvePoolDeploymentData.out_fee = 45000000;
        curvePoolDeploymentData.allowed_extra_profit = 10000000000;
        curvePoolDeploymentData.fee_gamma = 5000000000000000;
        curvePoolDeploymentData.adjustment_step = 5500000000000;
        curvePoolDeploymentData.admin_fee = 5000000000;
        curvePoolDeploymentData.ma_half_time = 600;
        curvePoolDeploymentData.initial_price = 0.8e18;
        curvePool = _deployCurvePool(address(pt), curvePoolDeploymentData);

        // misc minting and liquidity provisioning
        MockUnderlyingCustomDecimals(underlying).mint(
            address(this),
            100_000_000_000_000_000_000_000_000 * ASSET_UNIT
        );

        MockUnderlyingCustomDecimals(underlying).mint(
            address(1),
            100_000_000_000_000_000_000_000_000 * ASSET_UNIT
        );

        MockUnderlyingCustomDecimals(underlying).mint(testUser, 100000000 * ASSET_UNIT);
        MockUnderlyingCustomDecimals(underlying).approve(address(ibt), 1000000 * ASSET_UNIT);
        MockUnderlyingCustomDecimals(underlying).approve(pt, 1000000 * ASSET_UNIT);
        uint256 amountIbt = IERC4626(ibt).deposit((1000000 * ASSET_UNIT * 0.8e18) / 1e18, testUser);
        uint256 amountPt = IPrincipalToken(pt).deposit(1000000 * ASSET_UNIT, testUser);

        IERC20(ibt).approve(curvePool, amountIbt);
        IERC20(pt).approve(curvePool, amountPt);
        (bool success, ) = curvePool.call(
            abi.encodeWithSelector(0x0b4c7e4d, [amountIbt, amountPt], 0)
        );
        require(success, "Could not add liquidity to curve pool");
    }

    function _deployProtocolIBTRateFuzzed(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint256 _tokenizationFee,
        uint256 _yieldFee,
        uint256 _ptFlashLoanFee,
        uint16 _ibtRateVar,
        bool _isIncrease
    ) internal {
        // deploy underlying, IBT and wrapper, and modify IBT rate
        _deployTokens(_underlyingDecimals, _ibtDecimals, _ibtRateVar, _isIncrease);

        // deploy Spectra core contracts
        _deployCore(_tokenizationFee, _yieldFee, _ptFlashLoanFee);

        // deploy curve pool
        CurvePoolParams memory curvePoolDeploymentData;
        curvePoolDeploymentData.A = 4e9;
        curvePoolDeploymentData.gamma = 2e16;
        curvePoolDeploymentData.mid_fee = 5000000;
        curvePoolDeploymentData.out_fee = 45000000;
        curvePoolDeploymentData.allowed_extra_profit = 10000000000;
        curvePoolDeploymentData.fee_gamma = 5000000000000000;
        curvePoolDeploymentData.adjustment_step = 5500000000000;
        curvePoolDeploymentData.admin_fee = 5000000000;
        curvePoolDeploymentData.ma_half_time = 600;
        curvePoolDeploymentData.initial_price = 0.8e18;
        curvePool = _deployCurvePool(address(pt), curvePoolDeploymentData);

        // misc minting and liquidity provisioning
        MockUnderlyingCustomDecimals(underlying).mint(
            address(this),
            100_000_000_000_000_000_000_000_000 * ASSET_UNIT
        );

        MockUnderlyingCustomDecimals(underlying).mint(
            address(1),
            100_000_000_000_000_000_000_000_000 * ASSET_UNIT
        );

        MockUnderlyingCustomDecimals(underlying).mint(testUser, 100000000 * ASSET_UNIT);
        MockUnderlyingCustomDecimals(underlying).approve(address(ibt), 1000000 * ASSET_UNIT);
        MockUnderlyingCustomDecimals(underlying).approve(pt, 1000000 * ASSET_UNIT);
        uint256 amountIbt = IERC4626(ibt).deposit((1000000 * ASSET_UNIT * 0.8e18) / 1e18, testUser);
        uint256 amountPt = IPrincipalToken(pt).deposit(1000000 * ASSET_UNIT, testUser);

        IERC20(ibt).approve(curvePool, amountIbt);
        IERC20(pt).approve(curvePool, amountPt);
        (bool success, ) = curvePool.call(
            abi.encodeWithSelector(0x0b4c7e4d, [amountIbt, amountPt], 0)
        );
        require(success, "Could not add liquidity to curve pool");
    }

    function _deployTokens(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint16 _ibtRateVar,
        bool _isIncrease
    ) internal {
        underlying = address(new MockUnderlyingCustomDecimals());
        MockUnderlyingCustomDecimals(underlying).initialize(
            "MOCK UNDERLYING",
            "MUDL",
            _underlyingDecimals
        );

        ibt = address(
            new MockIBTCustomDecimals("MOCK IBT", "MIBT", IERC20(underlying), _ibtDecimals)
        );

        spectra4626Wrapper = address(new MockSpectra4626Wrapper());
        MockSpectra4626Wrapper(spectra4626Wrapper).initialize(ibt, address(0));

        IBT_UNIT = 10 ** _ibtDecimals;
        ASSET_UNIT = 10 ** _underlyingDecimals;

        // deposit assets in IBT before PT deployment
        MockUnderlyingCustomDecimals(underlying).mint(testUser, 100_000_000 * ASSET_UNIT);
        MockUnderlyingCustomDecimals(underlying).approve(address(ibt), 100_000_000 * ASSET_UNIT);
        IERC4626(ibt).deposit(100_000_000 * ASSET_UNIT, testUser);
        if (_ibtRateVar > 0) {
            _changeIbtRate(_ibtRateVar, _isIncrease);
        }
    }

    function _deployCore(
        uint256 _tokenizationFee,
        uint256 _yieldFee,
        uint256 _ptFlashLoanFee
    ) internal {
        AccessManagerDeploymentScript accessManagerScript = new AccessManagerDeploymentScript();
        address accessManager = accessManagerScript.deployForTest(scriptAdmin);

        // deploy registry
        RegistryScript registryScript = new RegistryScript();
        registry = registryScript.deployForTest(
            _tokenizationFee,
            _yieldFee,
            _ptFlashLoanFee,
            feeCollector,
            accessManager
        );
        vm.prank(scriptAdmin);
        IAccessManager(accessManager).grantRole(Roles.REGISTRY_ROLE, scriptAdmin, 0);
        vm.prank(scriptAdmin);
        IAccessManager(accessManager).grantRole(Roles.FEE_SETTER_ROLE, scriptAdmin, 0);

        // deploy router
        RouterScript routerScript = new RouterScript();
        (router, routerUtil, curveLiqArbitrage) = routerScript.deployForTest(
            registry,
            address(0),
            // address(1),
            accessManager
        );

        // deploy principalToken and yieldToken instances and beacons
        PrincipalTokenInstanceScript principalTokenInstanceScript = new PrincipalTokenInstanceScript();
        YTInstanceScript ytInstanceScript = new YTInstanceScript();
        PrincipalToken principalTokenInstance = PrincipalToken(
            principalTokenInstanceScript.deployForTest(registry)
        );
        address ytInstance = ytInstanceScript.deployForTest();
        PrincipalTokenBeaconScript principalTokenBeaconScript = new PrincipalTokenBeaconScript();
        YTBeaconScript ytBeaconScript = new YTBeaconScript();
        principalTokenBeaconScript.deployForTest(
            address(principalTokenInstance),
            registry,
            accessManager
        );
        ytBeaconScript.deployForTest(ytInstance, registry, accessManager);

        // deploy factory
        FactoryScript factoryScript = new FactoryScript();
        factory = factoryScript.deployForTest(registry, curveFactoryAddress, accessManager);
        vm.prank(scriptAdmin);
        AccessManager(accessManager).grantRole(Roles.ADMIN_ROLE, factory, 0);
        vm.prank(scriptAdmin);
        AccessManager(accessManager).grantRole(Roles.REGISTRY_ROLE, factory, 0);

        // deploy principalToken
        PrincipalTokenScript principalTokenScript = new PrincipalTokenScript();
        pt = principalTokenScript.deployForTest(factory, ibt, DURATION);
        yt = IPrincipalToken(pt).getYT();
    }

    function _deployCurvePool(
        address _pt,
        CurvePoolParams memory _p
    ) internal returns (address _curvePoolAddr) {
        bytes memory name = bytes("Spectra-PT/IBT");
        bytes memory symbol = bytes("SPT-PT/IBT");
        bytes memory cd = new bytes(576); // calldata to the curve factory
        address coin0 = IPrincipalToken(_pt).getIBT();
        address coin1 = _pt;
        uint256 num; // temporary variable for passing contents of _p to Yul
        // append the coins array
        assembly {
            mstore(
                add(cd, 0x20),
                0x00000000000000000000000000000000000000000000000000000000000001c0
            )
            mstore(
                add(cd, 0x40),
                0x0000000000000000000000000000000000000000000000000000000000000200
            )
            mstore(add(cd, 0x60), coin0)
            mstore(add(cd, 0x80), coin1)
        }

        // append the numerical parameters
        num = _p.A;
        assembly {
            mstore(add(cd, 0xa0), num)
        }
        num = _p.gamma;
        assembly {
            mstore(add(cd, 0xc0), num)
        }
        num = _p.mid_fee;
        assembly {
            mstore(add(cd, 0xe0), num)
        }
        num = _p.out_fee;
        assembly {
            mstore(add(cd, 0x100), num)
        }
        num = _p.allowed_extra_profit;
        assembly {
            mstore(add(cd, 0x120), num)
        }
        num = _p.fee_gamma;
        assembly {
            mstore(add(cd, 0x140), num)
        }
        num = _p.adjustment_step;
        assembly {
            mstore(add(cd, 0x160), num)
        }
        num = _p.admin_fee;
        assembly {
            mstore(add(cd, 0x180), num)
        }
        num = _p.ma_half_time;
        assembly {
            mstore(add(cd, 0x1a0), num)
        }
        num = _p.initial_price;

        assembly {
            mstore(add(cd, 0x1c0), num)

            mstore(add(cd, 0x1e0), mload(name))
            mstore(add(cd, 0x200), mload(add(name, 0x20)))

            mstore(add(cd, 0x220), mload(symbol))
            mstore(add(cd, 0x240), mload(add(symbol, 0x20)))
        }

        // prepend the function selector
        cd = bytes.concat(ICurveFactory(address(0)).deploy_pool.selector, cd);

        // make the call to the curve factory
        (bool success, bytes memory result) = curveFactoryAddress.call(cd);
        if (!success) {
            revert DeploymentFailed();
        }

        assembly {
            _curvePoolAddr := mload(add(add(result, 12), 20))
        }
    }

    /* INTERNAL FOR PRINCIPAL TOKEN */

    /**
     * @dev Internal function for testing basic PT deposit functionality
     * @param assets Amount of assets to deposit
     * @param receiver Address of the receiver
     * @return receivedShares Amount of shares received
     */
    function _testPTDeposit(
        uint256 assets,
        address receiver
    ) internal returns (uint256 receivedShares) {
        ptFunctionsData memory data;

        // data before
        data.assetBalBefore = IERC20(underlying).balanceOf(address(this));
        data.ptBalBeforeReceiver = IERC20(pt).balanceOf(receiver);
        data.ytBalBeforeReceiver = IERC20(yt).balanceOf(receiver);
        data.ibtBalPTContractBefore = IERC20(ibt).balanceOf(address(pt));

        // data global
        data.expectedShares1 = _amountMinusFee(
            IERC4626(ibt).previewDeposit(assets),
            IRegistry(registry).getTokenizationFee()
        ).mulDiv(IPrincipalToken(pt).getIBTRate(), IPrincipalToken(pt).getPTRate());
        data.expectedShares2 = IPrincipalToken(pt).previewDeposit(assets);
        data.assetsInIBT = IERC4626(ibt).convertToShares(assets);

        // deposit
        if (data.expectedShares2 != 0) {
            receivedShares = IPrincipalToken(pt).deposit(assets, receiver);

            // data after
            data.assetBalAfter = IERC20(underlying).balanceOf(address(this));
            data.ptBalAfterReceiver = IPrincipalToken(pt).balanceOf(receiver);
            data.ytBalAfterReceiver = IYieldToken(yt).balanceOf(receiver);
            data.ibtBalPTContractAfter = IERC4626(ibt).balanceOf(address(pt));

            // assertions
            if (assets > 10000) {
                assertApproxEqRel(
                    data.expectedShares1,
                    data.expectedShares2,
                    1e15,
                    "previewDeposit does not match the calculated value"
                );

                assertApproxEqRel(
                    receivedShares,
                    data.expectedShares2,
                    1e15,
                    "Received shares from deposit are not as expected (previewDeposit)"
                );
            } else {
                assertApproxEqAbs(
                    data.expectedShares1,
                    data.expectedShares2,
                    _getPrecision(IBT_UNIT),
                    "previewDeposit does not match the calculated value"
                );

                assertApproxEqAbs(
                    receivedShares,
                    data.expectedShares2,
                    _getPrecision(IBT_UNIT),
                    "Received shares from deposit are not as expected (previewDeposit)"
                );
            }

            assertGe(
                receivedShares,
                data.expectedShares2,
                "previewDeposit must round down compared to real received amount of shares"
            );

            assertEq(
                data.assetBalBefore,
                data.assetBalAfter + assets,
                "Asset balance after deposit is wrong"
            );
            assertEq(
                data.ptBalAfterReceiver,
                data.ptBalBeforeReceiver + receivedShares,
                "PT balance after deposit is wrong"
            );
            assertEq(
                data.ytBalAfterReceiver,
                data.ytBalBeforeReceiver + receivedShares,
                "YT balance after deposit is wrong"
            );

            assertEq(
                data.ibtBalPTContractAfter,
                data.ibtBalPTContractBefore + data.assetsInIBT,
                "IBT balance of PT contract after deposit is wrong"
            );
        }
    }

    /**
     * @dev Internal function for testing basic PT deposit functionality
     * @param assets Amount of assets to deposit
     * @param ytReceiver Address of the YT receiver
     * @param ptReceiver Address of the PT receiver
     * @return receivedShares Amount of shares received
     */
    function _testPTDeposit2(
        uint256 assets,
        address ytReceiver,
        address ptReceiver
    ) internal returns (uint256 receivedShares) {
        ptFunctionsData2 memory data;

        // data before
        data.assetBalBefore = IERC20(underlying).balanceOf(address(this));
        data.ptBalBeforeUser1 = IERC20(pt).balanceOf(ytReceiver);
        data.ytBalBeforeUser1 = IERC20(yt).balanceOf(ytReceiver);

        data.ptBalBeforeUser2 = IERC20(pt).balanceOf(ptReceiver);
        data.ytBalBeforeUser2 = IERC20(yt).balanceOf(ptReceiver);
        data.ibtBalPTContractBefore = IERC20(ibt).balanceOf(address(pt));

        // data global
        data.expectedShares1 = _amountMinusFee(
            IERC4626(ibt).previewDeposit(assets),
            IRegistry(registry).getTokenizationFee()
        ).mulDiv(IPrincipalToken(pt).getIBTRate(), IPrincipalToken(pt).getPTRate());
        data.expectedShares2 = IPrincipalToken(pt).previewDeposit(assets);
        data.assetsInIBT = IERC4626(ibt).previewDeposit(assets);

        // deposit
        if (data.expectedShares2 != 0) {
            receivedShares = IPrincipalToken(pt).deposit(assets, ptReceiver, ytReceiver);

            // data after
            data.assetBalAfter = IERC20(underlying).balanceOf(address(this));
            data.ptBalAfterUser1 = IPrincipalToken(pt).balanceOf(ytReceiver);
            data.ytBalAfterUser1 = IYieldToken(yt).balanceOf(ytReceiver);
            data.ptBalAfterUser2 = IPrincipalToken(pt).balanceOf(ptReceiver);
            data.ytBalAfterUser2 = IYieldToken(yt).balanceOf(ptReceiver);
            data.ibtBalPTContractAfter = IERC4626(ibt).balanceOf(address(pt));

            // assertions
            if (assets > 10000) {
                assertApproxEqRel(
                    data.expectedShares1,
                    data.expectedShares2,
                    1e15,
                    "previewDeposit does not match the calculated value"
                );

                assertApproxEqRel(
                    receivedShares,
                    data.expectedShares2,
                    1e15,
                    "Received shares from deposit are not as expected (previewDeposit)"
                );
            } else {
                assertApproxEqAbs(
                    data.expectedShares1,
                    data.expectedShares2,
                    _getPrecision(IBT_UNIT),
                    "previewDeposit does not match the calculated value"
                );

                assertApproxEqAbs(
                    receivedShares,
                    data.expectedShares2,
                    _getPrecision(IBT_UNIT),
                    "Received shares from deposit are not as expected (previewDeposit)"
                );
            }

            assertGe(
                receivedShares,
                data.expectedShares2,
                "previewDeposit must round down compared to real received amount of shares"
            );

            assertEq(
                data.assetBalBefore,
                data.assetBalAfter + assets,
                "Asset balance after deposit is wrong"
            );
            assertEq(
                data.ptBalAfterUser1,
                data.ptBalBeforeUser1,
                "PT balance of YT receiver after deposit is wrong"
            );
            assertEq(
                data.ptBalAfterUser2,
                data.ptBalBeforeUser2 + receivedShares,
                "PT balance of PT receiver after deposit is wrong"
            );
            assertEq(
                data.ytBalAfterUser1,
                data.ytBalBeforeUser1 + receivedShares,
                "YT balance of YT receiver after deposit is wrong"
            );
            assertEq(
                data.ytBalAfterUser2,
                data.ytBalBeforeUser2,
                "YT balance of PT receiver after deposit is wrong"
            );

            assertEq(
                data.ibtBalPTContractAfter,
                data.ibtBalPTContractBefore + data.assetsInIBT,
                "IBT balance of PT contract after deposit is wrong"
            );
        }
    }

    /**
     * @dev Internal function for testing basic PT deposit functionality with slippage protection
     * @param assets Amount of assets to deposit
     * @param ytReceiver Address of the YT receiver
     * @param ptReceiver Address of the PT receiver
     * @return receivedShares Amount of shares received
     */
    function _testPTDeposit3(
        uint256 assets,
        address ytReceiver,
        address ptReceiver,
        bool minShares
    ) internal returns (uint256 receivedShares) {
        ptFunctionsData2 memory data;

        // data before
        data.assetBalBefore = IERC20(underlying).balanceOf(address(this));
        data.ptBalBeforeUser1 = IERC20(pt).balanceOf(ytReceiver);
        data.ytBalBeforeUser1 = IERC20(yt).balanceOf(ytReceiver);

        data.ptBalBeforeUser2 = IERC20(pt).balanceOf(ptReceiver);
        data.ytBalBeforeUser2 = IERC20(yt).balanceOf(ptReceiver);
        data.ibtBalPTContractBefore = IERC20(ibt).balanceOf(address(pt));

        // data global
        data.expectedShares1 = _amountMinusFee(
            IERC4626(ibt).previewDeposit(assets),
            IRegistry(registry).getTokenizationFee()
        ).mulDiv(IPrincipalToken(pt).getIBTRate(), IPrincipalToken(pt).getPTRate());
        data.expectedShares2 = IPrincipalToken(pt).previewDeposit(assets);
        data.assetsInIBT = IERC4626(ibt).previewDeposit(assets);

        // deposit
        if (data.expectedShares2 != 0) {
            if (minShares) {
                bytes memory revertData = abi.encodeWithSignature(
                    "ERC5143SlippageProtectionFailed()"
                );
                vm.expectRevert(revertData);
                IPrincipalToken(pt).deposit(
                    assets,
                    ptReceiver,
                    ytReceiver,
                    data.expectedShares2 + _getPrecision(IBT_UNIT) * assets
                );
            }

            receivedShares = IPrincipalToken(pt).deposit(assets, ptReceiver, ytReceiver);

            // data after
            data.assetBalAfter = IERC20(underlying).balanceOf(address(this));
            data.ptBalAfterUser1 = IPrincipalToken(pt).balanceOf(ytReceiver);
            data.ytBalAfterUser1 = IYieldToken(yt).balanceOf(ytReceiver);
            data.ptBalAfterUser2 = IPrincipalToken(pt).balanceOf(ptReceiver);
            data.ytBalAfterUser2 = IYieldToken(yt).balanceOf(ptReceiver);
            data.ibtBalPTContractAfter = IERC4626(ibt).balanceOf(address(pt));

            // assertions
            if (assets > 10000) {
                assertApproxEqRel(
                    data.expectedShares1,
                    data.expectedShares2,
                    1e15,
                    "previewDeposit does not match the calculated value"
                );

                assertApproxEqRel(
                    receivedShares,
                    data.expectedShares2,
                    1e15,
                    "Received shares from deposit are not as expected (previewDeposit)"
                );
            } else {
                assertApproxEqAbs(
                    data.expectedShares1,
                    data.expectedShares2,
                    _getPrecision(IBT_UNIT),
                    "previewDeposit does not match the calculated value"
                );

                assertApproxEqAbs(
                    receivedShares,
                    data.expectedShares2,
                    _getPrecision(IBT_UNIT),
                    "Received shares from deposit are not as expected (previewDeposit)"
                );
            }

            assertGe(
                receivedShares,
                data.expectedShares2,
                "previewDeposit must round down compared to real received amount of shares"
            );

            assertEq(
                data.assetBalBefore,
                data.assetBalAfter + assets,
                "Asset balance after deposit is wrong"
            );
            assertEq(
                data.ptBalAfterUser1,
                data.ptBalBeforeUser1,
                "PT balance of YT receiver after deposit is wrong"
            );
            assertEq(
                data.ptBalAfterUser2,
                data.ptBalBeforeUser2 + receivedShares,
                "PT balance of PT receiver after deposit is wrong"
            );
            assertEq(
                data.ytBalAfterUser1,
                data.ytBalBeforeUser1 + receivedShares,
                "YT balance of YT receiver after deposit is wrong"
            );
            assertEq(
                data.ytBalAfterUser2,
                data.ytBalBeforeUser2,
                "YT balance of PT receiver after deposit is wrong"
            );

            assertEq(
                data.ibtBalPTContractAfter,
                data.ibtBalPTContractBefore + data.assetsInIBT,
                "IBT balance of PT contract after deposit is wrong"
            );
        }
    }

    /**
     * @dev Internal function for testing basic PT depositIBT functionality
     * @param ibts Amount of IBT to deposit
     * @param receiver Address of the receiver
     * @return receivedShares Amount of shares received
     */
    function _testPTDepositIBT(
        uint256 ibts,
        address receiver
    ) internal returns (uint256 receivedShares) {
        ptFunctionsData memory data;

        // data before
        data.ibtBalBefore = IERC20(ibt).balanceOf(address(this));
        data.ptBalBeforeReceiver = IERC20(pt).balanceOf(receiver);
        data.ytBalBeforeReceiver = IERC20(yt).balanceOf(receiver);
        data.ibtBalPTContractBefore = IERC20(ibt).balanceOf(address(pt));

        // data global
        data.expectedShares1 = _amountMinusFee(ibts, IRegistry(registry).getTokenizationFee())
            .mulDiv(IPrincipalToken(pt).getIBTRate(), IPrincipalToken(pt).getPTRate());
        data.expectedShares2 = IPrincipalToken(pt).previewDepositIBT(ibts);

        // depositIBT
        if (data.expectedShares2 != 0) {
            receivedShares = IPrincipalToken(pt).depositIBT(ibts, receiver);

            // data after
            data.ibtBalAfter = IERC20(ibt).balanceOf(address(this));
            data.ptBalAfterReceiver = IPrincipalToken(pt).balanceOf(receiver);
            data.ytBalAfterReceiver = IYieldToken(yt).balanceOf(receiver);
            data.ibtBalPTContractAfter = IERC4626(ibt).balanceOf(address(pt));

            // assertions
            assertApproxEqAbs(
                data.expectedShares1,
                data.expectedShares2,
                10,
                "previewDeposit does not match the calculated value"
            );

            assertApproxEqAbs(
                receivedShares,
                data.expectedShares2,
                10,
                "Received shares from deposit are not as expected (previewDeposit)"
            );

            assertGe(
                receivedShares,
                data.expectedShares2,
                "previewDeposit must round down compared to real received amount of shares"
            );

            assertEq(
                data.ibtBalBefore,
                data.ibtBalAfter + ibts,
                "IBT balance after deposit is wrong"
            );
            assertEq(
                data.ptBalAfterReceiver,
                data.ptBalBeforeReceiver + receivedShares,
                "PT balance after deposit is wrong"
            );
            assertEq(
                data.ytBalAfterReceiver,
                data.ytBalBeforeReceiver + receivedShares,
                "YT balance after deposit is wrong"
            );

            assertEq(
                data.ibtBalPTContractAfter,
                data.ibtBalPTContractBefore + ibts,
                "IBT balance of PT contract after deposit is wrong"
            );
        }
    }

    /**
     * @dev Internal function for testing basic PT depositIBT functionality
     * @param ibts Amount of IBT to deposit
     * @param ytReceiver Address of the YT receiver
     * @param ptReceiver Address of the PT receiver
     * @return receivedShares Amount of shares received
     */
    function _testPTDepositIBT2(
        uint256 ibts,
        address ytReceiver,
        address ptReceiver
    ) internal returns (uint256 receivedShares) {
        ptFunctionsData2 memory data;

        // data before
        data.ibtBalBefore = IERC20(ibt).balanceOf(address(this));
        data.ptBalBeforeUser1 = IERC20(pt).balanceOf(ytReceiver);
        data.ytBalBeforeUser1 = IERC20(yt).balanceOf(ytReceiver);

        data.ptBalBeforeUser2 = IERC20(pt).balanceOf(ptReceiver);
        data.ytBalBeforeUser2 = IERC20(yt).balanceOf(ptReceiver);
        data.ibtBalPTContractBefore = IERC20(ibt).balanceOf(address(pt));

        // data global
        data.expectedShares1 = _amountMinusFee(ibts, IRegistry(registry).getTokenizationFee())
            .mulDiv(IPrincipalToken(pt).getIBTRate(), IPrincipalToken(pt).getPTRate());
        data.expectedShares2 = IPrincipalToken(pt).previewDepositIBT(ibts);

        // depositIBT
        if (data.expectedShares2 != 0) {
            receivedShares = IPrincipalToken(pt).depositIBT(ibts, ptReceiver, ytReceiver);

            // data after
            data.ibtBalAfter = IERC20(ibt).balanceOf(address(this));
            data.ptBalAfterUser1 = IPrincipalToken(pt).balanceOf(ytReceiver);
            data.ytBalAfterUser1 = IYieldToken(yt).balanceOf(ytReceiver);
            data.ptBalAfterUser2 = IPrincipalToken(pt).balanceOf(ptReceiver);
            data.ytBalAfterUser2 = IYieldToken(yt).balanceOf(ptReceiver);
            data.ibtBalPTContractAfter = IERC4626(ibt).balanceOf(address(pt));

            // assertions
            assertApproxEqAbs(
                data.expectedShares1,
                data.expectedShares2,
                10,
                "previewDeposit does not match the calculated value"
            );

            assertApproxEqAbs(
                receivedShares,
                data.expectedShares2,
                10,
                "Received shares from deposit are not as expected (previewDeposit)"
            );

            assertGe(
                receivedShares,
                data.expectedShares2,
                "previewDeposit must round down compared to real received amount of shares"
            );

            assertEq(
                data.ibtBalBefore,
                data.ibtBalAfter + ibts,
                "IBT balance after deposit is wrong"
            );

            assertEq(
                data.ptBalAfterUser1,
                data.ptBalBeforeUser1,
                "PT balance of YT receiver after deposit is wrong"
            );
            assertEq(
                data.ptBalAfterUser2,
                data.ptBalBeforeUser2 + receivedShares,
                "PT balance of PT receiver after deposit is wrong"
            );
            assertEq(
                data.ytBalAfterUser1,
                data.ytBalBeforeUser1 + receivedShares,
                "YT balance of YT receiver after deposit is wrong"
            );
            assertEq(
                data.ytBalAfterUser2,
                data.ytBalBeforeUser2,
                "YT balance of PT receiver after deposit is wrong"
            );

            assertEq(
                data.ibtBalPTContractAfter,
                data.ibtBalPTContractBefore + ibts,
                "IBT balance of PT contract after deposit is wrong"
            );
        }
    }

    /**
     * @dev Internal function for testing basic PT depositIBT functionality with slippage protection
     * @param ibts Amount of IBT to deposit
     * @param ytReceiver Address of the YT receiver
     * @param ptReceiver Address of the PT receiver
     * @return receivedShares Amount of shares received
     */
    function _testPTDepositIBT3(
        uint256 ibts,
        address ytReceiver,
        address ptReceiver,
        bool minShares
    ) internal returns (uint256 receivedShares) {
        ptFunctionsData2 memory data;

        // data before
        data.ibtBalBefore = IERC20(ibt).balanceOf(address(this));
        data.ptBalBeforeUser1 = IERC20(pt).balanceOf(ytReceiver);
        data.ytBalBeforeUser1 = IERC20(yt).balanceOf(ytReceiver);

        data.ptBalBeforeUser2 = IERC20(pt).balanceOf(ptReceiver);
        data.ytBalBeforeUser2 = IERC20(yt).balanceOf(ptReceiver);
        data.ibtBalPTContractBefore = IERC20(ibt).balanceOf(address(pt));

        // data global
        data.expectedShares1 = _amountMinusFee(ibts, IRegistry(registry).getTokenizationFee())
            .mulDiv(IPrincipalToken(pt).getIBTRate(), IPrincipalToken(pt).getPTRate());
        data.expectedShares2 = IPrincipalToken(pt).previewDepositIBT(ibts);

        // depositIBT
        if (data.expectedShares2 != 0) {
            if (minShares) {
                bytes memory revertData = abi.encodeWithSignature(
                    "ERC5143SlippageProtectionFailed()"
                );
                vm.expectRevert(revertData);
                IPrincipalToken(pt).depositIBT(
                    ibts,
                    ptReceiver,
                    ytReceiver,
                    data.expectedShares2 + _getPrecision(IBT_UNIT) * ibts
                );
            }
            receivedShares = IPrincipalToken(pt).depositIBT(ibts, ptReceiver, ytReceiver);

            // data after
            data.ibtBalAfter = IERC20(ibt).balanceOf(address(this));
            data.ptBalAfterUser1 = IPrincipalToken(pt).balanceOf(ytReceiver);
            data.ytBalAfterUser1 = IYieldToken(yt).balanceOf(ytReceiver);
            data.ptBalAfterUser2 = IPrincipalToken(pt).balanceOf(ptReceiver);
            data.ytBalAfterUser2 = IYieldToken(yt).balanceOf(ptReceiver);
            data.ibtBalPTContractAfter = IERC4626(ibt).balanceOf(address(pt));

            // assertions
            assertApproxEqAbs(
                data.expectedShares1,
                data.expectedShares2,
                10,
                "previewDeposit does not match the calculated value"
            );

            assertApproxEqAbs(
                receivedShares,
                data.expectedShares2,
                10,
                "Received shares from deposit are not as expected (previewDeposit)"
            );

            assertGe(
                receivedShares,
                data.expectedShares2,
                "previewDeposit must round down compared to real received amount of shares"
            );

            assertEq(
                data.ibtBalBefore,
                data.ibtBalAfter + ibts,
                "IBT balance after deposit is wrong"
            );

            assertEq(
                data.ptBalAfterUser1,
                data.ptBalBeforeUser1,
                "PT balance of YT receiver after deposit is wrong"
            );
            assertEq(
                data.ptBalAfterUser2,
                data.ptBalBeforeUser2 + receivedShares,
                "PT balance of PT receiver after deposit is wrong"
            );
            assertEq(
                data.ytBalAfterUser1,
                data.ytBalBeforeUser1 + receivedShares,
                "YT balance of YT receiver after deposit is wrong"
            );
            assertEq(
                data.ytBalAfterUser2,
                data.ytBalBeforeUser2,
                "YT balance of PT receiver after deposit is wrong"
            );

            assertEq(
                data.ibtBalPTContractAfter,
                data.ibtBalPTContractBefore + ibts,
                "IBT balance of PT contract after deposit is wrong"
            );
        }
    }

    /**
     * @dev Internal function for testing basic PT withdraw with max shares
     * @param assets Amount of assets to receive
     * @param owner Owner of the shares to redeem
     * @return burntShares Amount of shares burnt for withdrawing assets
     */
    function _testPTWithdraw(uint256 assets, address owner) internal returns (uint256 burntShares) {
        ptFunctionsData memory data;

        // data before
        data.assetBalBefore = IERC20(underlying).balanceOf(owner);
        data.ptBalBefore = IERC20(pt).balanceOf(owner);
        data.ytBalBefore = IERC20(yt).balanceOf(owner);
        data.ibtBalPTContractBefore = IERC20(ibt).balanceOf(address(pt));

        // data global
        data.expectedShares1 = IPrincipalToken(pt).previewWithdraw(assets);
        data.assetsInIBT = IERC4626(ibt).convertToShares(assets);

        if (data.expectedShares1 > 0) {
            // withdraw
            bytes memory revertData = abi.encodeWithSignature("ERC5143SlippageProtectionFailed()");
            vm.expectRevert(revertData);
            IPrincipalToken(pt).withdraw(assets, owner, owner, data.expectedShares1 - 1);

            burntShares = IPrincipalToken(pt).withdraw(assets, owner, owner, data.expectedShares1);

            // data after
            data.assetBalAfter = IERC20(underlying).balanceOf(owner);
            data.ptBalAfter = IERC20(pt).balanceOf(owner);
            data.ytBalAfter = IERC20(yt).balanceOf(owner);
            data.ibtBalPTContractAfter = IERC4626(ibt).balanceOf(address(pt));

            // assertions
            assertApproxEqAbs(
                burntShares,
                data.expectedShares1,
                _getPrecision(IBT_UNIT),
                "Received assets from withdraw are not as expected (previewWithdraw)"
            );

            assertEq(
                data.assetBalAfter,
                data.assetBalBefore + assets,
                "Underlying balance of owner after withdraw is wrong"
            );
            assertEq(
                data.ptBalBefore,
                data.ptBalAfter + burntShares,
                "PT balance of owner after withdraw is wrong"
            );
            if (block.timestamp > IPrincipalToken(pt).maturity()) {
                assertEq(
                    data.ytBalBefore,
                    data.ytBalAfter,
                    "YieldToken balance of owner after withdraw is wrong"
                );
            } else {
                assertEq(
                    data.ytBalBefore,
                    data.ytBalAfter + burntShares,
                    "YieldToken balance of owner after withdraw is wrong"
                );
            }

            assertApproxEqAbs(
                data.ibtBalPTContractBefore,
                data.ibtBalPTContractAfter + data.assetsInIBT,
                _getPrecision(IBT_UNIT),
                "IBT balance of PT contract after withdraw is wrong"
            );
        }
    }

    /**
     * @dev Internal function for testing basic PT withdrawIBT with max shares
     * @param ibts Amount of IBT to receive
     * @param owner Owner of the shares to redeem
     * @return burntShares Amount of shares burnt for withdrawing ibts
     */
    function _testPTWithdrawIBT(
        uint256 ibts,
        address owner
    ) internal returns (uint256 burntShares) {
        ptFunctionsData memory data;

        // data before
        data.ibtBalBefore = IERC20(ibt).balanceOf(owner);
        data.ptBalBefore = IERC20(pt).balanceOf(owner);
        data.ytBalBefore = IERC20(yt).balanceOf(owner);
        data.ibtBalPTContractBefore = IERC20(ibt).balanceOf(address(pt));

        // data global
        data.expectedShares1 = IPrincipalToken(pt).previewWithdrawIBT(ibts);

        if (data.expectedShares1 > 0) {
            // withdraw
            bytes memory revertData = abi.encodeWithSignature("ERC5143SlippageProtectionFailed()");
            vm.expectRevert(revertData);
            IPrincipalToken(pt).withdrawIBT(ibts, owner, owner, data.expectedShares1 - 1);

            burntShares = IPrincipalToken(pt).withdrawIBT(ibts, owner, owner, data.expectedShares1);

            // data after
            data.ibtBalAfter = IERC20(ibt).balanceOf(owner);
            data.ptBalAfter = IPrincipalToken(pt).balanceOf(owner);
            data.ytBalAfter = IYieldToken(yt).balanceOf(owner);
            data.ibtBalPTContractAfter = IERC4626(ibt).balanceOf(address(pt));

            // assertions
            assertEq(
                burntShares,
                data.expectedShares1,
                "Received assets from withdraw are not as expected (previewWithdraw)"
            );

            assertEq(
                data.ibtBalAfter,
                data.ibtBalBefore + ibts,
                "IBT balance of owner after withdraw is wrong"
            );
            assertEq(
                data.ptBalBefore,
                data.ptBalAfter + burntShares,
                "PT balance of owner after withdraw is wrong"
            );
            if (block.timestamp > IPrincipalToken(pt).maturity()) {
                assertEq(
                    data.ytBalBefore,
                    data.ytBalAfter,
                    "YieldToken balance of owner after withdraw is wrong"
                );
            } else {
                assertEq(
                    data.ytBalBefore,
                    data.ytBalAfter + burntShares,
                    "YieldToken balance of owner after withdraw is wrong"
                );
            }

            assertEq(
                data.ibtBalPTContractBefore,
                data.ibtBalPTContractAfter + ibts,
                "IBT balance of PT contract after withdraw is wrong"
            );
        }
    }

    /**
     * @dev Internal function for testing basic PT redeem
     * @param shares Amount of shares to redeem
     * @param owner Owner of the shares to redeem
     * @return receivedAssets Amount of assets received for redeeming shares
     */
    function _testPTRedeem(
        uint256 shares,
        address owner
    ) internal returns (uint256 receivedAssets) {
        ptFunctionsData memory data;

        // data before
        data.assetBalBefore = IERC20(underlying).balanceOf(owner);
        data.ibtBalBefore = IERC4626(ibt).balanceOf(owner);
        data.ptBalBefore = IPrincipalToken(pt).balanceOf(owner);
        data.ytBalBefore = IYieldToken(yt).actualBalanceOf(owner);
        data.ibtBalPTContractBefore = IERC4626(ibt).balanceOf(address(pt));

        // data global
        data.expectedAssets1 = IPrincipalToken(pt).convertToUnderlying(shares);
        data.expectedAssets2 = IPrincipalToken(pt).previewRedeem(shares);

        if (data.expectedAssets2 > 0) {
            // redeem
            receivedAssets = IPrincipalToken(pt).redeem(shares, owner, owner);
            data.assetsInIBT = IERC4626(ibt).convertToShares(receivedAssets);

            // data after
            data.assetBalAfter = IERC20(underlying).balanceOf(owner);
            data.ibtBalAfter = IERC4626(ibt).balanceOf(owner);
            data.ptBalAfter = IPrincipalToken(pt).balanceOf(owner);
            data.ytBalAfter = IYieldToken(yt).actualBalanceOf(owner);
            data.ibtBalPTContractAfter = IERC4626(ibt).balanceOf(address(pt));

            // assertions

            assertApproxEqAbs(
                data.expectedAssets1,
                data.expectedAssets2,
                _getPrecision(ASSET_UNIT),
                "previewRedeem does not match the convert value"
            );

            assertApproxEqAbs(
                receivedAssets,
                data.expectedAssets2,
                _getPrecision(ASSET_UNIT),
                "Received assets from redeem are not as expected (previewRedeem)"
            );
            assertGe(receivedAssets, data.expectedAssets2, "previewRedeem should round down");

            assertEq(
                data.assetBalBefore + receivedAssets,
                data.assetBalAfter,
                "Underlying balance of sender/receiver after redeem is wrong"
            );
            assertEq(
                data.ibtBalBefore,
                data.ibtBalAfter,
                "IBT balance of sender/receiver after redeem is wrong"
            );
            assertEq(
                data.ptBalBefore,
                data.ptBalAfter + shares,
                "PT balance of sender/receiver after redeem is wrong"
            );
            if (block.timestamp > IPrincipalToken(pt).maturity()) {
                assertEq(
                    data.ytBalBefore,
                    data.ytBalAfter,
                    "YieldToken balance of sender/receiver after redeem is wrong"
                );
            } else {
                assertEq(
                    data.ytBalBefore,
                    data.ytBalAfter + shares,
                    "YieldToken balance of sender/receiver after redeem is wrong"
                );
            }

            assertApproxEqAbs(
                data.ibtBalPTContractBefore,
                data.ibtBalPTContractAfter + data.assetsInIBT,
                _getPrecision(IBT_UNIT),
                "IBT balance of PT contract after redeem is wrong"
            );
        }
    }

    /**
     * @dev Internal function for testing basic PT redeem with slippage protection
     * @param shares Amount of shares to redeem
     * @param owner Owner of the shares to redeem
     * @param minAssets the minimum amount of assets the receiver expect to redeem
     * @return receivedAssets Amount of assets received for redeeming shares
     */
    function _testPTRedeem2(
        uint256 shares,
        address owner,
        bool minAssets
    ) internal returns (uint256 receivedAssets) {
        ptFunctionsData memory data;

        // data before
        data.assetBalBefore = IERC20(underlying).balanceOf(owner);
        data.ibtBalBefore = IERC4626(ibt).balanceOf(owner);
        data.ptBalBefore = IPrincipalToken(pt).balanceOf(owner);
        data.ytBalBefore = IYieldToken(yt).actualBalanceOf(owner);
        data.ibtBalPTContractBefore = IERC4626(ibt).balanceOf(address(pt));

        // data global
        data.expectedAssets1 = IPrincipalToken(pt).convertToUnderlying(shares);
        data.expectedAssets2 = IPrincipalToken(pt).previewRedeem(shares);

        if (data.expectedAssets2 > 0) {
            // redeem
            if (minAssets) {
                bytes memory revertData = abi.encodeWithSignature(
                    "ERC5143SlippageProtectionFailed()"
                );
                vm.expectRevert(revertData);
                IPrincipalToken(pt).redeem(shares, owner, owner, data.expectedAssets2 + 1);
                receivedAssets = IPrincipalToken(pt).redeem(
                    shares,
                    owner,
                    owner,
                    data.expectedAssets2
                );
            } else {
                receivedAssets = IPrincipalToken(pt).redeem(shares, owner, owner);
            }
            data.assetsInIBT = IERC4626(ibt).convertToShares(receivedAssets);

            // data after
            data.assetBalAfter = IERC20(underlying).balanceOf(owner);
            data.ibtBalAfter = IERC4626(ibt).balanceOf(owner);
            data.ptBalAfter = IPrincipalToken(pt).balanceOf(owner);
            data.ytBalAfter = IYieldToken(yt).actualBalanceOf(owner);
            data.ibtBalPTContractAfter = IERC4626(ibt).balanceOf(address(pt));

            // assertions

            assertApproxEqAbs(
                data.expectedAssets1,
                data.expectedAssets2,
                _getPrecision(ASSET_UNIT),
                "previewRedeem does not match the convert value"
            );

            assertApproxEqAbs(
                receivedAssets,
                data.expectedAssets2,
                _getPrecision(ASSET_UNIT),
                "Received assets from redeem are not as expected (previewRedeem)"
            );
            assertGe(receivedAssets, data.expectedAssets2, "previewRedeem should round down");

            assertEq(
                data.assetBalBefore + receivedAssets,
                data.assetBalAfter,
                "Underlying balance of sender/receiver after redeem is wrong"
            );
            assertEq(
                data.ibtBalBefore,
                data.ibtBalAfter,
                "IBT balance of sender/receiver after redeem is wrong"
            );
            assertEq(
                data.ptBalBefore,
                data.ptBalAfter + shares,
                "PT balance of sender/receiver after redeem is wrong"
            );
            if (block.timestamp > IPrincipalToken(pt).maturity()) {
                assertEq(
                    data.ytBalBefore,
                    data.ytBalAfter,
                    "YieldToken balance of sender/receiver after redeem is wrong"
                );
            } else {
                assertEq(
                    data.ytBalBefore,
                    data.ytBalAfter + shares,
                    "YieldToken balance of sender/receiver after redeem is wrong"
                );
            }

            assertApproxEqAbs(
                data.ibtBalPTContractBefore,
                data.ibtBalPTContractAfter + data.assetsInIBT,
                _getPrecision(IBT_UNIT),
                "IBT balance of PT contract after redeem is wrong"
            );
        }
    }

    /**
     * @dev Internal function for testing basic PT redeemForIBT
     * @param shares Amount of shares to redeem
     * @param owner Owner of the shares to redeem
     * @return receivedIBTs Amount of IBT received for redeeming shares
     */
    function _testPTRedeemForIBT(
        uint256 shares,
        address owner
    ) internal returns (uint256 receivedIBTs) {
        ptFunctionsData memory data;

        // data before
        data.assetBalBefore = IERC20(underlying).balanceOf(owner);
        data.ibtBalBefore = IERC4626(ibt).balanceOf(owner);
        data.ptBalBefore = IPrincipalToken(pt).balanceOf(owner);
        data.ytBalBefore = IYieldToken(yt).actualBalanceOf(owner);
        data.ibtBalPTContractBefore = IERC4626(ibt).balanceOf(address(pt));

        // data global
        data.expectedIBTs1 = shares.mulDiv(
            IPrincipalToken(pt).getPTRate(),
            IPrincipalToken(pt).getIBTRate()
        );
        data.expectedIBTs2 = IPrincipalToken(pt).previewRedeemForIBT(shares);

        if (data.expectedIBTs2 > 0) {
            // redeem
            receivedIBTs = IPrincipalToken(pt).redeemForIBT(shares, owner, owner);

            // data after
            data.assetBalAfter = IERC20(underlying).balanceOf(owner);
            data.ibtBalAfter = IERC4626(ibt).balanceOf(owner);
            data.ptBalAfter = IPrincipalToken(pt).balanceOf(owner);
            data.ytBalAfter = IYieldToken(yt).actualBalanceOf(owner);
            data.ibtBalPTContractAfter = IERC4626(ibt).balanceOf(address(pt));

            // assertions

            assertApproxEqAbs(
                data.expectedIBTs1,
                data.expectedIBTs2,
                10,
                "previewRedeemForIBT does not match the convert value"
            );

            assertApproxEqAbs(
                receivedIBTs,
                data.expectedIBTs2,
                10,
                "Received IBTs from redeem are not as expected (previewRedeemForIBT)"
            );
            assertGe(receivedIBTs, data.expectedIBTs2, "previewRedeemForIBT should round down");

            assertEq(
                data.assetBalBefore,
                data.assetBalAfter,
                "Underlying balance of sender/receiver after redeem is wrong"
            );
            assertEq(
                data.ibtBalBefore + receivedIBTs,
                data.ibtBalAfter,
                "IBT balance of sender/receiver after redeem is wrong"
            );
            assertEq(
                data.ptBalBefore,
                data.ptBalAfter + shares,
                "PT balance of sender/receiver after redeem is wrong"
            );
            if (block.timestamp > IPrincipalToken(pt).maturity()) {
                assertEq(
                    data.ytBalBefore,
                    data.ytBalAfter,
                    "YieldToken balance of sender/receiver after redeem is wrong"
                );
            } else {
                assertEq(
                    data.ytBalBefore,
                    data.ytBalAfter + shares,
                    "YieldToken balance of sender/receiver after redeem is wrong"
                );
            }

            assertEq(
                data.ibtBalPTContractBefore,
                data.ibtBalPTContractAfter + receivedIBTs,
                "IBT balance of PT contract after redeem is wrong"
            );
        }
    }

    /**
     * @dev Internal function for testing basic PT redeemForIBT with slippage protection
     * @param shares Amount of shares to redeem
     * @param owner Owner of the shares to redeem
     * @param minAssets the minimum amount of assets the receiver expect to redeem
     * @return receivedIBTs Amount of IBT received for redeeming shares
     */
    function _testPTRedeemForIBT2(
        uint256 shares,
        address owner,
        bool minAssets
    ) internal returns (uint256 receivedIBTs) {
        ptFunctionsData memory data;

        // data before
        data.assetBalBefore = IERC20(underlying).balanceOf(owner);
        data.ibtBalBefore = IERC4626(ibt).balanceOf(owner);
        data.ptBalBefore = IPrincipalToken(pt).balanceOf(owner);
        data.ytBalBefore = IYieldToken(yt).actualBalanceOf(owner);
        data.ibtBalPTContractBefore = IERC4626(ibt).balanceOf(address(pt));

        // data global
        data.expectedIBTs1 = shares.mulDiv(
            IPrincipalToken(pt).getPTRate(),
            IPrincipalToken(pt).getIBTRate()
        );
        data.expectedIBTs2 = IPrincipalToken(pt).previewRedeemForIBT(shares);

        if (data.expectedIBTs2 > 0) {
            // redeem
            if (minAssets) {
                bytes memory revertData = abi.encodeWithSignature(
                    "ERC5143SlippageProtectionFailed()"
                );
                vm.expectRevert(revertData);
                IPrincipalToken(pt).redeem(shares, owner, owner, data.expectedIBTs2 + 1);
                receivedIBTs = IPrincipalToken(pt).redeemForIBT(
                    shares,
                    owner,
                    owner,
                    data.expectedIBTs2
                );
            } else {
                receivedIBTs = IPrincipalToken(pt).redeemForIBT(shares, owner, owner);
            }

            // data after
            data.assetBalAfter = IERC20(underlying).balanceOf(owner);
            data.ibtBalAfter = IERC4626(ibt).balanceOf(owner);
            data.ptBalAfter = IPrincipalToken(pt).balanceOf(owner);
            data.ytBalAfter = IYieldToken(yt).actualBalanceOf(owner);
            data.ibtBalPTContractAfter = IERC4626(ibt).balanceOf(address(pt));

            // assertions

            assertApproxEqAbs(
                data.expectedIBTs1,
                data.expectedIBTs2,
                10,
                "previewRedeemForIBT does not match the convert value"
            );

            assertApproxEqAbs(
                receivedIBTs,
                data.expectedIBTs2,
                10,
                "Received IBTs from redeem are not as expected (previewRedeemForIBT)"
            );
            assertGe(receivedIBTs, data.expectedIBTs2, "previewRedeemForIBT should round down");

            assertEq(
                data.assetBalBefore,
                data.assetBalAfter,
                "Underlying balance of sender/receiver after redeem is wrong"
            );
            assertEq(
                data.ibtBalBefore + receivedIBTs,
                data.ibtBalAfter,
                "IBT balance of sender/receiver after redeem is wrong"
            );
            assertEq(
                data.ptBalBefore,
                data.ptBalAfter + shares,
                "PT balance of sender/receiver after redeem is wrong"
            );
            if (block.timestamp > IPrincipalToken(pt).maturity()) {
                assertEq(
                    data.ytBalBefore,
                    data.ytBalAfter,
                    "YieldToken balance of sender/receiver after redeem is wrong"
                );
            } else {
                assertEq(
                    data.ytBalBefore,
                    data.ytBalAfter + shares,
                    "YieldToken balance of sender/receiver after redeem is wrong"
                );
            }

            assertEq(
                data.ibtBalPTContractBefore,
                data.ibtBalPTContractAfter + receivedIBTs,
                "IBT balance of PT contract after redeem is wrong"
            );
        }
    }

    /**
     * @dev Internal function for testing PT redeeming all shares shares + claiming yield
     * @param owner Owner of the shares and yield being withdrawn
     * @return assets Amount of assets received for withdrawing all shares and claiming yield
     */
    function _testPTMaxRedeemAndClaimYield(address owner) internal returns (uint256 assets) {
        ptFunctionsData memory data;

        // data before
        data.assetBalBefore = IERC20(underlying).balanceOf(owner);
        data.ibtBalBefore = IERC4626(ibt).balanceOf(owner);
        data.ptBalBefore = IPrincipalToken(pt).balanceOf(owner);
        data.ytBalBefore = IYieldToken(yt).balanceOf(owner);
        data.ibtBalPTContractBefore = IERC4626(ibt).balanceOf(address(pt));

        // data global
        uint256 previewYield = IERC4626(ibt).previewRedeem(
            IPrincipalToken(pt).getCurrentYieldOfUserInIBT(owner)
        );
        uint256 maxRedeem = IPrincipalToken(pt).maxRedeem(owner);
        data.expectedAssets1 = IPrincipalToken(pt).previewRedeem(maxRedeem) + previewYield;

        if (data.expectedAssets1 > 0) {
            assets = IPrincipalToken(pt).redeem(maxRedeem, owner, owner);
            vm.expectRevert();
            IPrincipalToken(pt).claimYield(owner, previewYield + 1000);
            assets += IPrincipalToken(pt).claimYield(owner, previewYield);

            // data after
            data.assetBalAfter = IERC20(underlying).balanceOf(owner);
            data.ibtBalAfter = IERC4626(ibt).balanceOf(owner);
            data.ptBalAfter = IPrincipalToken(pt).balanceOf(owner);
            data.ytBalAfter = IYieldToken(yt).balanceOf(owner);
            data.ibtBalPTContractAfter = IERC4626(ibt).balanceOf(address(pt));

            if (assets < ASSET_UNIT) {
                assertApproxEqAbs(
                    assets,
                    data.expectedAssets1,
                    _getPrecision(ASSET_UNIT),
                    "Received assets from Redeeming and claiming yield are not as expected"
                ); // with small amounts absolute difference is more relevant
            } else {
                assertApproxEqRel(
                    assets,
                    data.expectedAssets1,
                    1e14,
                    "Received assets from Redeeming and claiming yield are not as expected"
                ); // with reasonably high amounts relative difference is more relevant
            }
            assertGe(
                assets,
                data.expectedAssets1,
                "Received assets from Redeeming and claiming yield are lower than expected (breaking invariant)"
            );

            assertEq(
                data.assetBalBefore + assets,
                data.assetBalAfter,
                "Underlying balance of sender/receiver after Redeeming and claiming yield is wrong"
            );
            assertEq(
                data.ibtBalBefore,
                data.ibtBalAfter,
                "IBT balance of sender/receiver after Redeeming and claiming yield is wrong"
            );
            if (block.timestamp > IPrincipalToken(pt).maturity()) {
                assertEq(
                    0,
                    data.ptBalAfter,
                    "PT balance of sender/receiver after max redeem and claimYield is wrong"
                );
                assertEq(
                    data.ytBalBefore,
                    data.ytBalAfter,
                    "YieldToken balance of sender/receiver after Redeem and ClaimYield is wrong"
                );
            } else {
                assertEq(
                    data.ptBalBefore > data.ytBalBefore ? data.ptBalBefore - data.ytBalBefore : 0,
                    data.ptBalAfter,
                    "PT balance of sender/receiver after Redeem and ClaimYield is wrong"
                );
                assertEq(
                    data.ptBalBefore > data.ytBalBefore ? 0 : data.ytBalBefore - data.ptBalBefore,
                    data.ytBalAfter,
                    "YieldToken balance of sender/receiver after Redeem and ClaimYield is wrong"
                );
            }
        }
    }

    function _testPTMaxRedeemAndClaimYieldInIBT(address owner) internal returns (uint256 ibts) {
        ptFunctionsData memory data;

        // data before
        data.assetBalBefore = IERC20(underlying).balanceOf(owner);
        data.ibtBalBefore = IERC4626(ibt).balanceOf(owner);
        data.ptBalBefore = IPrincipalToken(pt).balanceOf(owner);
        data.ytBalBefore = IYieldToken(yt).actualBalanceOf(owner);
        data.ibtBalPTContractBefore = IERC4626(ibt).balanceOf(address(pt));

        // data global
        uint256 previewYieldInIBT = IPrincipalToken(pt).getCurrentYieldOfUserInIBT(owner);
        uint256 maxRedeem = IPrincipalToken(pt).maxRedeem(owner);
        data.expectedIbts1 = IPrincipalToken(pt).previewRedeemForIBT(maxRedeem) + previewYieldInIBT;

        if (data.expectedIbts1 > 0) {
            ibts = IPrincipalToken(pt).redeemForIBT(maxRedeem, owner, owner);
            ibts += IPrincipalToken(pt).claimYieldInIBT(owner, 0);

            // data after
            data.assetBalAfter = IERC20(underlying).balanceOf(owner);
            data.ibtBalAfter = IERC4626(ibt).balanceOf(owner);
            data.ptBalAfter = IPrincipalToken(pt).balanceOf(owner);
            data.ytBalAfter = IYieldToken(yt).actualBalanceOf(owner);
            data.ibtBalPTContractAfter = IERC4626(ibt).balanceOf(address(pt));

            if (ibts < IBT_UNIT) {
                assertApproxEqAbs(
                    ibts,
                    data.expectedIbts1,
                    _getPrecision(IBT_UNIT),
                    "Received assets from max redeem and claimYield are not as expected"
                ); // with small amounts absolute difference is more relevant
            } else {
                assertApproxEqRel(
                    ibts,
                    data.expectedIbts1,
                    1e13,
                    "Received assets from max redeem and claimYield are not as expected"
                ); // with reasonably high amounts relative difference is more relevant
            }
            assertGe(
                ibts,
                data.expectedIbts1,
                "Received assets from max redeem and claimYield are lower than expected (breaking invariant)"
            );

            assertEq(
                data.assetBalBefore,
                data.assetBalAfter,
                "Underlying balance of sender/receiver after max redeem and claimYield is wrong"
            );
            assertEq(
                data.ibtBalBefore + ibts,
                data.ibtBalAfter,
                "IBT balance of sender/receiver after max redeem and claimYield is wrong"
            );

            if (block.timestamp > IPrincipalToken(pt).maturity()) {
                assertEq(
                    0,
                    data.ptBalAfter,
                    "PT balance of sender/receiver after max redeem and claimYield is wrong"
                );
                assertEq(
                    data.ytBalBefore,
                    data.ytBalAfter,
                    "YieldToken balance of sender/receiver after max redeem and claimYield is wrong"
                );
            } else {
                assertEq(
                    data.ptBalBefore > data.ytBalBefore ? data.ptBalBefore - data.ytBalBefore : 0,
                    data.ptBalAfter,
                    "PT balance of sender/receiver after max redeem and claimYield is wrong"
                );
                assertEq(
                    data.ytBalBefore > data.ptBalBefore ? data.ytBalBefore - data.ptBalBefore : 0,
                    data.ytBalAfter,
                    "YieldToken balance of sender/receiver after max redeem and claimYield is wrong"
                );
            }

            assertApproxEqAbs(
                data.ibtBalPTContractBefore - data.ibtBalPTContractAfter,
                ibts,
                _getPrecision(IBT_UNIT),
                "IBT balance of PT contract after max redeem and claimYield is wrong"
            );
        }
    }

    function _testAddLiquiditytoCurvePool(uint256 assetsA, uint256 assetsB) public {
        IERC20(underlying).approve(ibt, assetsA);
        IERC20(underlying).approve(pt, assetsB);

        // deposit assets in IBT then in PT
        uint256 amountIbt = IERC4626(ibt).deposit(assetsA, address(this));
        uint256 amountPt = _testPTDeposit(assetsB, address(this));

        if (amountIbt != 0 && amountPt != 0) {
            // add liquidity to curve pool
            IERC4626(ibt).approve(curvePool, amountIbt);
            IPrincipalToken(pt).approve(curvePool, amountPt);
            (bool success, ) = curvePool.call(
                abi.encodeWithSelector(0x0b4c7e4d, [amountIbt, amountPt], 0)
            );
            if (!success) {
                revert FailedToAddLiquidity();
            }
        }
    }

    /* INTERNAL FOR PT FULL CYCLE TEST */

    /* ROUTER */

    /**
     * @dev Internal function for testing router WRAP_VAULT_IN_4626_ADAPTER command
     * @param vaultShares Amount of vault shares to deposit
     * @return receivedWrapperShares Amount of wrapper shares received
     */
    function _testRouterWrapVaultInAdapter(
        uint256 vaultShares
    ) internal returns (uint256 receivedWrapperShares) {
        routerCommandsData memory data;

        // data before
        data.ibtBalBefore = IERC20(ibt).balanceOf(address(this));
        data.wrapperBalBefore = IERC20(spectra4626Wrapper).balanceOf(address(this));
        data.ibtBalRouterContractBefore = IERC20(ibt).balanceOf(address(router));
        data.wrapperBalRouterContractBefore = IERC20(spectra4626Wrapper).balanceOf(address(router));

        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.WRAP_VAULT_IN_4626_ADAPTER))
        );
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(ibt, vaultShares);
        inputs[1] = abi.encode(spectra4626Wrapper, Constants.CONTRACT_BALANCE, address(this), 0);

        data.expected2 = ISpectra4626Wrapper(spectra4626Wrapper).previewWrap(vaultShares);

        if (data.expected2 != 0) {
            data.routerPreviewRate = IRouter(router).previewRate(commands, inputs);
            data.expected1 = vaultShares.mulDiv(data.routerPreviewRate, 1e27, Math.Rounding.Ceil);

            IRouter(router).execute(commands, inputs);

            // data after
            data.ibtBalAfter = IERC20(ibt).balanceOf(address(this));
            data.wrapperBalAfter = IERC20(spectra4626Wrapper).balanceOf(address(this));
            data.ibtBalRouterContractAfter = IERC20(ibt).balanceOf(address(router));
            data.wrapperBalRouterContractAfter = IERC20(spectra4626Wrapper).balanceOf(
                address(router)
            );

            receivedWrapperShares = data.wrapperBalAfter - data.wrapperBalBefore;

            assertEq(
                data.ibtBalRouterContractAfter,
                data.ibtBalRouterContractBefore,
                "Vault balance of Router contract after execution is wrong"
            );
            assertEq(
                data.wrapperBalRouterContractAfter,
                data.wrapperBalRouterContractBefore,
                "Wrapper balance of Router contract after execution is wrong"
            );

            assertEq(data.expected2, data.expected1, "Router previewRate is wrong");

            assertEq(data.expected2, receivedWrapperShares, "Wrapper balance after wrap is wrong");
            assertEq(
                data.ibtBalBefore,
                data.ibtBalAfter + vaultShares,
                "Vault balance after wrap is wrong"
            );
        }
    }

    /**
     * @dev Internal function for testing router UNWRAP_VAULT_FROM_4626_ADAPTER command
     * @param wrapperShares Amount of wrapper shares to redeem
     * @return receivedVaultShares Amount of vault shares received
     */
    function _testRouterUnwrapVaultFromAdapter(
        uint256 wrapperShares
    ) internal returns (uint256 receivedVaultShares) {
        routerCommandsData memory data;

        // data before
        data.ibtBalBefore = IERC20(ibt).balanceOf(address(this));
        data.wrapperBalBefore = IERC20(spectra4626Wrapper).balanceOf(address(this));
        data.ibtBalRouterContractBefore = IERC20(ibt).balanceOf(address(router));
        data.wrapperBalRouterContractBefore = IERC20(spectra4626Wrapper).balanceOf(address(router));

        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.UNWRAP_VAULT_FROM_4626_ADAPTER))
        );
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(spectra4626Wrapper, wrapperShares);
        inputs[1] = abi.encode(spectra4626Wrapper, Constants.CONTRACT_BALANCE, address(this), 0);

        data.expected2 = ISpectra4626Wrapper(spectra4626Wrapper).previewUnwrap(wrapperShares);

        if (data.expected2 != 0) {
            data.routerPreviewRate = IRouter(router).previewRate(commands, inputs);
            data.expected1 = wrapperShares.mulDiv(data.routerPreviewRate, 1e27, Math.Rounding.Ceil);

            IRouter(router).execute(commands, inputs);

            // data after
            data.ibtBalAfter = IERC20(ibt).balanceOf(address(this));
            data.wrapperBalAfter = IERC20(spectra4626Wrapper).balanceOf(address(this));
            data.ibtBalRouterContractAfter = IERC20(ibt).balanceOf(address(router));
            data.wrapperBalRouterContractAfter = IERC20(spectra4626Wrapper).balanceOf(
                address(router)
            );

            receivedVaultShares = data.ibtBalAfter - data.ibtBalBefore;

            assertEq(
                data.ibtBalRouterContractAfter,
                data.ibtBalRouterContractBefore,
                "Vault balance of Router contract after execution is wrong"
            );
            assertEq(
                data.wrapperBalRouterContractAfter,
                data.wrapperBalRouterContractBefore,
                "Wrapper balance of Router contract after execution is wrong"
            );

            assertEq(data.expected2, data.expected1, "Router previewRate is wrong");

            assertEq(data.expected2, receivedVaultShares, "Vault balance after unwrap is wrong");
            assertEq(
                data.wrapperBalBefore,
                data.wrapperBalAfter + wrapperShares,
                "Wrapper balance after unwrap is wrong"
            );
        }
    }

    /**
     * @dev Internal function for testing router DEPOSIT_ASSET_IN_IBT command
     * @param assets Amount of assets to deposit
     * @return receivedShares Amount of PT shares received
     */
    function _testRouterDepositAssetInIBT(
        uint256 assets
    ) internal returns (uint256 receivedShares) {
        routerCommandsData memory data;

        // data before
        data.assetBalBefore = IERC20(underlying).balanceOf(address(this));
        data.ibtBalBefore = IERC20(ibt).balanceOf(address(this));
        data.assetBalRouterContractBefore = IERC20(underlying).balanceOf(address(router));
        data.ibtBalRouterContractBefore = IERC20(ibt).balanceOf(address(router));

        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.DEPOSIT_ASSET_IN_IBT))
        );
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(underlying, assets);
        inputs[1] = abi.encode(ibt, Constants.CONTRACT_BALANCE, address(this));

        data.expected2 = IERC4626(ibt).previewDeposit(assets);

        if (data.expected2 != 0) {
            data.routerPreviewRate = IRouter(router).previewRate(commands, inputs);
            data.expected1 = assets.mulDiv(data.routerPreviewRate, 1e27, Math.Rounding.Ceil);

            IRouter(router).execute(commands, inputs);

            // data after
            data.assetBalAfter = IERC20(underlying).balanceOf(address(this));
            data.ibtBalAfter = IERC20(ibt).balanceOf(address(this));
            data.assetBalRouterContractAfter = IERC20(underlying).balanceOf(address(router));
            data.ibtBalRouterContractAfter = IERC20(ibt).balanceOf(address(router));

            receivedShares = data.ibtBalAfter - data.ibtBalBefore;

            assertEq(
                data.assetBalRouterContractAfter,
                data.assetBalRouterContractBefore,
                "Asset balance of Router contract after execution is wrong"
            );
            assertEq(
                data.ibtBalRouterContractAfter,
                data.ibtBalRouterContractBefore,
                "IBT balance of Router contract after execution is wrong"
            );

            assertEq(data.expected2, data.expected1, "Router previewRate is wrong");

            assertEq(data.expected2, receivedShares, "IBT balance after deposit is wrong");
            assertEq(
                data.assetBalBefore,
                data.assetBalAfter + assets,
                "Asset balance after deposit is wrong"
            );
        }
    }

    /**
     * @dev Internal function for testing basic router DEPOSIT_ASSET_IN_PT command
     * @param assets Amount of assets to deposit
     * @return receivedShares Amount of PT shares received
     */
    function _testRouterDepositAssetInPT(uint256 assets) internal returns (uint256 receivedShares) {
        routerCommandsData memory data;

        // data before
        data.assetBalBefore = IERC20(underlying).balanceOf(address(this));
        data.ptBalBefore = IERC20(pt).balanceOf(address(this));
        data.ytBalBefore = IERC20(yt).balanceOf(address(this));
        data.ibtBalPTContractBefore = IERC20(ibt).balanceOf(pt);
        data.assetBalRouterContractBefore = IERC20(underlying).balanceOf(router);
        data.ytBalRouterContractBefore = IERC20(yt).balanceOf(router);
        data.ptBalRouterContractBefore = IERC20(pt).balanceOf(router);
        data.assetsInIBT = IERC4626(ibt).previewDeposit(assets);

        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.DEPOSIT_ASSET_IN_PT))
        );
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(underlying, assets);
        inputs[1] = abi.encode(pt, Constants.CONTRACT_BALANCE, address(this), address(this), 0);

        data.expected2 = IPrincipalToken(pt).previewDeposit(assets);

        if (data.expected2 != 0) {
            data.routerPreviewRate = IRouter(router).previewRate(commands, inputs);
            data.expected1 = assets.mulDiv(data.routerPreviewRate, 1e27, Math.Rounding.Ceil);

            IRouter(router).execute(commands, inputs);

            // data after
            data.assetBalAfter = IERC20(underlying).balanceOf(address(this));
            data.ptBalAfter = IERC20(pt).balanceOf(address(this));
            data.ytBalAfter = IERC20(yt).balanceOf(address(this));
            data.ibtBalPTContractAfter = IERC20(ibt).balanceOf(pt);
            data.assetBalRouterContractAfter = IERC20(underlying).balanceOf(router);
            data.ytBalRouterContractAfter = IERC20(yt).balanceOf(router);
            data.ptBalRouterContractAfter = IERC20(pt).balanceOf(router);

            receivedShares = data.ptBalAfter - data.ptBalBefore;

            assertEq(
                data.assetBalRouterContractAfter,
                data.assetBalRouterContractBefore,
                "Asset balance of Router contract after execution is wrong"
            );
            assertEq(
                data.ytBalRouterContractAfter,
                data.ytBalRouterContractBefore,
                "YT balance of Router contract after execution is wrong"
            );
            assertEq(
                data.ptBalRouterContractAfter,
                data.ptBalRouterContractBefore,
                "PT balance of Router contract after execution is wrong"
            );

            assertEq(data.expected2, data.expected1, "Router previewRate is wrong");

            assertEq(data.expected2, receivedShares, "PT balance after deposit is wrong");
            assertEq(
                data.ytBalBefore + receivedShares,
                data.ytBalAfter,
                "YT balance after deposit is wrong"
            );
            assertEq(
                data.assetBalBefore,
                data.assetBalAfter + assets,
                "Asset balance after deposit is wrong"
            );

            assertEq(
                data.ibtBalPTContractAfter,
                data.ibtBalPTContractBefore + data.assetsInIBT,
                "IBT balance of PT contract after deposit is wrong"
            );
        }
    }

    /**
     * @dev Internal function for testing basic router DEPOSIT_IBT_IN_PT command
     * @param ibts Amount of IBT to deposit
     * @return receivedShares Amount of PT shares received
     */
    function _testRouterDepositIBTInPT(uint256 ibts) internal returns (uint256 receivedShares) {
        routerCommandsData memory data;

        // data before
        data.ibtBalBefore = IERC20(ibt).balanceOf(address(this));
        data.ptBalBefore = IERC20(pt).balanceOf(address(this));
        data.ytBalBefore = IERC20(yt).balanceOf(address(this));
        data.ibtBalPTContractBefore = IERC20(ibt).balanceOf(pt);
        data.ibtBalRouterContractBefore = IERC20(ibt).balanceOf(router);
        data.ytBalRouterContractBefore = IERC20(yt).balanceOf(router);
        data.ptBalRouterContractBefore = IERC20(pt).balanceOf(router);

        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.DEPOSIT_IBT_IN_PT))
        );
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(ibt, ibts);
        inputs[1] = abi.encode(pt, Constants.CONTRACT_BALANCE, address(this), address(this), 0);

        data.expected2 = IPrincipalToken(pt).previewDepositIBT(ibts);

        if (data.expected2 != 0) {
            data.routerPreviewRate = IRouter(router).previewRate(commands, inputs);
            data.expected1 = ibts.mulDiv(data.routerPreviewRate, 1e27, Math.Rounding.Ceil);

            IRouter(router).execute(commands, inputs);

            // data after
            data.ibtBalAfter = IERC20(ibt).balanceOf(address(this));
            data.ptBalAfter = IERC20(pt).balanceOf(address(this));
            data.ytBalAfter = IERC20(yt).balanceOf(address(this));
            data.ibtBalPTContractAfter = IERC20(ibt).balanceOf(pt);
            data.ibtBalRouterContractAfter = IERC20(ibt).balanceOf(router);
            data.ytBalRouterContractAfter = IERC20(yt).balanceOf(router);
            data.ptBalRouterContractAfter = IERC20(pt).balanceOf(router);

            receivedShares = data.ptBalAfter - data.ptBalBefore;

            assertEq(
                data.ibtBalRouterContractAfter,
                data.ibtBalRouterContractBefore,
                "IBT balance of Router after execution is wrong"
            );
            assertEq(
                data.ytBalRouterContractAfter,
                data.ytBalRouterContractBefore,
                "YT balance of Router contract after execution is wrong"
            );
            assertEq(
                data.ptBalRouterContractAfter,
                data.ptBalRouterContractBefore,
                "PT balance of Router contract after execution is wrong"
            );

            assertEq(data.expected2, data.expected1, "Router previewRate is wrong");

            assertEq(data.expected2, receivedShares, "PT balance after deposit is wrong");
            assertEq(
                data.ytBalBefore + receivedShares,
                data.ytBalAfter,
                "YT balance after deposit is wrong"
            );
            assertEq(
                data.ibtBalBefore,
                data.ibtBalAfter + ibts,
                "IBT balance after deposit is wrong"
            );

            assertEq(
                data.ibtBalPTContractAfter,
                data.ibtBalPTContractBefore + ibts,
                "IBT balance of PT contract after deposit is wrong"
            );
        }
    }

    /**
     * @dev Internal function for testing basic router REDEEM_IBT_FOR_ASSET command
     * @param shares Amount of shares to redeem
     * @return receivedAssets Amount of assets received for redeeming shares
     */
    function _testRouterRedeemIBTForAsset(
        uint256 shares
    ) internal returns (uint256 receivedAssets) {
        routerCommandsData memory data;

        // data before
        data.assetBalBefore = IERC20(underlying).balanceOf(address(this));
        data.ibtBalBefore = IERC20(ibt).balanceOf(address(this));
        data.assetBalRouterContractBefore = IERC20(underlying).balanceOf(address(router));
        data.ibtBalRouterContractBefore = IERC20(ibt).balanceOf(address(router));

        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.REDEEM_IBT_FOR_ASSET))
        );
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(ibt, shares);
        inputs[1] = abi.encode(ibt, Constants.CONTRACT_BALANCE, address(this));

        data.expected2 = IERC4626(ibt).previewRedeem(shares);

        if (data.expected2 != 0) {
            data.routerPreviewRate = IRouter(router).previewRate(commands, inputs);
            data.expected1 = shares.mulDiv(data.routerPreviewRate, 1e27);

            IRouter(router).execute(commands, inputs);

            // data after
            data.assetBalAfter = IERC20(underlying).balanceOf(address(this));
            data.ibtBalAfter = IERC20(ibt).balanceOf(address(this));
            data.assetBalRouterContractAfter = IERC20(underlying).balanceOf(address(router));
            data.ibtBalRouterContractAfter = IERC20(ibt).balanceOf(address(router));

            receivedAssets = data.assetBalAfter - data.assetBalBefore;

            assertEq(
                data.assetBalRouterContractAfter,
                data.assetBalRouterContractBefore,
                "Asset balance of Router contract after execution is wrong"
            );
            assertEq(
                data.ibtBalRouterContractAfter,
                data.ibtBalRouterContractBefore,
                "IBT balance of Router after execution is wrong"
            );

            assertEq(data.expected2, data.expected1, "Router previewRate is wrong");

            assertEq(data.expected2, receivedAssets, "underlying balance after redeem is wrong");
            assertEq(
                data.ibtBalBefore,
                data.ibtBalAfter + shares,
                "IBT balance after redeem is wrong"
            );
        }
    }

    /**
     * @dev Internal function for testing basic router REDEEM_PT_FOR_ASSET command
     * @param shares Amount of shares to redeem
     * @return receivedAssets Amount of assets received for redeeming shares
     */
    function _testRouterRedeemPTForAsset(uint256 shares) internal returns (uint256 receivedAssets) {
        routerCommandsData memory data;

        // data before
        data.assetBalBefore = IERC20(underlying).balanceOf(address(this));
        data.ptBalBefore = IERC20(pt).balanceOf(address(this));
        data.ytBalBefore = IERC20(yt).balanceOf(address(this));
        data.ibtBalPTContractBefore = IERC20(ibt).balanceOf(pt);
        data.assetBalRouterContractBefore = IERC20(underlying).balanceOf(router);
        data.ptBalRouterContractBefore = IERC20(pt).balanceOf(router);
        data.ytBalRouterContractBefore = IERC20(yt).balanceOf(router);
        data.assetsInIBT = IERC4626(ibt).convertToShares(IPrincipalToken(pt).previewRedeem(shares));

        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.REDEEM_PT_FOR_ASSET))
        );
        bytes[] memory inputs = new bytes[](3);
        inputs[0] = abi.encode(pt, shares);
        inputs[1] = abi.encode(yt, shares);
        inputs[2] = abi.encode(pt, Constants.CONTRACT_BALANCE, address(this), 0);

        data.expected2 = IPrincipalToken(pt).previewRedeem(shares);

        if (data.expected2 != 0) {
            data.routerPreviewRate = IRouter(router).previewRate(commands, inputs);
            data.expected1 = shares.mulDiv(data.routerPreviewRate, 1e27, Math.Rounding.Ceil);

            IRouter(router).execute(commands, inputs);

            // data before
            data.assetBalAfter = IERC20(underlying).balanceOf(address(this));
            data.ptBalAfter = IERC20(pt).balanceOf(address(this));
            data.ytBalAfter = IERC20(yt).balanceOf(address(this));
            data.ibtBalPTContractAfter = IERC20(ibt).balanceOf(pt);
            data.assetBalRouterContractAfter = IERC20(underlying).balanceOf(router);
            data.ptBalRouterContractAfter = IERC20(pt).balanceOf(router);
            data.ytBalRouterContractAfter = IERC20(yt).balanceOf(router);

            receivedAssets = data.assetBalAfter - data.assetBalBefore;

            assertEq(
                data.assetBalRouterContractAfter,
                data.assetBalRouterContractBefore,
                "Asset balance of Router contract after execution is wrong"
            );
            assertEq(
                data.ptBalRouterContractAfter,
                data.ptBalRouterContractBefore,
                "PT balance of Router contract after execution is wrong"
            );
            assertEq(
                data.ytBalRouterContractAfter,
                data.ytBalRouterContractBefore,
                "YT balance of Router contract after execution is wrong"
            );

            assertEq(data.expected2, data.expected1, "Router preview rate is wrong");

            assertEq(data.expected2, receivedAssets, "Asset balance after redeem is wrong");
            assertEq(
                data.ptBalBefore,
                data.ptBalAfter + shares,
                "PT balance after redeem is wrong"
            );
            assertEq(
                data.ytBalBefore,
                data.ytBalAfter + shares,
                "YT balance after redeem is wrong"
            );

            assertApproxEqAbs(
                data.ibtBalPTContractBefore,
                data.ibtBalPTContractAfter + data.assetsInIBT,
                _getPrecision(IBT_UNIT),
                "IBT balance of PT contract after redeem is wrong"
            );
        }
    }

    /**
     * @dev Internal function for testing basic router REDEEM_PT_FOR_IBT command
     * @param shares Amount of shares to redeem
     * @return receivedIBTs Amount of IBT received for redeeming shares
     */
    function _testRouterRedeemPTForIBT(uint256 shares) internal returns (uint256 receivedIBTs) {
        routerCommandsData memory data;

        // data before
        data.ibtBalBefore = IERC20(ibt).balanceOf(address(this));
        data.ptBalBefore = IERC20(pt).balanceOf(address(this));
        data.ytBalBefore = IERC20(yt).balanceOf(address(this));
        data.ibtBalPTContractBefore = IERC20(ibt).balanceOf(pt);
        data.ibtBalRouterContractBefore = IERC20(ibt).balanceOf(router);
        data.ptBalRouterContractBefore = IERC20(pt).balanceOf(router);
        data.ytBalRouterContractBefore = IERC20(yt).balanceOf(router);

        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.REDEEM_PT_FOR_IBT))
        );
        bytes[] memory inputs = new bytes[](3);
        inputs[0] = abi.encode(pt, shares);
        inputs[1] = abi.encode(yt, shares);
        inputs[2] = abi.encode(pt, Constants.CONTRACT_BALANCE, address(this), 0);

        data.expected2 = IPrincipalToken(pt).previewRedeemForIBT(shares);

        if (data.expected2 != 0) {
            data.routerPreviewRate = IRouter(router).previewRate(commands, inputs);
            data.expected1 = shares.mulDiv(data.routerPreviewRate, 1e27);

            IRouter(router).execute(commands, inputs);

            // data before
            data.ibtBalAfter = IERC20(ibt).balanceOf(address(this));
            data.ptBalAfter = IERC20(pt).balanceOf(address(this));
            data.ytBalAfter = IERC20(yt).balanceOf(address(this));
            data.ibtBalPTContractAfter = IERC20(ibt).balanceOf(pt);
            data.ibtBalRouterContractAfter = IERC20(ibt).balanceOf(router);
            data.ptBalRouterContractAfter = IERC20(pt).balanceOf(router);
            data.ytBalRouterContractAfter = IERC20(yt).balanceOf(router);

            receivedIBTs = data.ibtBalAfter - data.ibtBalBefore;

            assertEq(
                data.ibtBalRouterContractAfter,
                data.ibtBalRouterContractBefore,
                "IBT balance of Router after execution is wrong"
            );
            assertEq(
                data.ptBalRouterContractAfter,
                data.ptBalRouterContractBefore,
                "PT balance of Router contract after execution is wrong"
            );
            assertEq(
                data.ytBalRouterContractAfter,
                data.ytBalRouterContractBefore,
                "YT balance of Router contract after execution is wrong"
            );

            assertEq(data.expected2, data.expected1, "Router preview rate is wrong");

            assertEq(data.expected2, receivedIBTs, "IBT balance after redeem is wrong");
            assertEq(
                data.ptBalBefore,
                data.ptBalAfter + shares,
                "PT balance after redeem is wrong"
            );
            assertEq(
                data.ytBalBefore,
                data.ytBalAfter + shares,
                "YT balance after redeem is wrong"
            );

            assertEq(
                data.ibtBalPTContractAfter + receivedIBTs,
                data.ibtBalPTContractBefore,
                "IBT balance of PT contract after deposit is wrong"
            );
        }
    }

    /**
     * @dev Internal function for testing basic router swap functionality
     * @param amountIn Amount of assets to swap
     * @param i Index of the token to swap from
     * @param j Index of the token to swap to
     * @return amountOut Amount of assets received from the swap
     */
    function _testRouterSwap(
        uint256 amountIn,
        uint256 i,
        uint256 j
    ) internal returns (uint256 amountOut) {
        routerCommandsData memory data;

        // data before
        data.ibtBalBefore = IERC4626(ibt).balanceOf(address(this));
        data.ptBalBefore = IPrincipalToken(pt).balanceOf(address(this));
        data.ibtBalRouterContractBefore = IERC4626(ibt).balanceOf(router);
        data.ptBalRouterContractBefore = IPrincipalToken(pt).balanceOf(router);

        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.TRANSFER_FROM)),
            bytes1(uint8(Commands.CURVE_SWAP))
        );
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(i == 0 ? ibt : pt, amountIn);
        inputs[1] = abi.encode(
            curvePool,
            i, // in
            j, // out
            Constants.CONTRACT_BALANCE,
            0, // No min output
            address(this)
        );

        data.expected2 = ICurvePool(curvePool).get_dy(i, j, amountIn);

        if (data.expected2 != 0) {
            data.routerPreviewRate = IRouter(router).previewRate(commands, inputs);
            data.expected1 = amountIn.mulDiv(data.routerPreviewRate, 1e27, Math.Rounding.Ceil);

            IRouter(router).execute(commands, inputs);

            // data after
            data.ibtBalAfter = IERC4626(ibt).balanceOf(address(this));
            data.ptBalAfter = IPrincipalToken(pt).balanceOf(address(this));
            data.ibtBalRouterContractAfter = IERC4626(ibt).balanceOf(router);
            data.ptBalRouterContractAfter = IPrincipalToken(pt).balanceOf(router);

            if (i == 0) {
                amountOut = data.ptBalAfter - data.ptBalBefore;
                assertEq(
                    data.ibtBalBefore - data.ibtBalAfter,
                    amountIn,
                    "swap input amount is wrong"
                );
            } else {
                amountOut = data.ibtBalAfter - data.ibtBalBefore;
                assertEq(
                    data.ptBalBefore - data.ptBalAfter,
                    amountIn,
                    "swap input amount is wrong"
                );
            }

            assertEq(data.expected2, data.expected1, "Router previewRate is wrong");
            assertEq(data.expected2, amountOut, "swap output amount is wrong");

            assertEq(
                data.ptBalRouterContractAfter,
                data.ptBalRouterContractBefore,
                "PT balance of Router contract after execution is wrong"
            );
            assertEq(
                data.ibtBalRouterContractAfter,
                data.ibtBalRouterContractBefore,
                "IBT balance of Router contract after execution is wrong"
            );
        }
    }

    /* MISC UTILS */

    /**
     * @dev Internal function for changing IBT rate
     */
    function _changeIbtRate(uint16 ibtRateVar, bool isIncrease) internal {
        MockIBTCustomDecimals(ibt).changeRate(ibtRateVar, isIncrease);
    }

    /**
     * @dev Internal function for expiring principalToken
     */
    function _increaseTimeToExpiry() internal {
        uint256 time = block.timestamp + IPrincipalToken(pt).maturity();
        vm.warp(time);
    }

    /**
     * @dev Compute amount substracted by a relative fee
     * @param amount The amount to substract fee from
     * @param feeRate The fee rate, where 1e18 == 100%
     */
    function _amountMinusFee(uint256 amount, uint256 feeRate) internal pure returns (uint256) {
        return amount - amount.mulDiv(feeRate, 1e18);
    }

    function _calcFees(uint256 amount, uint256 feeRate) internal pure returns (uint256) {
        return amount.mulDiv(feeRate, 1e18);
    }

    /**
     * @dev Internal function to get measurement precision equal to 0.1% of given unit
     * @param unit The unit of reference
     */
    function _getPrecision(uint256 unit) internal pure returns (uint256) {
        return (1e15 * unit) / 1e18;
    }

    /**
     * @dev Internal function that calculates the pool's Noise fee.
     * @param amount The amount to deposit in the pool for a token.
     */
    function _calcNoiseFee(uint256 amount) internal view returns (uint256) {
        //Important: this fee doesn't seem to correspond only to the noise fee but encapsulates more fees.
        return ((amount * NOISE_FEE) / UNIT + 1); //not sure why the 1 but seem to satisfy the tests.
    }

    /* ROUTER UTILS */

    function _getCurvePriceImpactLossAndFees(
        uint256 i,
        uint256 j,
        uint256 amountIn
    ) internal view returns (uint256) {
        return
            amountIn.mulDiv(
                RouterUtil(routerUtil).spotExchangeRate(curvePool, i, j),
                CurvePoolUtil.CURVE_UNIT
            ) - ICurvePool(curvePool).get_dy(i, j, amountIn);
    }
}
