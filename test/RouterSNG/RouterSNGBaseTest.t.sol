// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "forge-std/Test.sol";

import "../../src/mocks/MockUnderlyingCustomDecimals.sol";
import "../../src/mocks/MockIBTCustomDecimals.sol";
import "script/00_deployAccessManager.s.sol";
import "script/01_deployRegistry.s.sol";
import "script/02_deployPrincipalTokenInstance.s.sol";
import "script/03_deployYTInstance.s.sol";
import "script/04_deployPrincipalTokenBeacon.s.sol";
import "script/05_deployYTBeacon.s.sol";
import "script/06_deployFactory.s.sol";
import "script/07_deployPrincipalToken.s.sol";
import "script/08_deployCurvePool.s.sol";
import "script/09_deployRouter.s.sol";
import "script/22_deployRateOracleRegistry.s.sol";
import "script/23_deployFactorySNG.s.sol";
import "script/24_deployRateAdjustmentOracleInstance.s.sol";
import "script/25_deployRateAdjustmentOracleBeacon.s.sol";
import "src/mocks/MockERC20.sol";
import "src/mocks/MockIBT2.sol";
import "src/mocks/MockSpectra4626Wrapper.sol";
import {MockFaucet} from "src/mocks/MockFaucet.sol";
import {Router} from "src/router/Router.sol";
import {RouterUtil} from "src/router/util/RouterUtil.sol";
import {CurveLiqArbitrage} from "src/router/util/CurveLiqArbitrage.sol";
import {Commands} from "src/router/Commands.sol";
import {Constants} from "src/router/Constants.sol";
import {IStableSwapNG} from "src/interfaces/IStableSwapNG.sol";
import {IPrincipalToken} from "src/interfaces/IPrincipalToken.sol";
import {PrincipalToken} from "src/tokens/PrincipalToken.sol";
import {IRateAdjustmentOracle} from "src/interfaces/IRateAdjustmentOracle.sol";
import {RateAdjustmentOracle} from "src/amm/RateAdjustmentOracle.sol";
import {RateOracleRegistry} from "src/RateOracleRegistry.sol";
import {FactorySNG} from "src/factory/FactorySNG.sol";
import "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {IERC20} from "openzeppelin-contracts/interfaces/IERC20.sol";

error CouldNotFetchLPToken();
error FailedToAddInitialLiquidity();

contract RouterSNGBaseTest is Test {
    PrincipalToken public principalToken;
    FactorySNG public factory;
    RateAdjustmentOracle public rateAdjustmentOracle;
    AccessManager public accessManager;
    MockUnderlyingCustomDecimals public underlying;
    MockIBTCustomDecimals public ibt;
    MockSpectra4626Wrapper public spectra4626Wrapper;
    IERC20Metadata public lpToken;
    IStableSwapNG public curvePool;
    UpgradeableBeacon public principalTokenBeacon;
    UpgradeableBeacon public ytBeacon;
    address public curveFactoryAddress;
    YieldToken public yt;
    Router public router;
    address payable public routerAddr;
    RouterUtil public routerUtil;
    address kyberRouterAddr;
    CurveLiqArbitrage public curveLiqArbitrage;
    address public routerUtilAddr;
    address public curveLiqArbitrageAddr;
    Registry public registry;
    RateOracleRegistry public rateOracleRegistry;
    address feeCollector = 0x0000000000000000000000000000000000000FEE;
    address public other = 0x0000000000000000000000000000000000011111; // Do *NOT* use anything already in Constants.sol as it will not behave as expected
    uint256 public fork;
    uint256 public constant FAUCET_AMOUNT = 10e18; // initial amount of underlying & IBT to give to the user
    uint256 public FAUCET_AMOUNT_UND;
    uint256 public FAUCET_AMOUNT_IBT;
    string SEPOLIA_RPC_URL = vm.envString("MAINNET_RPC_URL");
    uint256 public TOKENIZATION_FEE = 1e15;
    uint256 public YIELD_FEE = 0;
    uint256 public PT_FLASH_LOAN_FEE = 0;
    uint256 public constant DURATION = 15724800; // 182 days
    uint256 public IBT_UNIT;
    uint256 public UNDERLYING_UNIT;
    address public testUser;
    address public scriptAdmin;
    address public curvePoolAddr;

    uint256 public constant UND_DEPOSIT_AMOUNT = 1_000_000;
    uint256 public constant UNIT = 10 ** 18;
    uint256 public constant MIN_INITIAL_PRICE = 8 * 10 ** 17;
    uint256 public constant MAX_INITIAL_PRICE = UNIT - 1;
    uint256 public constant MIN_DECIMALS = 6;
    uint256 public constant MAX_DECIMALS = 18;

    IFactorySNG.CurvePoolParams curvePoolParams;

    // Events
    event PTDeployed(address indexed principalToken, address indexed poolCreator);
    event CurvePoolDeployed(address indexed poolAddress, address indexed ibt, address indexed pt);

    /**
     * @dev This is the function to deploy principalToken and other mock contracts
     * for testing. It is called before each test.
     */
    function setUp() public virtual {
        fork = vm.createFork(SEPOLIA_RPC_URL);
        vm.selectFork(fork);
        curveFactoryAddress = 0x6A8cbed756804B16E05E741eDaBd5cB544AE21bf;
        // default account for deploying scripts contracts. refer to line 35 of
        // https://github.com/foundry-rs/foundry/blob/master/evm/src/lib.rs for more details
        scriptAdmin = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
        testUser = address(this); // to reduce number of lines and repeated vm pranks
        AccessManagerDeploymentScript accessManagerScript = new AccessManagerDeploymentScript();
        accessManager = AccessManager(accessManagerScript.deployForTest(scriptAdmin));

        // deploy registry
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
        // setting tokenization fees to 0 (for convenience since they were added after all those tests)
        vm.prank(scriptAdmin);
        registry.setTokenizationFee(0);

        RateOracleRegistryScript rateOracleRegistryScript = new RateOracleRegistryScript();
        rateOracleRegistry = RateOracleRegistry(
            rateOracleRegistryScript.deployForTest(address(accessManager))
        );

        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.REGISTRY_ROLE, scriptAdmin, 0);

        // deploy router
        RouterScript routerScript = new RouterScript();
        (routerAddr, routerUtilAddr, curveLiqArbitrageAddr) = routerScript.deployForTest(
            address(registry),
            kyberRouterAddr,
            address(accessManager)
        );
        router = Router(routerAddr);
        routerUtil = RouterUtil(routerUtilAddr);

        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.UPGRADE_ROLE, scriptAdmin, 0);
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.PAUSER_ROLE, scriptAdmin, 0);

        // deploy wrapper on top of ibt;

        // deploy principalToken and yieldToken instances and beacons
        PrincipalTokenInstanceScript principalTokenInstanceScript = new PrincipalTokenInstanceScript();
        YTInstanceScript ytInstanceScript = new YTInstanceScript();
        PrincipalToken principalTokenInstance = PrincipalToken(
            principalTokenInstanceScript.deployForTest(address(registry))
        );
        YieldToken ytInstance = YieldToken(ytInstanceScript.deployForTest());

        PrincipalTokenBeaconScript principalTokenBeaconScript = new PrincipalTokenBeaconScript();
        YTBeaconScript ytBeaconScript = new YTBeaconScript();
        principalTokenBeacon = UpgradeableBeacon(
            principalTokenBeaconScript.deployForTest(
                address(principalTokenInstance),
                address(registry),
                address(accessManager)
            )
        );
        ytBeacon = UpgradeableBeacon(
            ytBeaconScript.deployForTest(
                address(ytInstance),
                address(registry),
                address(accessManager)
            )
        );

        // deploy rate adjustment oracle

        RateAdjustmentOracleInstanceScript raoScript = new RateAdjustmentOracleInstanceScript();
        RateAdjustmentOracle raoInstance = RateAdjustmentOracle(raoScript.deployForTest());
        RateAdjustmentOracleBeaconScript raoBeaconScript = new RateAdjustmentOracleBeaconScript();
        UpgradeableBeacon rateAdjustmentOracleBeacon = UpgradeableBeacon(
            raoBeaconScript.deployForTest(
                address(raoInstance),
                address(rateOracleRegistry),
                address(accessManager)
            )
        );

        // set the rate oracle beacon in the rate oracle registry
        vm.prank(scriptAdmin);
        rateOracleRegistry.setRateOracleBeacon(address(rateAdjustmentOracleBeacon));

        // deploy factory
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

        uint256 initialPrice = 0.8 * 10 ** 18;
        curvePoolParams = IFactorySNG.CurvePoolParams({
            A: 300,
            fee: 1000000,
            fee_mul: 20000000000,
            ma_exp_time: 600,
            initial_price: initialPrice,
            rate_adjustment_oracle: address(0)
        });
        this.deployProtocol(18, 18, address(factory), curvePoolParams);
    }

    function deployProtocol(
        uint8 underlyingDecimals,
        uint8 ibtDecimals,
        address factorySNG,
        IFactorySNG.CurvePoolParams memory _curvePoolParams
    ) public {
        // deploy underlying and ibt
        underlying = new MockUnderlyingCustomDecimals();
        underlying.initialize("MOCK UNDERLYING", "MUDL", underlyingDecimals); // deploys underlying mints 100000e18 token to caller
        ibt = new MockIBTCustomDecimals("MOCK IBT", "MIBT", IERC20(underlying), ibtDecimals); // deploys ibt which principalToken holds
        spectra4626Wrapper = new MockSpectra4626Wrapper();
        spectra4626Wrapper.initialize(address(ibt), address(accessManager));

        UNDERLYING_UNIT = 10 ** uint256(underlying.decimals());
        IBT_UNIT = 10 ** uint256(ibt.decimals());

        FAUCET_AMOUNT_UND = 10 * UNDERLYING_UNIT;
        FAUCET_AMOUNT_IBT = 10 * IBT_UNIT;

        MockUnderlyingCustomDecimals(underlying).mint(
            testUser,
            UND_DEPOSIT_AMOUNT * UNDERLYING_UNIT
        );
        underlying.approve(address(ibt), UND_DEPOSIT_AMOUNT * UNDERLYING_UNIT);
        uint256 shares = ibt.deposit(UND_DEPOSIT_AMOUNT * UNDERLYING_UNIT, testUser);

        ibt.approve(address(factory), shares);
        (address _pt, address _rateAdjustmentOracle, address _curvePoolAddr) = factory.deployAll(
            address(ibt),
            DURATION,
            _curvePoolParams,
            shares,
            0
        );

        principalToken = PrincipalToken(_pt);
        yt = YieldToken(principalToken.getYT());
        rateAdjustmentOracle = RateAdjustmentOracle(_rateAdjustmentOracle);
        curvePoolAddr = _curvePoolAddr;
        lpToken = IERC20Metadata(_curvePoolAddr);
        curvePool = IStableSwapNG(_curvePoolAddr);
        vm.stopPrank();

        vm.startPrank(testUser); // remove any leftover balance
        ibt.transfer(other, ibt.balanceOf(testUser));
        underlying.transfer(other, underlying.balanceOf(testUser));
        // prepare approvals
        underlying.approve(address(ibt), FAUCET_AMOUNT_UND * 2);
        underlying.approve(address(router), FAUCET_AMOUNT_UND);
        ibt.approve(address(router), FAUCET_AMOUNT_IBT);
        ibt.approve(address(spectra4626Wrapper), FAUCET_AMOUNT_IBT);
        spectra4626Wrapper.approve(address(router), FAUCET_AMOUNT_IBT);
        vm.stopPrank();
    }
}
