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
import "../script/05_deployYTBeacon.s.sol";
import "../script/06_deployFactory.s.sol";
import "../script/07_deployPrincipalToken.s.sol";
import "../script/08_deployCurvePool.s.sol";
import "../src/libraries/Roles.sol";
import "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";

contract ContractFactory is Test {
    using Math for uint256;

    struct CurvePoolDeploymentData {
        address[2] coins;
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

    struct TestData {
        address erc20LP;
        uint256 mock1LPT;
        uint256 totalAssetValue;
        uint256 tokenFee;
        uint256 mock1LPT2;
        uint256 totalAssetValue2;
        uint256 mock1LPT3;
        uint256 totalAssetValue3;
        uint256 mock1LPT4;
        uint256 totalAssetValue4;
        uint256 ibtBalanceBefore;
        uint256 ibtBalanceAfter1;
        uint256 ibtBalanceAfter2;
        uint256 initialLiquidityInIBT;
        uint256 ibtBalanceInPTFromInitPrice;
        uint256 ptBalanceAdded;
        uint256 ibtBalanceAdded;
        uint256 ibtBalanceInPTFromInitPrice2;
        uint256 ptBalanceAdded2;
        uint256 ibtBalanceAdded2;
    }

    Factory public factory;
    AccessManager public accessManager;
    PrincipalToken public principalToken;
    MockERC20 public underlying;
    PrincipalToken public principalTokenInstance;
    MockIBT public ibt;
    uint256 public DURATION = 100000;
    uint256 public IBT_UNIT;
    Registry public registry;
    address public admin;
    address public scriptAdmin;
    address public curveAddressProvider;
    address public curveFactoryAddress;
    address public curvePoolAddr;
    IERC20Metadata public lpToken;
    address feeCollector = 0x0000000000000000000000000000000000000FEE;
    address MOCK_ADDR_1 = 0x0000000000000000000000000000000000000001;
    uint256 public TOKENIZATION_FEE = 1e15;
    uint256 public YIELD_FEE = 0;
    uint256 public PT_FLASH_LOAN_FEE = 0;
    string GOERLI_RPC_URL = vm.envString("GOERLI_RPC_URL");
    uint256 fork;
    YieldToken public yt;
    UpgradeableBeacon public principalTokenBeacon;
    UpgradeableBeacon public ytBeacon;

    // Events
    event PTDeployed(address indexed principalToken, address indexed poolCreator);
    event CurvePoolDeployed(address indexed poolAddress, address indexed ibt, address indexed pt);

    error CouldNotFetchLPToken();
    error FailedToAddInitialLiquidity();

    /**
     * @dev This function is called before each test.
     */
    function setUp() public {
        fork = vm.createFork(GOERLI_RPC_URL);
        vm.selectFork(fork);
        curveAddressProvider = address(0x44Ba140128cae03A13A7cD5F3Da32b5Cd73c1c7a);
        curveFactoryAddress = address(0xAd86AA4a359fA82e449F4486beD9Db1253DcE4Db);
        admin = address(this); // also set as principalTokenAdmin.
        // default account for deploying scripts contracts. refer to line 35 of
        // https://github.com/foundry-rs/foundry/blob/master/evm/src/lib.rs for more details
        scriptAdmin = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
        AccessManagerDeploymentScript accessManagerScript = new AccessManagerDeploymentScript();
        accessManager = AccessManager(accessManagerScript.deployForTest(scriptAdmin));
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.UPGRADE_ROLE, scriptAdmin, 0);
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
        underlying = new MockERC20();
        underlying.initialize("MOCK UNDERLYING", "MUDL"); // deploys underlying mints 100000e18 token to caller
        ibt = new MockIBT();
        ibt.initialize("MOCK IBT", "MIBT", IERC20Metadata(address(underlying))); // deploys ibt which principalToken holds
        IBT_UNIT = 10 ** ibt.decimals();
        underlying.mint(address(this), 1);
        underlying.approve(address(ibt), 1);
        ibt.deposit(1, address(this));
        PrincipalTokenInstanceScript principalTokenInstanceScript = new PrincipalTokenInstanceScript();
        YTInstanceScript ytInstanceScript = new YTInstanceScript();
        principalTokenInstance = PrincipalToken(
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
    }

    function testDeployPrincipalToken() public {
        // Factory
        FactoryScript factoryScript = new FactoryScript();
        factory = Factory(factoryScript.deployForTest(address(registry), address(accessManager)));
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.ADMIN_ROLE, address(factory), 0);
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.REGISTRY_ROLE, address(factory), 0);

        PrincipalTokenScript principalTokenScript = new PrincipalTokenScript();
        vm.expectEmit(false, true, false, true);
        emit PTDeployed(address(principalTokenInstance), scriptAdmin);
        // deploys principalToken
        address principalTokenAddress = principalTokenScript.deployForTest(
            address(factory),
            address(ibt),
            DURATION
        );

        assertTrue(
            PrincipalToken(principalTokenAddress).maturity() == DURATION + block.timestamp,
            "PrincipalTokenFactory: Future Vault attributes do not match after deploying"
        );
    }

    function testDeployPrincipalTokenFailWithoutYTBeacon() public {
        // Factory
        FactoryScript factoryScript = new FactoryScript();
        RegistryScript registryScript = new RegistryScript();
        // Setup a registry with beacon proxies not set
        Registry registry2 = Registry(
            registryScript.deployForTest(
                TOKENIZATION_FEE,
                YIELD_FEE,
                PT_FLASH_LOAN_FEE,
                feeCollector,
                address(accessManager)
            )
        );
        factory = Factory(factoryScript.deployForTest(address(registry2), address(accessManager)));
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.ADMIN_ROLE, address(factory), 0);
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.REGISTRY_ROLE, address(factory), 0);
        bytes memory revertData = abi.encodeWithSignature("BeaconNotSet()");
        vm.expectRevert(revertData);
        factory.deployPT(address(ibt), DURATION);
    }

    function testSetRegistryFailWhenUnauthorizedCaller() public {
        // Factory
        FactoryScript factoryScript = new FactoryScript();
        factory = Factory(factoryScript.deployForTest(address(registry), address(accessManager)));
        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("AccessManagedUnauthorized(address)")),
            MOCK_ADDR_1
        );
        vm.expectRevert(revertData);
        vm.prank(MOCK_ADDR_1);
        factory.setRegistry(address(registry));
    }

    function testSetRegistryFailWhenRegistryIsZero() public {
        // Factory
        FactoryScript factoryScript = new FactoryScript();
        factory = Factory(factoryScript.deployForTest(address(registry), address(accessManager)));
        bytes memory revertData = abi.encodeWithSelector(bytes4(keccak256("AddressError()")));
        vm.expectRevert(revertData);
        vm.prank(scriptAdmin);
        factory.setRegistry(address(0));
    }

    function testSetCurveAddressProviderFailWhenCurveAddressIsZero() public {
        // Factory
        FactoryScript factoryScript = new FactoryScript();
        factory = Factory(factoryScript.deployForTest(address(registry), address(accessManager)));
        bytes memory revertData = abi.encodeWithSelector(bytes4(keccak256("AddressError()")));
        vm.expectRevert(revertData);
        vm.prank(scriptAdmin);
        factory.setCurveAddressProvider(address(0));
    }

    function testSetCurveAddressProviderFailWhenNotCurve() public {
        // Factory
        FactoryScript factoryScript = new FactoryScript();
        factory = Factory(factoryScript.deployForTest(address(registry), address(accessManager)));
        // We need to get a contract account (CA) to get a valid fallback for call tx
        MockIBT mockIBT = new MockIBT();
        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("FailedToFetchCurveFactoryAddress()"))
        );
        vm.expectRevert(revertData);
        vm.prank(scriptAdmin);
        factory.setCurveAddressProvider(address(mockIBT));
    }

    /*
     * The test checks that the curve factory address is set
     * correctly upon setting the curve address provider.
     * The addresses are the one of mock contracts on Goerli.
     * The test check only the logic of the setters and the encoding
     * of the function selector for curve get_address(uint256) function.
     * https://curve.readthedocs.io/registry-address-provider.html#AddressProvider.get_address
     */
    function testSetCurveAddressProviderFactoryFetch() public {
        // Factory
        FactoryScript factoryScript = new FactoryScript();
        factory = Factory(factoryScript.deployForTest(address(registry), address(accessManager)));
        vm.prank(scriptAdmin);
        factory.setCurveAddressProvider(curveAddressProvider);
        assertEq(curveAddressProvider, factory.getCurveAddressProvider());
        assertEq(curveFactoryAddress, factory.getCurveFactory());
    }

    function testDeployPrincipalTokenWithBeaconNotSet() public {
        // Factory
        FactoryScript factoryScript = new FactoryScript();
        RegistryScript registryScript = new RegistryScript();
        // Setup a registry with beacon proxies not set
        Registry registry2 = Registry(
            registryScript.deployForTest(
                TOKENIZATION_FEE,
                YIELD_FEE,
                PT_FLASH_LOAN_FEE,
                feeCollector,
                address(accessManager)
            )
        );
        factory = Factory(factoryScript.deployForTest(address(registry2), address(accessManager)));
        vm.prank(scriptAdmin);
        bytes memory revertData = abi.encodeWithSelector(bytes4(keccak256("BeaconNotSet()")));
        vm.expectRevert(revertData);
        factory.deployPT(address(ibt), DURATION);
    }

    function testFactoryDeployCurvePoolWithoutCurveFactoryFail() public {
        // Factory
        FactoryScript factoryScript = new FactoryScript();
        factory = Factory(factoryScript.deployForTest(address(registry), address(accessManager)));
        bytes memory revertData = abi.encodeWithSelector(bytes4(keccak256("CurveFactoryNotSet()")));
        vm.expectRevert(revertData);
        factory.deployCurvePool(
            address(0),
            IFactory.CurvePoolParams(0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
            0
        );
    }

    function testFactoryDeployCurvePoolWithUnregisteredPTFail() public {
        // Factory
        FactoryScript factoryScript = new FactoryScript();
        factory = Factory(factoryScript.deployForTest(address(registry), address(accessManager)));
        vm.prank(scriptAdmin);
        IFactory(factory).setCurveAddressProvider(address(curveAddressProvider));
        bytes memory revertData = abi.encodeWithSelector(bytes4(keccak256("UnregisteredPT()")));
        vm.expectRevert(revertData);
        factory.deployCurvePool(
            address(0),
            IFactory.CurvePoolParams(0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
            0
        );
    }

    function testFactoryDeployCurvePoolWithExpiredPTFail() public {
        // Factory
        FactoryScript factoryScript = new FactoryScript();
        factory = Factory(factoryScript.deployForTest(address(registry), address(accessManager)));

        vm.prank(scriptAdmin);
        IFactory(factory).setCurveAddressProvider(address(curveAddressProvider));

        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.ADMIN_ROLE, address(factory), 0);
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.REGISTRY_ROLE, address(factory), 0);

        // deploy principalToken
        PrincipalTokenScript principalTokenScript = new PrincipalTokenScript();
        address principalTokenAddress = principalTokenScript.deployForTest(
            address(factory),
            address(ibt),
            DURATION
        );
        principalToken = PrincipalToken(principalTokenAddress);

        _increaseTimeToExpiry();

        bytes memory revertData = abi.encodeWithSelector(bytes4(keccak256("ExpiredPT()")));
        vm.expectRevert(revertData);
        factory.deployCurvePool(
            principalTokenAddress,
            IFactory.CurvePoolParams(0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
            0
        );
    }

    function testFactoryDeployAllWithoutInitialLiquidity() public {
        FactoryScript factoryScript = new FactoryScript();
        factory = Factory(factoryScript.deployForTest(address(registry), address(accessManager)));
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.ADMIN_ROLE, address(factory), 0);
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.REGISTRY_ROLE, address(factory), 0);

        IFactory.CurvePoolParams memory curvePoolParams = IFactory.CurvePoolParams({
            A: 200000000,
            gamma: 100000000000000,
            mid_fee: 5000000,
            out_fee: 45000000,
            allowed_extra_profit: 10000000000,
            fee_gamma: 5000000000000000,
            adjustment_step: 5500000000000,
            admin_fee: 5000000000,
            ma_half_time: 600,
            initial_price: 1e18
        });

        vm.prank(scriptAdmin);
        IFactory(factory).setCurveAddressProvider(address(curveAddressProvider));

        (address pt, address curvePool) = IFactory(factory).deployAll(
            address(ibt),
            DURATION,
            curvePoolParams,
            0
        );
        assertEq(IPrincipalToken(pt).underlying(), ibt.asset());
        assertEq(IPrincipalToken(pt).getDuration(), DURATION);
        assertEq(IPrincipalToken(pt).getIBT(), address(ibt));
        assertEq(IERC4626(ICurvePool(curvePool).token()).symbol(), "SPT-PT/IBT-f");
        assertEq(
            IERC4626(ICurvePool(curvePool).token()).name(),
            "Curve.fi Factory Crypto Pool: Spectra-PT/IBT"
        );

        assertEq(
            IPrincipalToken(pt).symbol(),
            NamingUtil.genPTSymbol(ibt.symbol(), IPrincipalToken(pt).maturity())
        );
        assertEq(
            IPrincipalToken(pt).name(),
            NamingUtil.genPTName(ibt.symbol(), IPrincipalToken(pt).maturity())
        );

        assertEq(ICurvePool(curvePool).A(), curvePoolParams.A);
        assertEq(ICurvePool(curvePool).gamma(), curvePoolParams.gamma);
        assertEq(ICurvePool(curvePool).mid_fee(), curvePoolParams.mid_fee);
        assertEq(ICurvePool(curvePool).out_fee(), curvePoolParams.out_fee);
        assertEq(
            ICurvePool(curvePool).allowed_extra_profit(),
            curvePoolParams.allowed_extra_profit
        );
        assertEq(ICurvePool(curvePool).fee_gamma(), curvePoolParams.fee_gamma);
        assertEq(ICurvePool(curvePool).adjustment_step(), curvePoolParams.adjustment_step);
        assertEq(ICurvePool(curvePool).admin_fee(), curvePoolParams.admin_fee);
        assertEq(ICurvePool(curvePool).ma_half_time(), curvePoolParams.ma_half_time);
    }

    function testFactoryDeployAllWithInitialLiquidityFuzz(
        uint256 amount,
        uint256 initialPrice,
        uint16 changeRate,
        bool increaseRate
    ) public {
        TestData memory data;
        amount = bound(amount, IBT_UNIT / 1000, 1_000_000_000_000_000 * IBT_UNIT);
        initialPrice = bound(initialPrice, 1e13, 1000000e18);
        int256 _changeRate = int256(bound(changeRate, 0, 10000));
        if (!increaseRate) {
            if (_changeRate > 99) {
                _changeRate = 99;
            }
        }
        _increaseRate(_changeRate);
        FactoryScript factoryScript = new FactoryScript();
        factory = Factory(factoryScript.deployForTest(address(registry), address(accessManager)));
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.ADMIN_ROLE, address(factory), 0);
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.REGISTRY_ROLE, address(factory), 0);

        IFactory.CurvePoolParams memory curvePoolParams = IFactory.CurvePoolParams({
            A: 200000000,
            gamma: 100000000000000,
            mid_fee: 5000000,
            out_fee: 45000000,
            allowed_extra_profit: 10000000000,
            fee_gamma: 5000000000000000,
            adjustment_step: 5500000000000,
            admin_fee: 5000000000,
            ma_half_time: 600,
            initial_price: initialPrice
        });

        data.initialLiquidityInIBT = amount;

        vm.prank(scriptAdmin);
        IFactory(factory).setCurveAddressProvider(address(curveAddressProvider));

        underlying.mint(MOCK_ADDR_1, 3 * ibt.convertToAssets(amount));
        vm.startPrank(MOCK_ADDR_1);
        underlying.approve(address(ibt), 3 * ibt.convertToAssets(amount));
        ibt.deposit(3 * ibt.convertToAssets(amount), MOCK_ADDR_1);
        vm.stopPrank();

        data.ibtBalanceBefore = IERC4626(ibt).balanceOf(MOCK_ADDR_1);

        // testing factory's deploy all
        vm.startPrank(MOCK_ADDR_1);
        ibt.approve(address(factory), amount);
        (address pt, address curvePool) = IFactory(factory).deployAll(
            address(ibt),
            DURATION,
            curvePoolParams,
            data.initialLiquidityInIBT
        );
        vm.stopPrank();

        data.ibtBalanceAfter1 = IERC4626(ibt).balanceOf(MOCK_ADDR_1);

        assertEq(IPrincipalToken(pt).underlying(), ibt.asset());
        assertEq(IPrincipalToken(pt).getDuration(), DURATION);
        assertEq(IPrincipalToken(pt).getIBT(), address(ibt));
        assertEq(IERC4626(ICurvePool(curvePool).token()).symbol(), "SPT-PT/IBT-f");
        assertEq(
            IERC4626(ICurvePool(curvePool).token()).name(),
            "Curve.fi Factory Crypto Pool: Spectra-PT/IBT"
        );

        assertEq(
            IPrincipalToken(pt).symbol(),
            NamingUtil.genPTSymbol(ibt.symbol(), IPrincipalToken(pt).maturity())
        );
        assertEq(
            IPrincipalToken(pt).name(),
            NamingUtil.genPTName(ibt.symbol(), IPrincipalToken(pt).maturity())
        );

        assertEq(ICurvePool(curvePool).A(), curvePoolParams.A);
        assertEq(ICurvePool(curvePool).gamma(), curvePoolParams.gamma);
        assertEq(ICurvePool(curvePool).mid_fee(), curvePoolParams.mid_fee);
        assertEq(ICurvePool(curvePool).out_fee(), curvePoolParams.out_fee);
        assertEq(
            ICurvePool(curvePool).allowed_extra_profit(),
            curvePoolParams.allowed_extra_profit
        );
        assertEq(ICurvePool(curvePool).fee_gamma(), curvePoolParams.fee_gamma);
        assertEq(ICurvePool(curvePool).adjustment_step(), curvePoolParams.adjustment_step);
        assertEq(ICurvePool(curvePool).admin_fee(), curvePoolParams.admin_fee);
        assertEq(ICurvePool(curvePool).ma_half_time(), curvePoolParams.ma_half_time);
        assertEq(ICurvePool(curvePool).coins(0), address(ibt), "Curve pool has wrong coin 0");
        assertEq(ICurvePool(curvePool).coins(1), pt, "Curve pool has wrong coin 1");
        if (initialPrice > 1e18) {
            assertApproxGeAbs(
                ICurvePool(curvePool).balances(0),
                ICurvePool(curvePool).balances(1),
                10
            );
        } else {
            assertApproxGeAbs(
                ICurvePool(curvePool).balances(1),
                ICurvePool(curvePool).balances(0),
                10
            );
        }
        data.ibtBalanceInPTFromInitPrice = IPrincipalToken(pt).previewDepositIBT(
            (IBT_UNIT).mulDiv(initialPrice, 1e18)
        );
        data.ptBalanceAdded = data.initialLiquidityInIBT.mulDiv(
            IBT_UNIT,
            IBT_UNIT + data.ibtBalanceInPTFromInitPrice
        ); // in IBT for now
        data.ibtBalanceAdded = data.initialLiquidityInIBT - data.ptBalanceAdded;
        data.ptBalanceAdded = IPrincipalToken(pt).previewDepositIBT(data.ptBalanceAdded);
        assertApproxEqAbs(
            ICurvePool(curvePool).balances(0),
            data.ibtBalanceAdded,
            100,
            "IBT balance of curve pool is wrong"
        );
        assertApproxEqAbs(
            ICurvePool(curvePool).balances(1),
            data.ptBalanceAdded,
            100,
            "PT balance of curve pool is wrong"
        );
        assertEq(
            data.ibtBalanceBefore,
            data.ibtBalanceAfter1 + data.initialLiquidityInIBT,
            "IBT balance of user is wrong"
        );

        // testing factory's deploy curve pool
        vm.startPrank(MOCK_ADDR_1);
        ibt.approve(address(factory), amount);
        address curvePool2 = IFactory(factory).deployCurvePool(
            pt,
            curvePoolParams,
            data.initialLiquidityInIBT
        );
        vm.stopPrank();

        data.ibtBalanceAfter2 = IERC4626(ibt).balanceOf(MOCK_ADDR_1);

        assertEq(IERC4626(ICurvePool(curvePool2).token()).symbol(), "SPT-PT/IBT-f");
        assertEq(
            IERC4626(ICurvePool(curvePool2).token()).name(),
            "Curve.fi Factory Crypto Pool: Spectra-PT/IBT"
        );
        assertEq(ICurvePool(curvePool2).A(), curvePoolParams.A);
        assertEq(ICurvePool(curvePool2).gamma(), curvePoolParams.gamma);
        assertEq(ICurvePool(curvePool2).mid_fee(), curvePoolParams.mid_fee);
        assertEq(ICurvePool(curvePool2).out_fee(), curvePoolParams.out_fee);
        assertEq(
            ICurvePool(curvePool2).allowed_extra_profit(),
            curvePoolParams.allowed_extra_profit
        );
        assertEq(ICurvePool(curvePool2).fee_gamma(), curvePoolParams.fee_gamma);
        assertEq(ICurvePool(curvePool2).adjustment_step(), curvePoolParams.adjustment_step);
        assertEq(ICurvePool(curvePool2).admin_fee(), curvePoolParams.admin_fee);
        assertEq(ICurvePool(curvePool2).ma_half_time(), curvePoolParams.ma_half_time);
        assertEq(ICurvePool(curvePool2).coins(0), address(ibt), "Curve pool has wrong coin 0");
        assertEq(ICurvePool(curvePool2).coins(1), pt, "Curve pool has wrong coin 1");
        if (initialPrice > 1e18) {
            assertApproxGeAbs(
                ICurvePool(curvePool2).balances(0),
                ICurvePool(curvePool2).balances(1),
                10
            );
        } else {
            assertApproxGeAbs(
                ICurvePool(curvePool2).balances(1),
                ICurvePool(curvePool2).balances(0),
                10
            );
        }
        data.ibtBalanceInPTFromInitPrice2 = IPrincipalToken(pt).previewDepositIBT(
            (IBT_UNIT).mulDiv(initialPrice, 1e18)
        );
        data.ptBalanceAdded2 = data.initialLiquidityInIBT.mulDiv(
            IBT_UNIT,
            IBT_UNIT + data.ibtBalanceInPTFromInitPrice2
        ); // in IBT for now
        data.ibtBalanceAdded2 = data.initialLiquidityInIBT - data.ptBalanceAdded2;
        data.ptBalanceAdded2 = IPrincipalToken(pt).previewDepositIBT(data.ptBalanceAdded2);
        assertApproxEqAbs(
            ICurvePool(curvePool2).balances(0),
            data.ibtBalanceAdded2,
            100,
            "IBT balance of curve pool is wrong"
        );
        assertApproxEqAbs(
            ICurvePool(curvePool2).balances(1),
            data.ptBalanceAdded2,
            100,
            "PT balance of curve pool is wrong"
        );
        assertEq(
            data.ibtBalanceAfter1,
            data.ibtBalanceAfter2 + data.initialLiquidityInIBT,
            "IBT balance of user is wrong"
        );
    }

    function testFactoryDeployAllFailBeaconNotSet() public {
        FactoryScript factoryScript = new FactoryScript();
        RegistryScript registryScript = new RegistryScript();
        // Setup a registry with beacon proxies not set
        Registry registry2 = Registry(
            registryScript.deployForTest(
                TOKENIZATION_FEE,
                YIELD_FEE,
                PT_FLASH_LOAN_FEE,
                feeCollector,
                address(accessManager)
            )
        );
        factory = Factory(factoryScript.deployForTest(address(registry2), address(accessManager)));
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.ADMIN_ROLE, address(factory), 0);
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.REGISTRY_ROLE, address(factory), 0);

        IFactory.CurvePoolParams memory curvePoolParams = IFactory.CurvePoolParams({
            A: 200000000,
            gamma: 100000000000000,
            mid_fee: 5000000,
            out_fee: 45000000,
            allowed_extra_profit: 10000000000,
            fee_gamma: 5000000000000000,
            adjustment_step: 5500000000000,
            admin_fee: 5000000000,
            ma_half_time: 600,
            initial_price: 1e18
        });

        vm.prank(scriptAdmin);
        IFactory(factory).setCurveAddressProvider(address(curveAddressProvider));

        bytes memory revertData = abi.encodeWithSelector(bytes4(keccak256("BeaconNotSet()")));

        vm.expectRevert(revertData);
        IFactory(factory).deployAll(address(ibt), DURATION, curvePoolParams, 0);
    }

    function _increaseTimeToExpiry() internal {
        uint256 time = block.timestamp + principalToken.maturity();
        vm.warp(time);
    }

    /**
     * @dev Internal function for changing ibt rate with a determined rate as passed
     */
    function _increaseRate(int256 rate) internal {
        int256 currentRate = int256(ibt.convertToAssets(10 ** ibt.decimals()));
        int256 newRate = (currentRate * (rate + 100)) / 100;
        ibt.setPricePerFullShare(uint256(newRate));
    }

    function assertApproxGeAbs(uint a, uint b, uint maxDelta) internal {
        if (!(a >= b)) {
            uint dt = b - a;
            if (dt > maxDelta) {
                emit log("Error: a >=~ b not satisfied [uint]");
                emit log_named_uint("   Value a", a);
                emit log_named_uint("   Value b", b);
                emit log_named_uint(" Max Delta", maxDelta);
                emit log_named_uint("     Delta", dt);
                fail();
            }
        }
    }
}
