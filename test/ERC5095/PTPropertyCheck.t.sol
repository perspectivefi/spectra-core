// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../../script/10_deployAll.s.sol";
import "../../src/libraries/RayMath.sol";
import "../../src/mocks/MockUnderlyingCustomDecimals.sol";
import "../../src/mocks/MockIBTCustomDecimals.sol";
import {TestPT5095AndDeposit} from "./TestPT5095AndDeposit.t.sol";

contract TestPTProperties is TestPT5095AndDeposit {
    using Math for uint256;

    uint256 fork;
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    DeployAllScript deployAllScript;

    address testUser;
    address curveFactoryAddress;
    address public scriptAdmin;
    address public ibt;
    uint256 DURATION = 7 days;

    address feeCollector = 0x0000000000000000000000000000000000000FEE;
    address caller1 = 0x0000000000000000000000000000000000000001;
    address caller2 = 0x0000000000000000000000000000000000000002;

    uint8 public MIN_DECIMALS = 6;
    uint8 public MAX_DECIMALS = 18;

    uint256 public TOKENIZATION_FEE = 1e15;
    uint256 public YIELD_FEE = 0;
    uint256 public PT_FLASH_LOAN_FEE = 0;
    uint256 constant MAX_TOKENIZATION_FEE = 1e16;
    uint256 constant MAX_YIELD_FEE = 5e17;
    uint256 constant MAX_PT_FLASH_LOAN_FEE = 1e18;
    uint256 constant FEE_DIVISOR = 1e18;
    uint256 public NOISE_FEE = 1e13;

    uint256 public UNIT = 1e18;
    uint256 public RAY_UNIT = 1e27;
    uint256 public IBT_UNIT;
    uint256 public ASSET_UNIT;

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

    function test_all_methods_fuzz(
        uint8 _ibtDecimals,
        uint8 _underlyingDecimals,
        uint256 amount
    ) public {
        _underlyingDecimals = uint8(
            bound(uint256(_underlyingDecimals), uint256(MIN_DECIMALS), uint256(MAX_DECIMALS))
        );
        _ibtDecimals = uint8(
            bound(uint256(_ibtDecimals), uint256(_underlyingDecimals), uint256(MAX_DECIMALS))
        );
        amount = bound(amount, 100, 100_000);
        ASSET_UNIT = 10 ** _underlyingDecimals;
        IBT_UNIT = 10 ** _ibtDecimals;

        _deployProtocol(
            _underlyingDecimals,
            _ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
        );

        //
        // Deposit tests
        //

        prop_maxDeposit(address(this), address(this));
        IERC20(_underlying_).approve(_pt_, amount * ASSET_UNIT);
        prop_previewDeposit(address(this), address(this), caller2, amount * ASSET_UNIT);
        IERC20(_underlying_).approve(_pt_, amount * ASSET_UNIT);
        prop_deposit(address(this), address(this), amount * ASSET_UNIT);

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

        uint256 maxWithdrawRedeem = prop_maxWithdraw_5095(address(this), address(this));
        prop_previewWithdraw_5095(
            address(this),
            address(this),
            address(this),
            caller2,
            maxWithdrawRedeem
        );

        // Deposit more assets in the PT by calling the deposit tests again
        IERC20(_underlying_).approve(_pt_, amount * ASSET_UNIT);
        prop_deposit(address(this), address(this), amount * ASSET_UNIT);

        maxWithdrawRedeem = prop_maxWithdraw_5095(address(this), address(this));
        prop_withdraw_5095(address(this), address(this), address(this), maxWithdrawRedeem);

        //
        // Redeem tests
        //

        // Deposit more assets in the PT by calling the deposit tests again
        IERC20(_underlying_).approve(_pt_, amount * ASSET_UNIT);
        prop_deposit(address(this), address(this), amount * ASSET_UNIT);

        maxWithdrawRedeem = prop_maxRedeem_5095(address(this), address(this));
        prop_previewRedeem_5095(
            address(this),
            address(this),
            address(this),
            caller2,
            maxWithdrawRedeem / 2
        );

        // Deposit more assets in the PT by calling the deposit tests again
        IERC20(_underlying_).approve(_pt_, amount * ASSET_UNIT);
        prop_deposit(address(this), address(this), amount * ASSET_UNIT);
        maxWithdrawRedeem = prop_maxRedeem_5095(address(this), address(this));

        prop_redeem_5095(address(this), address(this), address(this), maxWithdrawRedeem);
    }

    function test_all_methods_rate_change_fuzz(
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

        _deployProtocol(
            _underlyingDecimals,
            _ibtDecimals,
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE
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

    function _deployProtocol(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint256 _tokenizationFee,
        uint256 _yieldFee,
        uint256 _ptFlashLoanFee
    ) internal {
        _underlying_ = address(new MockUnderlyingCustomDecimals());
        MockUnderlyingCustomDecimals(_underlying_).initialize(
            "MOCK UNDERLYING",
            "MUDL",
            _underlyingDecimals
        );

        ibt = address(
            new MockIBTCustomDecimals("MOCK IBT", "MIBT", IERC20(_underlying_), _ibtDecimals)
        );

        // deposit assets in IBT
        MockUnderlyingCustomDecimals(_underlying_).mint(address(this), 1);
        IERC20(_underlying_).approve(ibt, 1);
        IPrincipalToken(ibt).deposit(1, address(this));
        IBT_UNIT = 10 ** _ibtDecimals;
        ASSET_UNIT = 10 ** _underlyingDecimals;

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
     * @dev Internal function for changing IBT rate
     */
    function _changeIbtRate(uint16 ibtRateVar, bool isIncrease) internal {
        MockIBTCustomDecimals(ibt).changeRate(ibtRateVar, isIncrease);
    }
}
