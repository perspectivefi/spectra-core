// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../../src/mocks/MockUnderlyingCustomDecimals.sol";
import "../../src/mocks/MockIBTCustom1.sol";
import "../../script/10_deployAll.s.sol";

contract MockIBT is Test {
    using Math for uint256;

    error FailedToAddLiquidity();

    DeployAllScript deployAllScript;

    address public underlying;
    address public ibt;
    address public registry;
    address public factory;
    address public router;
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

    uint256 public UNIT = 1e18;
    uint256 public IBT_UNIT;
    uint256 public ASSET_UNIT;

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

    function testDepositInIBTFuzz(
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
        uint256 rate1 = MockIBTCustom1(ibt).previewRedeem(IBT_UNIT);
        IERC20(underlying).approve(ibt, depositAmount);
        MockIBTCustom1(ibt).deposit(depositAmount, address(this));
        uint256 rate2 = MockIBTCustom1(ibt).previewRedeem(IBT_UNIT);
        assertGe(rate2, rate1, "Rate should have increased");
        if (depositAmount > ASSET_UNIT / 100) {
            assertApproxEqRel(rate2, 2 * rate1, 1e14, "Rate didn't double");
        }
    }

    function _deployProtocol(
        uint8 _underlyingDecimals,
        uint8 _ibtDecimals,
        uint256 _tokenizationFee,
        uint256 _yieldFee,
        uint256 _ptFlashLoanFee
    ) internal {
        underlying = address(new MockUnderlyingCustomDecimals());
        MockUnderlyingCustomDecimals(underlying).initialize(
            "MOCK UNDERLYING",
            "MUDL",
            _underlyingDecimals
        );

        ibt = address(
            new MockIBTCustom1("MOCK IBT", "MIBT", IERC20(underlying), _ibtDecimals, 100)
        );

        IBT_UNIT = 10 ** _ibtDecimals;
        ASSET_UNIT = 10 ** _underlyingDecimals;

        // deposit assets in IBT before PT deployment
        MockUnderlyingCustomDecimals(underlying).mint(address(this), 1);
        IERC20(underlying).approve(ibt, 1);
        IERC4626(ibt).deposit(1, address(this));

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

        registry = returnData._registry;
        factory = returnData._factory;
        router = returnData._router;
        routerUtil = returnData._routerUtil;
        curveLiqArbitrage = returnData._curveLiqArbitrage;
        pt = returnData._pt;
        curvePool = returnData._curvePool;
        yt = IPrincipalToken(pt).getYT();

        MockUnderlyingCustomDecimals(underlying).mint(
            address(this),
            100_000_000_000_000 * ASSET_UNIT
        );
        // Mint assets to another user to seed tokens with a different user (address(1)) in some tests
        MockUnderlyingCustomDecimals(underlying).mint(address(1), 100_000_000_000_000 * ASSET_UNIT);
    }
}
