// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "forge-std/Test.sol";

import "../../src/mocks/MockERC20.sol";
import "../../src/mocks/MockIBT.sol";
import "../../script/00_deployAccessManager.s.sol";
import "../../script/01_deployRegistry.s.sol";
import "../../script/02_deployPrincipalTokenInstance.s.sol";
import "../../script/03_deployYTInstance.s.sol";
import "../../script/04_deployPrincipalTokenBeacon.s.sol";
import "../../src/RateOracleRegistry.sol";
import "../../script/05_deployYTBeacon.s.sol";
import "../../script/07_deployPrincipalToken.s.sol";
import "../../script/08_deployCurvePool.s.sol";
import "../../script/22_deployRateOracleRegistry.s.sol";
import "../../script/23_deployFactorySNG.s.sol";
import "../../script/24_deployRateAdjustmentOracleInstance.s.sol";
import "../../script/25_deployRateAdjustmentOracleBeacon.s.sol";
import "../../src/libraries/Roles.sol";
import "../../src/libraries/RayMath.sol";
import "../../src/amm/RateAdjustmentOracle.sol";

import "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";

contract RateAdjustmentOracleTest is Test {
    using Math for uint256;
    using Math for int256;

    struct CurvePoolParams {
        uint256 A;
        uint256 fee;
        uint256 fee_mul;
        uint256 ma_exp_time;
        uint256 initial_price;
        address rate_adjustment_oracle;
    }

    FactorySNG public factory;
    AccessManager public accessManager;
    PrincipalToken public principalToken;
    RateAdjustmentOracle public rateAdjustmentOracle;
    MockERC20 public underlying;
    PrincipalToken public principalTokenInstance;
    RateAdjustmentOracle public rateAdjustmentOracleInstance;

    MockIBT public ibt;
    uint256 public constant YEAR = 365 * 24 * 3600;
    uint256 public constant DURATION = YEAR;
    uint256 public IBT_UNIT;

    // registry and the rate oracle registry
    Registry public registry;
    RateOracleRegistry public rateOracleRegistry;

    // addresses
    address public admin;
    address public scriptAdmin;
    address public curveFactoryAddress;
    address public curvePoolAddr;
    IERC20Metadata public lpToken;
    address feeCollector = 0x0000000000000000000000000000000000000FEE;
    address MOCK_ADDR_1 = 0x0000000000000000000000000000000000000001;

    // fees
    uint256 public TOKENIZATION_FEE = 1e15;
    uint256 public YIELD_FEE = 0;
    uint256 public PT_FLASH_LOAN_FEE = 0;
    uint256 constant FEE_DIVISOR = 1e18;

    // fuzz bounds
    uint256 public constant UNIT = 10 ** 18;

    uint256 public constant MIN_INITIAL_PRICE = 8 * 10 ** 17;
    uint256 public constant MAX_INITIAL_PRICE = UNIT - 1;

    int256 public constant MIN_IBT_RATE_ACCRUAL = 0;
    int256 public constant MAX_IBT_RATE_ACCRUAL = 10 ** 4;

    int256 public constant MIN_IBT_RATE_ACCRUAL_NEGATIVE = -99;
    int256 public constant MAX_IBT_RATE_ACCRUAL_NEGATIVE = 0;

    uint256 public constant MIN_TIME = 0;
    uint256 public constant MAX_TIME = DURATION;

    uint256 public constant IMPLIED_RATE_PRECISION = 10 ** 10;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    uint256 fork;
    YieldToken public yt;
    UpgradeableBeacon public principalTokenBeacon;
    UpgradeableBeacon public ytBeacon;
    UpgradeableBeacon public rateAdjustmentOracleBeacon;

    // Events
    event PTDeployed(address indexed principalToken, address indexed poolCreator);
    event CurvePoolDeployed(address indexed poolAddress, address indexed ibt, address indexed pt);
    event CurveFactoryChange(address indexed previousFactory, address indexed newFactory);

    // errors
    error CouldNotFetchLPToken();
    error FailedToAddInitialLiquidity();
    error PTExpired();

    /**
     * @dev This function is called before each test.
     */

    function setUp() public {
        fork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(fork);
        curveFactoryAddress = 0x6A8cbed756804B16E05E741eDaBd5cB544AE21bf;
        admin = address(this); // also set as principalTokenAdmin.
        // default account for deploying scripts contracts. refer to line 35 of
        // https://github.com/foundry-rs/foundry/blob/master/evm/src/lib.rs for more details
        scriptAdmin = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
        AccessManagerDeploymentScript accessManagerScript = new AccessManagerDeploymentScript();
        accessManager = AccessManager(accessManagerScript.deployForTest(scriptAdmin));
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.UPGRADE_ROLE, scriptAdmin, 0);
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.RATE_ADJUSTMENT_ORACLE_SETTER_ROLE, scriptAdmin, 0);

        // deploy the registry instance and proxy
        RegistryScript registryScript = new RegistryScript();
        registry = Registry(
            registryScript.deployForTest(
                TOKENIZATION_FEE,
                YIELD_FEE,
                PT_FLASH_LOAN_FEE,
                feeCollector,
                address(accessManager)
            )
        );

        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.REGISTRY_ROLE, scriptAdmin, 0);
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.FEE_SETTER_ROLE, scriptAdmin, 0);

        // deploy the rate oracle registry instance and proxy
        RateOracleRegistryScript rateOracleRegistryScript = new RateOracleRegistryScript();
        rateOracleRegistry = RateOracleRegistry(
            rateOracleRegistryScript.deployForTest(address(accessManager))
        );

        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.REGISTRY_ROLE, scriptAdmin, 0);

        underlying = new MockERC20();
        underlying.initialize("MOCK UNDERLYING", "MUDL"); // deploys underlying mints 100000e18 token to caller
        ibt = new MockIBT();
        ibt.initialize("MOCK IBT", "MIBT", IERC20Metadata(address(underlying))); // deploys ibt which principalToken holds
        IBT_UNIT = 10 ** ibt.decimals();
        underlying.mint(address(this), 1);
        underlying.approve(address(ibt), 1);
        ibt.deposit(1, address(this));

        // Principal token instance
        PrincipalTokenInstanceScript principalTokenInstanceScript = new PrincipalTokenInstanceScript();
        principalTokenInstance = PrincipalToken(
            principalTokenInstanceScript.deployForTest(address(registry))
        );

        // Yield token instance
        YTInstanceScript ytInstanceScript = new YTInstanceScript();
        YieldToken ytInstance = YieldToken(ytInstanceScript.deployForTest());

        // Rate adjustment oracle instance

        RateAdjustmentOracleInstanceScript rateAdjustmentOracleInstanceScript = new RateAdjustmentOracleInstanceScript();
        rateAdjustmentOracleInstance = RateAdjustmentOracle(
            rateAdjustmentOracleInstanceScript.deployForTest()
        );

        // Principal token beacon
        PrincipalTokenBeaconScript principalTokenBeaconScript = new PrincipalTokenBeaconScript();
        principalTokenBeacon = UpgradeableBeacon(
            principalTokenBeaconScript.deployForTest(
                address(principalTokenInstance),
                address(registry),
                address(accessManager)
            )
        );

        // YT beacon
        YTBeaconScript ytBeaconScript = new YTBeaconScript();
        ytBeacon = UpgradeableBeacon(
            ytBeaconScript.deployForTest(
                address(ytInstance),
                address(registry),
                address(accessManager)
            )
        );

        // Rate adjusment oracle beacon
        RateAdjustmentOracleBeaconScript raoScript = new RateAdjustmentOracleBeaconScript();
        rateAdjustmentOracleBeacon = UpgradeableBeacon(
            raoScript.deployForTest(
                address(rateAdjustmentOracleInstance),
                address(rateOracleRegistry),
                address(accessManager)
            )
        );
    }

    function testSetInitialPrice() public {
        uint256 initialPrice = UNIT;
        IFactorySNG.CurvePoolParams memory curvePoolParams = IFactorySNG.CurvePoolParams({
            A: 1500,
            fee: 1000000,
            fee_mul: 20000000000,
            ma_exp_time: 600,
            initial_price: initialPrice,
            rate_adjustment_oracle: address(0)
        });

        (, address _rateAdjustmentOracle, ) = __deployPoolWithInitialLiquidity(0, curvePoolParams);

        uint256 newInitialPrice = 2 * UNIT;

        vm.startPrank(scriptAdmin);
        IRateAdjustmentOracle(_rateAdjustmentOracle).setInitialPrice(newInitialPrice);

        assertEq(IRateAdjustmentOracle(_rateAdjustmentOracle).getInitialPrice(), 2 * UNIT);
        assertApproxEqAbs(IRateAdjustmentOracle(_rateAdjustmentOracle).value(), 2 * UNIT, 10);
    }

    function testInitialOracleValue(uint256 initialLiquidityIBT, uint256 initialPrice) public {
        initialLiquidityIBT = bound(
            initialLiquidityIBT,
            IBT_UNIT,
            1_000_000_000_000_000 * IBT_UNIT
        );

        initialPrice = bound(initialPrice, 10 ** 15, 10 ** 18 - 1);

        IFactorySNG.CurvePoolParams memory curvePoolParams = IFactorySNG.CurvePoolParams({
            A: 1500,
            fee: 1000000,
            fee_mul: 20000000000,
            ma_exp_time: 600,
            initial_price: initialPrice,
            rate_adjustment_oracle: address(0)
        });

        (, , address _curvePool) = __deployPoolWithInitialLiquidity(
            initialLiquidityIBT,
            curvePoolParams
        );

        uint256[] memory stored_rates = IStableSwapNG(_curvePool).stored_rates();
        assertApproxEqAbs(stored_rates[0], 10 ** 18, 1, "initial ibt rate oracle value is wrong");
        assertApproxEqAbs(
            stored_rates[1],
            initialPrice,
            IMPLIED_RATE_PRECISION,
            "initial pt rate oracle value is wrong"
        );
    }

    function testTerminalOracleValue(uint256 initialLiquidityIBT, uint256 initialPrice) public {
        initialLiquidityIBT = bound(
            initialLiquidityIBT,
            IBT_UNIT,
            1_000_000_000_000_000 * IBT_UNIT
        );
        initialPrice = bound(initialPrice, 10 ** 15, 10 ** 18 - 1);

        IFactorySNG.CurvePoolParams memory curvePoolParams = IFactorySNG.CurvePoolParams({
            A: 1500,
            fee: 1000000,
            fee_mul: 20000000000,
            ma_exp_time: 600,
            initial_price: initialPrice,
            rate_adjustment_oracle: address(0)
        });

        (address _pt, , address _curvePool) = __deployPoolWithInitialLiquidity(
            initialLiquidityIBT,
            curvePoolParams
        );

        _increaseTimeToExpiry(_pt, DURATION);
        uint256[] memory stored_rates = IStableSwapNG(_curvePool).stored_rates();
        assertApproxEqAbs(stored_rates[0], UNIT, 1, "initial ibt rate oracle value is wrong");
        assertApproxEqAbs(stored_rates[1], UNIT, 1, "initial pt rate oracle value is wrong");
    }

    function testTerminalOracleValueNegativeRate(
        uint256 initialLiquidityIBT,
        uint256 initialPrice,
        int256 ibtRateAccrual
    ) public {
        initialLiquidityIBT = bound(
            initialLiquidityIBT,
            IBT_UNIT,
            1_000_000_000_000_000 * IBT_UNIT
        );

        initialPrice = bound(initialPrice, MIN_INITIAL_PRICE, MAX_INITIAL_PRICE);
        ibtRateAccrual = bound(
            ibtRateAccrual,
            MIN_IBT_RATE_ACCRUAL_NEGATIVE,
            MAX_IBT_RATE_ACCRUAL_NEGATIVE
        );

        IFactorySNG.CurvePoolParams memory curvePoolParams = IFactorySNG.CurvePoolParams({
            A: 1500,
            fee: 1000000,
            fee_mul: 20000000000,
            ma_exp_time: 600,
            initial_price: initialPrice,
            rate_adjustment_oracle: address(0)
        });

        (address _pt, , address _curvePool) = __deployPoolWithInitialLiquidity(
            initialLiquidityIBT,
            curvePoolParams
        );

        _increaseRate(ibtRateAccrual);
        _increaseTimeToExpiry(_pt, DURATION);

        uint256[] memory stored_rates = IStableSwapNG(_curvePool).stored_rates();

        assertApproxEqAbs(stored_rates[0], uint256((100 + ibtRateAccrual)).mulDiv(UNIT, 100), 100);

        assertApproxEqAbs(
            IPrincipalToken(_pt).convertToUnderlying(UNIT),
            stored_rates[1],
            IMPLIED_RATE_PRECISION
        );
    }

    function testOracleValueNoTradeFuzz(
        uint256 initialLiquidityIBT,
        uint256 initialPrice,
        uint256 time,
        int256 ibtRateAccrual
    ) public {
        initialLiquidityIBT = bound(
            initialLiquidityIBT,
            IBT_UNIT,
            1_000_000_000_000_000 * IBT_UNIT
        );

        initialPrice = bound(initialPrice, MIN_INITIAL_PRICE, MAX_INITIAL_PRICE);
        ibtRateAccrual = bound(ibtRateAccrual, MIN_IBT_RATE_ACCRUAL, MAX_IBT_RATE_ACCRUAL);
        time = bound(time, MIN_TIME + 1, MAX_TIME - 1);

        IFactorySNG.CurvePoolParams memory curvePoolParams = IFactorySNG.CurvePoolParams({
            A: 1500,
            fee: 1000000,
            fee_mul: 20000000000,
            ma_exp_time: 600,
            initial_price: initialPrice,
            rate_adjustment_oracle: address(0)
        });

        (address _pt, , address _curvePool) = __deployPoolWithInitialLiquidity(
            initialLiquidityIBT,
            curvePoolParams
        );

        uint256 impliedRate = _implied_rate(
            initialPrice,
            block.timestamp,
            IPrincipalToken(_pt).maturity()
        );
        _increaseRate(ibtRateAccrual);
        _increaseTimeToExpiry(_pt, time);
        uint256[] memory stored_rates = IStableSwapNG(_curvePool).stored_rates();

        assertApproxEqAbs(
            stored_rates[0],
            (uint256((100 + ibtRateAccrual)) * UNIT) / 100,
            10,
            "initial ibt rate oracle value is wrong"
        );

        // compare the implied rates
        assertApproxEqRel(
            _implied_rate(stored_rates[1], block.timestamp, IPrincipalToken(_pt).maturity()),
            impliedRate,
            IMPLIED_RATE_PRECISION,
            "initial pt rate oracle value is wrong"
        );
    }

    /**
     * @dev Internal function for changing ibt rate with a determined rate as passed
     */
    function _increaseRate(int256 rate) internal {
        int256 currentRate = int256(ibt.convertToAssets(10 ** ibt.decimals()));
        int256 newRate = (currentRate * (rate + 100)) / 100;
        ibt.setPricePerFullShare(uint256(newRate));
    }

    function _increaseTimeToExpiry(address _principalToken, uint256 time) internal {
        console.log(time);
        assert(time + block.timestamp <= IPrincipalToken(_principalToken).maturity());
        time = block.timestamp + time;
        vm.warp(time);
    }

    /**
     * @notice calculates the implied rate given the exchange rate
     * @param price Current price of PT in IBT
     * @param current_timestamp Current timestamp
     * @param expiry Expiry timestamp of the PT
     */
    function _implied_rate(
        uint256 price,
        uint256 current_timestamp,
        uint256 expiry
    ) public pure returns (uint256) {
        if (current_timestamp >= expiry) {
            revert PTExpired();
        }
        uint256 exp = YEAR.mulDiv(UNIT, expiry - current_timestamp);
        return LogExpMath.pow(UNIT.mulDiv(UNIT, price), exp);
    }

    function __deployPoolWithInitialLiquidity(
        uint256 _initialLiquidityIBT,
        IFactorySNG.CurvePoolParams memory _params
    ) private returns (address, address, address) {
        FactorySNGScript factoryScript = new FactorySNGScript();
        factory = FactorySNG(
            factoryScript.deployForTest(
                address(registry),
                address(rateOracleRegistry),
                curveFactoryAddress,
                address(accessManager)
            )
        );
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.ADMIN_ROLE, address(factory), 0);
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.REGISTRY_ROLE, address(factory), 0);

        // Mint some IBT
        underlying.mint(MOCK_ADDR_1, 3 * ibt.convertToAssets(_initialLiquidityIBT));
        vm.startPrank(MOCK_ADDR_1);
        underlying.approve(address(ibt), 3 * ibt.convertToAssets(_initialLiquidityIBT));
        ibt.deposit(3 * ibt.convertToAssets(_initialLiquidityIBT), MOCK_ADDR_1);
        vm.stopPrank();

        // Deploy all with initial liquidity
        vm.startPrank(MOCK_ADDR_1);
        ibt.approve(address(factory), _initialLiquidityIBT);
        (address _pt, address _rateAdjustmentOracle, address _curvePool) = IFactorySNG(factory)
            .deployAll(address(ibt), DURATION, _params, _initialLiquidityIBT, 0);

        return (_pt, _rateAdjustmentOracle, _curvePool);
    }
}
