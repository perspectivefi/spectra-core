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
import {ICurveFactory} from "src/interfaces/ICurveFactory.sol";
import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {IPrincipalToken} from "src/interfaces/IPrincipalToken.sol";
import {PrincipalToken} from "src/tokens/PrincipalToken.sol";
import "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {IERC20} from "openzeppelin-contracts/interfaces/IERC20.sol";

error DeploymentFailed();
error CouldNotFetchLPToken();
error FailedToAddInitialLiquidity();

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

contract RouterBaseTest is Test {
    PrincipalToken public principalToken;
    Factory public factory;
    AccessManager public accessManager;
    MockERC20 public underlying;
    MockIBT2 public ibt;
    MockSpectra4626Wrapper public spectra4626Wrapper;
    IERC20Metadata public lpToken;
    ICurvePool public curvePool;
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
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    uint256 public TOKENIZATION_FEE = 0;
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
        curveFactoryAddress = 0x90f584A7AfA70ECa0cf073082Ab0Ec95e5EfE38a;
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

        curvePoolAddr = _deployCurvePool(address(principalToken), curvePoolDeploymentData);
        curvePool = ICurvePool(curvePoolAddr);

        (bool successLPToken, bytes memory response) = curvePoolAddr.call(
            abi.encodeWithSelector(0xfc0c546a)
        );
        if (!successLPToken) {
            revert CouldNotFetchLPToken();
        }
        lpToken = IERC20Metadata(abi.decode(response, (address)));

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
        (bool success, bytes memory result) = address(curveFactoryAddress).call(cd);
        if (!success) {
            revert DeploymentFailed();
        }

        assembly {
            _curvePoolAddr := mload(add(add(result, 12), 20))
        }
    }
}
