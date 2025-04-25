// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../../src/mocks/MockUnderlyingCustomDecimals.sol";
import "../../src/mocks/MockIBTCustomRedeemFeesThreshold.sol";
import "../../script/10_deployAll.s.sol";
import "../../src/libraries/RayMath.sol";
import {TestPT5095AndDeposit} from "../ERC5095/PTPropertyCheck.t.sol";
import "openzeppelin-math/Math.sol";

abstract contract MockIBTFees is TestPT5095AndDeposit {
    using Math for uint256;
    using RayMath for uint256;

    error FailedToAddLiquidity();

    DeployAllScript deployAllScript;

    address public _yt_;
    address public ibt;
    address public curveFactoryAddress;

    uint256 fork;
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    address public scriptAdmin;
    address public testUser;

    address feeCollector = 0x0000000000000000000000000000000000000FEE;
    address caller1 = 0x0000000000000000000000000000000000000001;
    address caller2 = 0x0000000000000000000000000000000000000002;

    uint8 public MIN_DECIMALS = 6;
    uint8 public MAX_DECIMALS = 18;

    uint256 public DURATION = 15724800; // 182 days
    uint256 public TOKENIZATION_FEE = 0;
    uint256 public YIELD_FEE = 0;
    uint256 public PT_FLASH_LOAN_FEE = 0;
    uint256 constant MAX_TOKENIZATION_FEE = 1e16;
    uint256 constant MAX_YIELD_FEE = 5e17;
    uint256 constant MAX_PT_FLASH_LOAN_FEE = 1e18;
    uint256 constant FEE_DIVISOR = 1e18;
    uint256 public NOISE_FEE = 1e13;

    uint256 public UNIT = 1e18;
    uint256 public IBT_UNIT;
    uint256 public ASSET_UNIT;

    struct ptDepositWithdrawData {
        uint256 maxWithdrawRedeem;
        uint256 depositAssetAmount;
        uint256 depositedIBT;
        uint256 PTRate;
        uint256 IBTRate;
        uint256 fee1;
        uint256 fee2;
        uint256 feesDiff;
        uint256 claimedYield;
        uint256 expectedYieldInIBT;
    }

    struct YieldData {
        uint256 oldYieldUser;
        uint256 ibtOfYTUser;
        uint256 yieldInUnderlyingUser;
        uint256 expectedYieldInIBTUser;
        uint256 actualYieldUser;
        uint256 ytBalanceBeforeUser;
        uint256 yieldClaimed;
        uint256 underlyingBalanceBefore;
        uint256 oldPTRateUser;
        uint256 newPTRateUser;
        uint256 oldIBTRateUser;
        uint256 newIBTRateUser;
        uint256 oldRate;
        uint256 newRate;
        uint256 oldIBTRate;
        uint256 newIBTRate;
        uint256 oldPTRate;
        uint256 newPTRate;
    }

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

        curveFactoryAddress = 0x98EE851a00abeE0d95D08cF4CA2BdCE32aeaAF7F;

        deployAllScript = new DeployAllScript();
    }

    function test_all_methods_rate_changeFuzz(
        uint8 _ibtDecimals,
        uint8 _underlyingDecimals,
        uint256 amount,
        uint16 _ibtRateVar,
        bool _isIncrease
    ) public {
        _underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        _ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(_underlyingDecimals), uint256(MAX_DECIMALS))
        );
        uint16 ibtRateVar = uint16(bound(_ibtRateVar, 0, 50));
        amount = bound(amount, 100, 100_000);
        ASSET_UNIT = 10 ** _underlyingDecimals;
        IBT_UNIT = 10 ** _ibtDecimals;
        vm.assume(caller1 != address(0));
        vm.assume(caller2 != address(0));
        vm.assume(caller2 != caller1);

        IBT_UNIT = 10 ** _ibtDecimals;
        ASSET_UNIT = 10 ** _underlyingDecimals;
        _deployProtocol(
            _underlyingDecimals,
            _ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE,
            IBT_UNIT, // threshold
            IBT_UNIT / 10, // lowFee
            IBT_UNIT / 20 // highFee
        );

        MockUnderlyingCustomDecimals(_underlying_).mint(caller1, 100_000_000_000_000 * ASSET_UNIT);
        MockUnderlyingCustomDecimals(_underlying_).mint(caller2, 100_000_000_000_000 * ASSET_UNIT);

        //
        // Deposit tests
        //

        vm.prank(caller1);
        IERC20(_underlying_).approve(_pt_, amount * ASSET_UNIT);
        prop_previewDeposit(caller1, caller1, caller2, amount * ASSET_UNIT);
        vm.prank(caller1);
        IERC20(_underlying_).approve(_pt_, amount * ASSET_UNIT);
        prop_deposit(caller1, caller1, amount * ASSET_UNIT);

        vm.prank(caller2);
        IERC20(_underlying_).approve(_pt_, amount * ASSET_UNIT);
        prop_previewDeposit(caller2, caller2, caller1, amount * ASSET_UNIT);
        vm.prank(caller2);
        IERC20(_underlying_).approve(_pt_, amount * ASSET_UNIT);
        prop_deposit(caller2, caller2, amount * ASSET_UNIT);

        _changeIbtRate(ibtRateVar, _isIncrease);

        //
        // getter tests
        //

        check_underlying_5095(caller1);
        check_maturity_5095(caller1);
        check_convertToUnderlying_5095(caller1, caller2, amount * IBT_UNIT);
        check_convertToPrincipal_5095(caller1, caller2, amount * ASSET_UNIT);

        //
        // Withdraw tests
        //

        uint256 maxWithdrawRedeem = prop_maxWithdraw_5095(caller1, caller1);
        prop_previewWithdraw_5095(caller1, caller1, caller1, caller2, maxWithdrawRedeem);
        maxWithdrawRedeem = prop_maxWithdraw_5095(caller2, caller2);
        prop_previewWithdraw_5095(caller2, caller2, caller2, caller1, maxWithdrawRedeem);

        // Deposit more assets in the PT by calling the deposit tests again
        vm.prank(caller1);
        IERC20(_underlying_).approve(_pt_, amount * ASSET_UNIT);
        prop_deposit(caller1, caller1, amount * ASSET_UNIT);
        vm.prank(caller2);
        IERC20(_underlying_).approve(_pt_, amount * ASSET_UNIT);
        prop_deposit(caller2, caller2, amount * ASSET_UNIT);

        maxWithdrawRedeem = prop_maxWithdraw_5095(caller1, caller1);
        prop_withdraw_5095(caller1, caller1, caller1, maxWithdrawRedeem);
        maxWithdrawRedeem = prop_maxWithdraw_5095(caller2, caller2);
        prop_withdraw_5095(caller2, caller2, caller2, maxWithdrawRedeem);

        //
        // Redeem tests
        //

        for (uint i; i < 5; i++) {
            // change ibt rate
            _changeIbtRate(ibtRateVar, ((i % 2) == 0) ? _isIncrease : !_isIncrease);

            // Deposit more assets in the PT by calling the deposit tests again
            vm.prank(caller1);
            IERC20(_underlying_).approve(_pt_, amount * ASSET_UNIT);
            prop_deposit(caller1, caller1, amount * ASSET_UNIT);
            vm.prank(caller2);
            IERC20(_underlying_).approve(_pt_, amount * ASSET_UNIT);
            prop_deposit(caller2, caller2, amount * ASSET_UNIT);
        }

        maxWithdrawRedeem = prop_maxRedeem_5095(caller1, caller1);
        prop_previewRedeem_5095(caller1, caller1, caller1, caller2, maxWithdrawRedeem);

        maxWithdrawRedeem = prop_maxRedeem_5095(caller2, caller2);
        prop_previewRedeem_5095(caller2, caller2, caller2, caller1, maxWithdrawRedeem);

        // Deposit more assets in the PT by calling the deposit tests again
        vm.prank(caller1);
        IERC20(_underlying_).approve(_pt_, amount * ASSET_UNIT);
        prop_deposit(caller1, caller1, amount * ASSET_UNIT);
        vm.prank(caller2);
        IERC20(_underlying_).approve(_pt_, amount * ASSET_UNIT);
        prop_deposit(caller2, caller2, amount * ASSET_UNIT);

        maxWithdrawRedeem = prop_maxRedeem_5095(caller1, caller1);
        prop_redeem_5095(caller1, caller1, caller1, maxWithdrawRedeem);

        maxWithdrawRedeem = prop_maxRedeem_5095(caller2, caller2);
        prop_redeem_5095(caller2, caller2, caller2, maxWithdrawRedeem);
    }

    function testAllMethodsAfterExpiryRateChangeFuzz(
        uint8 _ibtDecimals,
        uint8 _underlyingDecimals,
        uint256 amount,
        uint16 _ibtRateVar,
        bool _isIncrease
    ) public {
        _underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        _ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(_underlyingDecimals), uint256(MAX_DECIMALS))
        );
        uint16 ibtRateVar = uint16(bound(_ibtRateVar, 0, 50));
        amount = bound(amount, 100, 100_000);
        ASSET_UNIT = 10 ** _underlyingDecimals;
        IBT_UNIT = 10 ** _ibtDecimals;
        vm.assume(caller1 != address(0));
        vm.assume(caller2 != address(0));
        vm.assume(caller2 != caller1);

        IBT_UNIT = 10 ** _ibtDecimals;
        ASSET_UNIT = 10 ** _underlyingDecimals;
        _deployProtocol(
            _underlyingDecimals,
            _ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE,
            IBT_UNIT, // threshold
            IBT_UNIT / 10, // lowFee
            IBT_UNIT / 20 // highFee
        );

        MockUnderlyingCustomDecimals(_underlying_).mint(caller1, 100_000_000_000_000 * ASSET_UNIT);
        MockUnderlyingCustomDecimals(_underlying_).mint(caller2, 100_000_000_000_000 * ASSET_UNIT);

        //
        // Deposit tests
        //

        vm.prank(caller1);
        IERC20(_underlying_).approve(_pt_, amount * ASSET_UNIT);
        prop_previewDeposit(caller1, caller1, caller2, amount * ASSET_UNIT);
        vm.prank(caller1);
        IERC20(_underlying_).approve(_pt_, amount * ASSET_UNIT);
        prop_deposit(caller1, caller1, amount * ASSET_UNIT);

        vm.prank(caller2);
        IERC20(_underlying_).approve(_pt_, amount * ASSET_UNIT);
        prop_previewDeposit(caller2, caller2, caller1, amount * ASSET_UNIT);
        vm.prank(caller2);
        IERC20(_underlying_).approve(_pt_, amount * ASSET_UNIT);
        prop_deposit(caller2, caller2, amount * ASSET_UNIT);

        _changeIbtRate(ibtRateVar, _isIncrease);

        //
        // getter tests
        //

        check_underlying_5095(caller1);
        check_maturity_5095(caller1);
        check_convertToUnderlying_5095(caller1, caller2, amount * IBT_UNIT);
        check_convertToPrincipal_5095(caller1, caller2, amount * ASSET_UNIT);

        //
        // Withdraw tests
        //

        uint256 maxWithdrawRedeem = prop_maxWithdraw_5095(caller1, caller1);
        prop_previewWithdraw_5095(caller1, caller1, caller1, caller2, maxWithdrawRedeem);
        maxWithdrawRedeem = prop_maxWithdraw_5095(caller2, caller2);
        prop_previewWithdraw_5095(caller2, caller2, caller2, caller1, maxWithdrawRedeem);

        // Deposit more assets in the PT by calling the deposit tests again
        vm.prank(caller1);
        IERC20(_underlying_).approve(_pt_, amount * ASSET_UNIT);
        prop_deposit(caller1, caller1, amount * ASSET_UNIT);
        vm.prank(caller2);
        IERC20(_underlying_).approve(_pt_, amount * ASSET_UNIT);
        prop_deposit(caller2, caller2, amount * ASSET_UNIT);

        maxWithdrawRedeem = prop_maxWithdraw_5095(caller1, caller1);
        prop_withdraw_5095(caller1, caller1, caller1, maxWithdrawRedeem);
        maxWithdrawRedeem = prop_maxWithdraw_5095(caller2, caller2);
        prop_withdraw_5095(caller2, caller2, caller2, maxWithdrawRedeem);

        //
        // Redeem tests
        //

        maxWithdrawRedeem = prop_maxRedeem_5095(caller1, caller1);
        prop_previewRedeem_5095(caller1, caller1, caller1, caller2, maxWithdrawRedeem);

        maxWithdrawRedeem = prop_maxRedeem_5095(caller2, caller2);
        prop_previewRedeem_5095(caller2, caller2, caller2, caller1, maxWithdrawRedeem);

        // Deposit more assets in the PT by calling the deposit tests again
        vm.prank(caller1);
        IERC20(_underlying_).approve(_pt_, amount * ASSET_UNIT);
        prop_deposit(caller1, caller1, amount * ASSET_UNIT);
        vm.prank(caller2);
        IERC20(_underlying_).approve(_pt_, amount * ASSET_UNIT);
        prop_deposit(caller2, caller2, amount * ASSET_UNIT);

        maxWithdrawRedeem = prop_maxRedeem_5095(caller1, caller1);
        prop_redeem_5095(caller1, caller1, caller1, maxWithdrawRedeem);

        maxWithdrawRedeem = prop_maxRedeem_5095(caller2, caller2);
        prop_redeem_5095(caller2, caller2, caller2, maxWithdrawRedeem);

        for (uint i; i < 5; i++) {
            // change ibt rate
            _changeIbtRate(ibtRateVar, ((i % 2) == 0) ? _isIncrease : !_isIncrease);

            // Deposit more assets in the PT by calling the deposit tests again
            vm.prank(caller1);
            IERC20(_underlying_).approve(_pt_, amount * ASSET_UNIT);
            prop_deposit(caller1, caller1, amount * ASSET_UNIT);
            vm.prank(caller2);
            IERC20(_underlying_).approve(_pt_, amount * ASSET_UNIT);
            prop_deposit(caller2, caller2, amount * ASSET_UNIT);
        }

        _increaseTimeToExpiry();

        // Caller 1 try to deposit
        bytes memory revertData = abi.encodeWithSelector(bytes4(keccak256("PTExpired()")));
        vm.prank(caller1);
        IERC20(_underlying_).approve(_pt_, amount * ASSET_UNIT);
        vm.expectRevert(revertData);
        vm.prank(caller1);
        IPrincipalToken(_pt_).deposit(amount * ASSET_UNIT, caller1);

        // Caller 1 withdraw

        maxWithdrawRedeem = prop_maxRedeem_5095(caller1, caller1);
        prop_redeem_5095(caller1, caller1, caller1, maxWithdrawRedeem);
        // caller 2 redeem

        maxWithdrawRedeem = prop_maxWithdraw_5095(caller2, caller2);
        prop_withdraw_5095(caller2, caller2, caller2, maxWithdrawRedeem);
    }

    function testYieldGenerationRateChangeFuzz(
        uint8 ibtDecimals,
        uint8 underlyingDecimals,
        uint16 ibtRateVar,
        uint256 fees,
        bool feesThresholdDirection,
        uint256 amount
    ) public {
        underlyingDecimals = uint8(
            bound(uint256(underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        ibtDecimals = uint8(
            bound(uint256(ibtDecimals), uint256(underlyingDecimals), uint256(MAX_DECIMALS))
        );
        ptDepositWithdrawData memory data;
        YieldData memory yieldData;
        ibtRateVar = uint16(bound(ibtRateVar, 1, 50));
        amount = bound(amount, 100, 100_000);
        // amount = 10; // TO REMOVE
        ASSET_UNIT = 10 ** underlyingDecimals;
        IBT_UNIT = 10 ** ibtDecimals;
        fees = uint16(bound(fees, 0, IBT_UNIT));
        data.depositAssetAmount = amount * ASSET_UNIT;

        vm.assume(caller1 != address(0));
        vm.assume(caller2 != address(0));
        vm.assume(caller2 != caller1);

        if (feesThresholdDirection) {
            data.fee1 = fees / 2;
            data.fee2 = fees;
        } else {
            data.fee1 = fees;
            data.fee2 = fees / 2;
        }

        IBT_UNIT = 10 ** ibtDecimals;
        ASSET_UNIT = 10 ** underlyingDecimals;
        _deployProtocol(
            underlyingDecimals,
            ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE,
            IBT_UNIT, // threshold
            data.fee1, // lowFee (<= T)
            data.fee2 // highFee (> T)
        );

        MockUnderlyingCustomDecimals(_underlying_).mint(caller1, 100_000_000_000_000 * ASSET_UNIT);
        MockUnderlyingCustomDecimals(_underlying_).mint(caller2, 100_000_000_000_000 * ASSET_UNIT);

        // Caller1 deposit
        vm.prank(caller1);
        IERC20(_underlying_).approve(_pt_, amount * ASSET_UNIT);
        prop_deposit(caller1, caller1, amount * ASSET_UNIT);

        // Caller2 deposit
        vm.prank(caller2);
        IERC20(_underlying_).approve(_pt_, amount * ASSET_UNIT);
        prop_deposit(caller2, caller2, amount * ASSET_UNIT);

        // Generate yield
        for (uint i; i < 25; i++) {
            _updateRateAndCheckYield(ibtRateVar, (i % 2) == 0, yieldData, ibtDecimals, caller1);
            _updateRateAndCheckYield(ibtRateVar, (i % 2) == 0, yieldData, ibtDecimals, caller2);
        }

        // Caller 1 withdraw all
        data.maxWithdrawRedeem = prop_maxRedeem_5095(caller1, caller1);
        prop_redeem_5095(caller1, caller1, caller1, data.maxWithdrawRedeem);

        // caller 2 redeem all
        data.maxWithdrawRedeem = prop_maxWithdraw_5095(caller2, caller2);
        prop_withdraw_5095(caller2, caller2, caller2, data.maxWithdrawRedeem);

        // Caller 1 claim yield must not revert
        vm.prank(caller1);
        IPrincipalToken(_pt_).claimYield(caller1, 0);

        // Caller 2 claim yield must not revert
        vm.prank(caller2);
        IPrincipalToken(_pt_).claimYield(caller2, 0);
    }

    function _updateRateAndCheckYield(
        uint16 ibtRateVar,
        bool isIncrease,
        YieldData memory yieldData,
        uint256 ibtDecimals,
        address user
    ) internal {
        yieldData.oldIBTRate = IPrincipalToken(_pt_).getIBTRate();
        yieldData.oldPTRate = IPrincipalToken(_pt_).getPTRate();
        yieldData.oldYieldUser = IPrincipalToken(_pt_).updateYield(user);
        _changeIbtRate(ibtRateVar, isIncrease);
        yieldData.newIBTRate = IPrincipalToken(_pt_).getIBTRate();
        yieldData.newPTRate = IPrincipalToken(_pt_).getPTRate();
        yieldData.actualYieldUser = IPrincipalToken(_pt_).updateYield(user);

        if (isIncrease) {
            assertGt(
                yieldData.newIBTRate,
                yieldData.oldIBTRate,
                "IBT rate not increased as expected"
            );
            yieldData.ibtOfYTUser = _convertToSharesWithRate(
                _convertToAssetsWithRate(
                    IERC20(_yt_).balanceOf(user),
                    yieldData.oldPTRate,
                    false,
                    true,
                    Math.Rounding.Floor
                ),
                yieldData.oldIBTRate,
                true,
                true,
                Math.Rounding.Floor
            );
            yieldData.yieldInUnderlyingUser = _convertToAssetsWithRate(
                yieldData.ibtOfYTUser,
                (yieldData.newIBTRate - yieldData.oldIBTRate),
                true,
                true,
                Math.Rounding.Floor
            );
            yieldData.expectedYieldInIBTUser = _convertToSharesWithRate(
                yieldData.yieldInUnderlyingUser,
                yieldData.newIBTRate,
                true,
                false,
                Math.Rounding.Floor
            );

            assertApproxEqAbs(
                yieldData.actualYieldUser,
                yieldData.oldYieldUser + yieldData.expectedYieldInIBTUser,
                1000,
                "After rate change yield of user1 is not equal to expected value"
            );
        } else {
            assertLt(
                yieldData.newIBTRate,
                yieldData.oldIBTRate,
                "IBT rate not decreased as expected"
            );
            assertApproxEqRel(
                yieldData.newIBTRate.fromRay(ibtDecimals),
                yieldData.oldIBTRate.mulDiv(100 - ibtRateVar, 100, Math.Rounding.Floor).fromRay(
                    ibtDecimals
                ),
                1e15,
                "IBT rate not changed as expected"
            );
            assertEq(yieldData.actualYieldUser, yieldData.oldYieldUser);
        }
    }

    function _deployProtocol(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint256 _tokenizationFee,
        uint256 _yieldFee,
        uint256 _ptFlashLoanFee,
        uint256 _threshold,
        uint256 _lowFee,
        uint256 _highFee
    ) internal virtual {
        _underlying_ = address(new MockUnderlyingCustomDecimals());
        MockUnderlyingCustomDecimals(_underlying_).initialize(
            "MOCK UNDERLYING",
            "MUDL",
            _underlyingDecimals
        );

        ibt = address(
            new MockIBTCustomFeesThreshold(
                "MOCK IBT",
                "MIBT",
                IERC20(_underlying_),
                _ibtDecimals,
                0, // rateChange
                _threshold,
                _lowFee,
                _highFee
            )
        );

        MockUnderlyingCustomDecimals(_underlying_).mint(address(this), ASSET_UNIT);
        MockUnderlyingCustomDecimals(_underlying_).approve(ibt, ASSET_UNIT);
        MockIBTCustomFeesThreshold(ibt).deposit(ASSET_UNIT, address(this));

        DeployAllScript.TestInputData memory inputData;
        inputData._ibt = ibt;
        inputData._duration = DURATION;
        inputData._curveFactoryAddress = curveFactoryAddress;
        inputData._deployer = scriptAdmin;
        inputData._tokenizationFee = _tokenizationFee;
        inputData._yieldFee = _yieldFee;
        inputData._ptFlashLoanFee = _ptFlashLoanFee;
        inputData._feeCollector = feeCollector;
        inputData._initialLiquidityInIBT = 0;
        inputData._minPTShares = 0;

        DeployAllScript.ReturnData memory returnData;
        returnData = deployAllScript.deployForTest(inputData);
        _pt_ = returnData._pt;
        _yt_ = IPrincipalToken(_pt_).getYT();

        MockUnderlyingCustomDecimals(_underlying_).mint(
            address(this),
            100_000_000_000_000 * ASSET_UNIT
        );
        // Mint assets to another user to seed tokens with a different user (address(1)) in some tests
        MockUnderlyingCustomDecimals(_underlying_).mint(
            address(1),
            100_000_000_000_000 * ASSET_UNIT
        );
    }

    /**
     * @dev Internal function for expiring principalToken
     */
    function _increaseTimeToExpiry() internal {
        uint256 time = block.timestamp + IPrincipalToken(_pt_).maturity();
        vm.warp(time);
    }

    /**
     * @dev Internal function for changing IBT rate
     */
    function _changeIbtRate(uint16 ibtRateVar, bool isIncrease) internal {
        MockIBTCustomFeesThreshold(ibt).changeRate(ibtRateVar, isIncrease);
    }

    function _convertToSharesWithRate(
        uint256 assets,
        uint256 rate,
        bool fromRay,
        bool toRay,
        Math.Rounding rounding
    ) internal view returns (uint256 shares) {
        uint256 _assets = fromRay ? assets : assets.toRay(18);
        uint256 _ibtUnit = toRay ? IBT_UNIT.toRay(18) : IBT_UNIT;
        shares = _assets.mulDiv(_ibtUnit, rate, rounding);
    }

    function _convertToAssetsWithRate(
        uint256 shares,
        uint256 rate,
        bool fromRay,
        bool toRay,
        Math.Rounding rounding
    ) internal view returns (uint256 assets) {
        uint256 _ibtUnit = fromRay ? IBT_UNIT.toRay(18) : IBT_UNIT;
        assets = shares.mulDiv(rate, _ibtUnit, rounding);
        if (!toRay) {
            assets = assets.fromRay(18);
        }
    }
}
