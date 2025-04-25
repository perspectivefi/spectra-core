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
import "script/08_deployCurvePool.s.sol";
import "script/09_deployRouter.s.sol";
import "src/mocks/MockERC20.sol";
import "src/mocks/MockIBT2.sol";
import "src/mocks/MockSpectra4626Wrapper.sol";
import {MockFaucet} from "src/mocks/MockFaucet.sol";
import {Router} from "src/router/Router.sol";
import {RouterUtil} from "src/router/util/RouterUtil.sol";
import {CurveLiqArbitrage} from "src/router/util/CurveLiqArbitrage.sol";
import {Commands} from "src/router/Commands.sol";
import {Constants} from "src/router/Constants.sol";
import {ICurveNGPool} from "src/interfaces/ICurveNGPool.sol";
import {IPrincipalToken} from "src/interfaces/IPrincipalToken.sol";
import {PrincipalToken} from "src/tokens/PrincipalToken.sol";
import "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {IERC20} from "openzeppelin-contracts/interfaces/IERC20.sol";

error FailedToAddInitialLiquidity();

contract RouterNGBaseTest is Test {
    PrincipalToken public principalToken;
    Factory public factory;
    AccessManager public accessManager;
    MockERC20 public underlying;
    MockIBT2 public ibt;
    MockSpectra4626Wrapper public spectra4626Wrapper;
    ICurveNGPool public curvePool;
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
    address feeCollector = 0x0000000000000000000000000000000000000FEE;
    address public other = 0x0000000000000000000000000000000000011111; // Do *NOT* use anything already in Constants.sol as it will not behave as expected
    uint256 public fork;
    uint256 public constant FAUCET_AMOUNT = 10e18; // initial amount of underlying & IBT to give to the user
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL"); // dev: newest release of curve ng pools not deployed on sepolia
    uint256 public TOKENIZATION_FEE = 1e15;
    uint256 public YIELD_FEE = 0;
    uint256 public PT_FLASH_LOAN_FEE = 0;
    uint256 public constant DURATION = 15724800; // 182 days
    uint256 public IBT_UNIT;
    address public testUser;
    address public scriptAdmin;
    address public curvePoolAddr;

    // Events
    event PTDeployed(address indexed principalToken, address indexed poolCreator);
    event CurvePoolDeployed(address indexed poolAddress, address indexed ibt, address indexed pt);

    /**
     * @dev This is the function to deploy principalToken and other mock contracts
     * for testing. It is called before each test.
     */
    function setUp() public virtual {
        fork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(fork);
        curveFactoryAddress = 0x98EE851a00abeE0d95D08cF4CA2BdCE32aeaAF7F;
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

        // deploy router
        RouterScript routerScript = new RouterScript();
        (routerAddr, routerUtilAddr, curveLiqArbitrageAddr) = routerScript.deployForTest(
            address(registry),
            kyberRouterAddr,
            address(accessManager)
        );
        router = Router(routerAddr);
        routerUtil = RouterUtil(routerUtilAddr);
        curveLiqArbitrage = CurveLiqArbitrage(curveLiqArbitrageAddr);

        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.UPGRADE_ROLE, scriptAdmin, 0);
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.PAUSER_ROLE, scriptAdmin, 0);

        // deploy underlying and ibt
        underlying = new MockERC20();
        underlying.initialize("MOCK UNDERLYING", "MUDL"); // deploys underlying mints 100000e18 token to caller
        ibt = new MockIBT2();
        ibt.initialize("MOCK IBT", "MIBT", IERC20Metadata(address(underlying))); // deploys ibt which principalToken holds
        IBT_UNIT = 10 ** ibt.decimals();
        underlying.approve(address(ibt), 10_000_000e18);
        ibt.deposit(10_000_000e18, other);

        // deploy wrapper on top of ibt;
        spectra4626Wrapper = new MockSpectra4626Wrapper();
        spectra4626Wrapper.initialize(address(ibt), address(accessManager));

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

        // deploy factory
        FactoryScript factoryScript = new FactoryScript();
        factory = Factory(
            factoryScript.deployForTest(
                address(registry),
                curveFactoryAddress,
                address(accessManager)
            )
        );
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.ADMIN_ROLE, address(factory), 0);
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.REGISTRY_ROLE, address(factory), 0);

        // deploy principalToken
        PrincipalTokenScript principalTokenScript = new PrincipalTokenScript();
        vm.expectEmit(false, true, false, true);
        emit PTDeployed(address(principalTokenInstance), scriptAdmin);
        address principalTokenAddr = principalTokenScript.deployForTest(
            address(factory),
            address(ibt),
            DURATION
        );
        principalToken = PrincipalToken(principalTokenAddr);
        yt = YieldToken(principalToken.getYT());

        // deploy curve pool
        CurvePoolScript curvePoolScript = new CurvePoolScript();
        IFactory.CurvePoolParams memory curvePoolDeploymentData;
        curvePoolDeploymentData.A = 2e6;
        curvePoolDeploymentData.gamma = 1e15;
        curvePoolDeploymentData.mid_fee = 5000000;
        curvePoolDeploymentData.out_fee = 45000000;
        curvePoolDeploymentData.fee_gamma = 5000000000000000;
        curvePoolDeploymentData.allowed_extra_profit = 10000000000;
        curvePoolDeploymentData.adjustment_step = 5500000000000;
        curvePoolDeploymentData.ma_exp_time = 1200;
        curvePoolDeploymentData.initial_price = 8e17;
        vm.expectEmit(false, true, true, true);
        emit CurvePoolDeployed(address(0), address(ibt), principalTokenAddr);
        curvePoolAddr = curvePoolScript.deployForTest(
            address(factory),
            address(ibt),
            principalTokenAddr,
            curvePoolDeploymentData,
            0,
            0
        );
        curvePool = ICurveNGPool(curvePoolAddr);

        // add initial liquidity to curve pool according to initial price
        underlying.mint(testUser, 1_800_000e18);
        underlying.approve(address(ibt), 800_000e18);
        uint256 amountIBT = ibt.deposit(800_000e18, testUser);
        underlying.approve(principalTokenAddr, 1_000_000e18);
        uint256 amountPT = principalToken.deposit(1_000_000e18, testUser);
        ibt.approve(curvePoolAddr, amountIBT);
        principalToken.approve(curvePoolAddr, amountPT);
        (bool success, ) = curvePoolAddr.call(
            abi.encodeWithSelector(0x0b4c7e4d, [amountIBT, amountPT], 0)
        );
        if (!success) {
            revert FailedToAddInitialLiquidity();
        }

        vm.startPrank(testUser);
        // remove any leftover balance
        ibt.transfer(other, ibt.balanceOf(testUser));
        underlying.transfer(other, underlying.balanceOf(testUser));
        // prepare approvals
        underlying.approve(address(ibt), FAUCET_AMOUNT * 2);
        underlying.approve(address(router), FAUCET_AMOUNT);
        ibt.approve(address(router), FAUCET_AMOUNT);
        ibt.approve(address(spectra4626Wrapper), FAUCET_AMOUNT);
        spectra4626Wrapper.approve(address(router), FAUCET_AMOUNT);
        vm.stopPrank();
    }
}
