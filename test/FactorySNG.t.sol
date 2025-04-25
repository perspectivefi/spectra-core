// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "forge-std/Test.sol";

import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockIBT.sol";
import "../script/00_deployAccessManager.s.sol";
import "../script/01_deployRegistry.s.sol";
import "../script/02_deployPrincipalTokenInstance.s.sol";
import "../script/03_deployYTInstance.s.sol";
import "../script/04_deployPrincipalTokenBeacon.s.sol";
import "../src/RateOracleRegistry.sol";
import "../script/05_deployYTBeacon.s.sol";
import "../script/07_deployPrincipalToken.s.sol";
import "../script/08_deployCurvePool.s.sol";
import "../script/22_deployRateOracleRegistry.s.sol";
import "../script/23_deployFactorySNG.s.sol";
import "../script/24_deployRateAdjustmentOracleInstance.s.sol";
import "../script/25_deployRateAdjustmentOracleBeacon.s.sol";
import "../src/libraries/Roles.sol";
import "../src/libraries/RayMath.sol";
import "../src/amm/RateAdjustmentOracle.sol";
import "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";

contract ContractFactory is Test {
    using Math for uint256;
    using RayMath for uint256;

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
    uint256 public DURATION = 100000;
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

    // constants
    address public constant CURVE_FACTORY_ADDRESS = 0x6A8cbed756804B16E05E741eDaBd5cB544AE21bf;

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

    /**
     * @dev This function is called before each test.
     */
    function setUp() public {
        fork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(fork);
        curveFactoryAddress = CURVE_FACTORY_ADDRESS;
        admin = address(this); // also set as principalTokenAdmin.
        // default account for deploying scripts contracts. refer to line 35 of
        // https://github.com/foundry-rs/foundry/blob/master/evm/src/lib.rs for more details
        scriptAdmin = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
        AccessManagerDeploymentScript accessManagerScript = new AccessManagerDeploymentScript();
        accessManager = AccessManager(accessManagerScript.deployForTest(scriptAdmin));
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.UPGRADE_ROLE, scriptAdmin, 0);

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
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.RATE_ADJUSTMENT_ORACLE_SETTER_ROLE, scriptAdmin, 0);

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

    function testDeployFactoryFailWhenRegistryIsZero() public {
        // Factory
        bytes memory revertData = abi.encodeWithSelector(bytes4(keccak256("AddressError()")));
        vm.expectRevert(revertData);
        address _rateOracleRegistry = address(1);
        new FactorySNG(address(0), _rateOracleRegistry);
    }

    function testDeployFactoryFailWhenRateOracleRegistryIsZero() public {
        // Factory
        bytes memory revertData = abi.encodeWithSelector(bytes4(keccak256("AddressError()")));
        vm.expectRevert(revertData);
        address _registry = address(1);
        new FactorySNG(_registry, address(0));
    }

    function testDeployFactoryFailWhenCurveAddressIsZero() public {
        // Factory
        FactorySNGScript factorySNGScript = new FactorySNGScript();
        bytes memory revertData = abi.encodeWithSelector(bytes4(keccak256("AddressError()")));
        new FactorySNG(address(registry), address(rateOracleRegistry));
        vm.expectRevert(revertData);
        factory = FactorySNG(
            factorySNGScript.deployForTest(
                address(registry),
                address(rateOracleRegistry),
                address(0),
                address(accessManager)
            )
        );
    }

    function testSetCurveFactory() public {
        // Factory
        FactorySNGScript factorySNGScript = new FactorySNGScript();
        factory = FactorySNG(
            factorySNGScript.deployForTest(
                address(registry),
                address(rateOracleRegistry),
                curveFactoryAddress,
                address(accessManager)
            )
        );
        vm.expectEmit(true, true, false, false);
        emit CurveFactoryChange(curveFactoryAddress, address(0xfac));
        vm.prank(scriptAdmin);
        factory.setCurveFactory(address(0xfac));
    }

    function testFactorySNGDeployAllWithoutInitialLiquidity() public {
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

        IFactorySNG.CurvePoolParams memory curvePoolParams = IFactorySNG.CurvePoolParams({
            A: 1500,
            fee: 1000000,
            fee_mul: 20000000000,
            ma_exp_time: 600,
            initial_price: 1e18,
            rate_adjustment_oracle: address(0)
        });

        (address _pt, , address _curvePool) = IFactorySNG(factory).deployAll(
            address(ibt),
            DURATION,
            curvePoolParams,
            0,
            0
        );

        assertEq(IPrincipalToken(_pt).underlying(), ibt.asset());
        assertEq(IPrincipalToken(_pt).getDuration(), DURATION);
        assertEq(IPrincipalToken(_pt).getIBT(), address(ibt));
        assertEq(IERC4626(_curvePool).symbol(), "SPT-PT/IBT");
        assertEq(IERC4626(_curvePool).name(), "Spectra-PT/IBT");

        assertEq(
            IPrincipalToken(_pt).symbol(),
            NamingUtil.genPTSymbol(ibt.symbol(), IPrincipalToken(_pt).maturity())
        );

        assertEq(
            IPrincipalToken(_pt).name(),
            NamingUtil.genPTName(ibt.symbol(), IPrincipalToken(_pt).maturity())
        );
        assertEq(IStableSwapNG(_curvePool).A(), curvePoolParams.A);
        assertEq(IStableSwapNG(_curvePool).fee(), curvePoolParams.fee);
        assertEq(IStableSwapNG(_curvePool).offpeg_fee_multiplier(), curvePoolParams.fee_mul);
        assertEq(IStableSwapNG(_curvePool).ma_exp_time(), curvePoolParams.ma_exp_time);
    }

    function testFactorySNGDeployAllWithInitialLiquidityFuzz(
        uint256 initialLiquidityIBT,
        uint256 initialPrice
    ) public {
        initialLiquidityIBT = bound(
            initialLiquidityIBT,
            IBT_UNIT,
            1_000_000_000_000_000 * IBT_UNIT
        );
        initialPrice = bound(initialPrice, 10 ** 15, 10 ** 18 - 1);

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

        IFactorySNG.CurvePoolParams memory curvePoolParams = IFactorySNG.CurvePoolParams({
            A: 1500,
            fee: 1000000,
            fee_mul: 20000000000,
            ma_exp_time: 600,
            initial_price: initialPrice,
            rate_adjustment_oracle: address(0)
        });

        // Mint some IBT
        underlying.mint(MOCK_ADDR_1, 3 * ibt.convertToAssets(initialLiquidityIBT));
        vm.startPrank(MOCK_ADDR_1);
        underlying.approve(address(ibt), 3 * ibt.convertToAssets(initialLiquidityIBT));
        ibt.deposit(3 * ibt.convertToAssets(initialLiquidityIBT), MOCK_ADDR_1);
        vm.stopPrank();

        // Deploy all with initial liquidity
        vm.startPrank(MOCK_ADDR_1);
        ibt.approve(address(factory), initialLiquidityIBT);
        (, , address _curvePool) = IFactorySNG(factory).deployAll(
            address(ibt),
            DURATION,
            curvePoolParams,
            initialLiquidityIBT,
            0
        );

        assertEq(IERC20(_curvePool).balanceOf(MOCK_ADDR_1), IERC20(_curvePool).totalSupply());
    }

    function testFactoryDeployAllFailBeaconNotSet() public {
        RegistryScript registryScript = new RegistryScript();
        // Setup a registry with beacon proxies not set
        Registry registryBeaconProxyUnset = Registry(
            registryScript.deployForTest(
                TOKENIZATION_FEE,
                YIELD_FEE,
                PT_FLASH_LOAN_FEE,
                feeCollector,
                address(accessManager)
            )
        );

        RateOracleRegistryScript rateOracleRegistryScript = new RateOracleRegistryScript();
        // Setup a rate oracle registry with beacon proxies not set
        RateOracleRegistry rateOracleRegistryBeaconProxyUnset = RateOracleRegistry(
            rateOracleRegistryScript.deployForTest(address(accessManager))
        );

        FactorySNGScript factoryScript = new FactorySNGScript();
        factory = FactorySNG(
            factoryScript.deployForTest(
                address(registryBeaconProxyUnset),
                address(rateOracleRegistryBeaconProxyUnset),
                curveFactoryAddress,
                address(accessManager)
            )
        );
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.ADMIN_ROLE, address(factory), 0);
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.REGISTRY_ROLE, address(factory), 0);

        IFactorySNG.CurvePoolParams memory curvePoolParams = IFactorySNG.CurvePoolParams({
            A: 1500,
            fee: 1000000,
            fee_mul: 20000000000,
            ma_exp_time: 600,
            initial_price: 1e18,
            rate_adjustment_oracle: address(0)
        });

        bytes memory revertData = abi.encodeWithSelector(bytes4(keccak256("BeaconNotSet()")));

        vm.expectRevert(revertData);
        IFactorySNG(factory).deployAll(address(ibt), DURATION, curvePoolParams, 0, 0);
    }

    /**
     * @dev Internal function for changing ibt rate with a determined rate as passed
     */
    function _increaseRate(int256 rate) internal {
        int256 currentRate = int256(ibt.convertToAssets(10 ** ibt.decimals()));
        int256 newRate = (currentRate * (rate + 100)) / 100;
        ibt.setPricePerFullShare(uint256(newRate));
    }
}
