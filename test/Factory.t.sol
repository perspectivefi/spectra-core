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
import "../src/libraries/RayMath.sol";
import "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";

contract ContractFactory is Test {
    using Math for uint256;
    using RayMath for uint256;

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
        uint256 minPTShares;
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
    address public curveFactoryAddress;
    address public curvePoolAddr;
    IERC20Metadata public lpToken;
    address feeCollector = 0x0000000000000000000000000000000000000FEE;
    address MOCK_ADDR_1 = 0x0000000000000000000000000000000000000001;
    uint256 public TOKENIZATION_FEE = 1e15;
    uint256 public YIELD_FEE = 0;
    uint256 public PT_FLASH_LOAN_FEE = 0;
    uint256 constant FEE_DIVISOR = 1e18;
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    uint256 fork;
    YieldToken public yt;
    UpgradeableBeacon public principalTokenBeacon;
    UpgradeableBeacon public ytBeacon;

    // Events
    event PTDeployed(address indexed principalToken, address indexed poolCreator);
    event CurvePoolDeployed(address indexed poolAddress, address indexed ibt, address indexed pt);
    event CurveFactoryChange(address indexed previousFactory, address indexed newFactory);

    error FailedToAddInitialLiquidity();

    /**
     * @dev This function is called before each test.
     */
    function setUp() public {
        fork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(fork);
        curveFactoryAddress = 0x98EE851a00abeE0d95D08cF4CA2BdCE32aeaAF7F;
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

    function testDeployFactoryFailWhenRegistryIsZero() public {
        // Factory
        bytes memory revertData = abi.encodeWithSelector(bytes4(keccak256("AddressError()")));
        vm.expectRevert(revertData);
        new Factory(address(0));
    }

    function testDeployFactoryFailWhenCurveAddressIsZero() public {
        // Factory
        FactoryScript factoryScript = new FactoryScript();
        bytes memory revertData = abi.encodeWithSelector(bytes4(keccak256("AddressError()")));
        new Factory(address(registry));
        vm.expectRevert(revertData);
        factory = Factory(
            factoryScript.deployForTest(address(registry), address(0), address(accessManager))
        );
    }

    function testDeployPrincipalToken() public {
        // Factory
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

    function testSetCurveFactory() public {
        // Factory
        FactoryScript factoryScript = new FactoryScript();
        factory = Factory(
            factoryScript.deployForTest(
                address(registry),
                curveFactoryAddress,
                address(accessManager)
            )
        );

        vm.expectEmit(true, true, false, false);
        emit CurveFactoryChange(curveFactoryAddress, address(0xfac));
        vm.prank(scriptAdmin);
        factory.setCurveFactory(address(0xfac));
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
        factory = Factory(
            factoryScript.deployForTest(
                address(registry2),
                curveFactoryAddress,
                address(accessManager)
            )
        );
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.ADMIN_ROLE, address(factory), 0);
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.REGISTRY_ROLE, address(factory), 0);
        bytes memory revertData = abi.encodeWithSignature("BeaconNotSet()");
        vm.expectRevert(revertData);
        factory.deployPT(address(ibt), DURATION);
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
        factory = Factory(
            factoryScript.deployForTest(
                address(registry2),
                curveFactoryAddress,
                address(accessManager)
            )
        );
        vm.prank(scriptAdmin);
        bytes memory revertData = abi.encodeWithSelector(bytes4(keccak256("BeaconNotSet()")));
        vm.expectRevert(revertData);
        factory.deployPT(address(ibt), DURATION);
    }

    function testFactoryDeployCurvePoolWithUnregisteredPTFail() public {
        // Factory
        FactoryScript factoryScript = new FactoryScript();
        factory = Factory(
            factoryScript.deployForTest(
                address(registry),
                curveFactoryAddress,
                address(accessManager)
            )
        );
        bytes memory revertData = abi.encodeWithSelector(bytes4(keccak256("UnregisteredPT()")));
        vm.expectRevert(revertData);
        factory.deployCurvePool(
            address(0),
            IFactory.CurvePoolParams(0, 0, 0, 0, 0, 0, 0, 0, 0),
            0,
            0
        );
    }

    function testFactoryDeployCurvePoolWithExpiredPTFail() public {
        // Factory
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
            IFactory.CurvePoolParams(0, 0, 0, 0, 0, 0, 0, 0, 0),
            0,
            0
        );
    }

    function testFactoryDeployCurvePoolWithTooBigMinPTSharesFail() public {
        TestData memory data;

        // Factory
        FactoryScript factoryScript = new FactoryScript();
        factory = Factory(
            factoryScript.deployForTest(
                address(registry),
                curveFactoryAddress,
                address(accessManager)
            )
        );

        vm.startPrank(scriptAdmin);
        accessManager.grantRole(Roles.ADMIN_ROLE, address(factory), 0);
        accessManager.grantRole(Roles.REGISTRY_ROLE, address(factory), 0);
        vm.stopPrank();

        // deploy principalToken
        PrincipalTokenScript principalTokenScript = new PrincipalTokenScript();
        address principalTokenAddress = principalTokenScript.deployForTest(
            address(factory),
            address(ibt),
            DURATION
        );
        principalToken = PrincipalToken(principalTokenAddress);

        uint256 initialPrice = 8e17;

        IFactory.CurvePoolParams memory curvePoolParams = IFactory.CurvePoolParams({
            A: 20000000,
            gamma: 100000000000000,
            mid_fee: 5000000,
            out_fee: 45000000,
            fee_gamma: 5000000000000000,
            allowed_extra_profit: 10000000000,
            adjustment_step: 5500000000000,
            ma_exp_time: 1200,
            initial_price: initialPrice
        });

        data.initialLiquidityInIBT = 100 * IBT_UNIT;

        // compute minPTShares for given initialLiquidityInIBT
        {
            // fictive balances of pool to be deployed
            uint256 poolPTBalance = 10 ** IERC20Metadata(ibt).decimals();
            uint256 poolIBTBalance = poolPTBalance.mulDiv(initialPrice, CurvePoolUtil.CURVE_UNIT);
            // compute the worth of the fictive IBT balance in the pool in PT
            uint256 poolIBTBalanceInPT = principalToken.previewDepositIBT(poolIBTBalance);

            // compute the portion of IBT to deposit in PT
            uint256 ibtsToTokenize = data.initialLiquidityInIBT.mulDiv(
                poolPTBalance,
                poolIBTBalanceInPT + poolPTBalance
            );

            data.minPTShares = principalToken.previewDepositIBT(ibtsToTokenize);
        }

        // mint IBT to user
        underlying.mint(MOCK_ADDR_1, ibt.convertToAssets(100 * IBT_UNIT));
        vm.startPrank(MOCK_ADDR_1);
        underlying.approve(address(ibt), ibt.convertToAssets(100 * IBT_UNIT));
        ibt.mint(data.initialLiquidityInIBT, MOCK_ADDR_1);
        ibt.approve(address(factory), data.initialLiquidityInIBT);

        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("ERC5143SlippageProtectionFailed()"))
        );
        vm.expectRevert(revertData);
        // deployment + addLiquidity should revert with minPTShares too big
        IFactory(factory).deployCurvePool(
            address(principalToken),
            curvePoolParams,
            data.initialLiquidityInIBT,
            data.minPTShares + 1
        );

        // deployment + addLiquidity should not revert
        IFactory(factory).deployCurvePool(
            address(principalToken),
            curvePoolParams,
            data.initialLiquidityInIBT,
            data.minPTShares
        );

        vm.stopPrank();
    }

    function testFactoryDeployAllWithoutInitialLiquidity() public {
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

        IFactory.CurvePoolParams memory curvePoolParams = IFactory.CurvePoolParams({
            A: 20000000,
            gamma: 100000000000000,
            mid_fee: 5000000,
            out_fee: 45000000,
            fee_gamma: 5000000000000000,
            allowed_extra_profit: 10000000000,
            adjustment_step: 5500000000000,
            ma_exp_time: 1200,
            initial_price: 1e18
        });

        (address pt, address curvePool) = IFactory(factory).deployAll(
            address(ibt),
            DURATION,
            curvePoolParams,
            0,
            0
        );
        assertEq(IPrincipalToken(pt).underlying(), ibt.asset());
        assertEq(IPrincipalToken(pt).getDuration(), DURATION);
        assertEq(IPrincipalToken(pt).getIBT(), address(ibt));
        assertEq(ICurveNGPool(curvePool).symbol(), "SPT-PT/IBT");
        assertEq(ICurveNGPool(curvePool).name(), "Spectra-PT/IBT");

        assertEq(
            IPrincipalToken(pt).symbol(),
            NamingUtil.genPTSymbol(ibt.symbol(), IPrincipalToken(pt).maturity())
        );
        assertEq(
            IPrincipalToken(pt).name(),
            NamingUtil.genPTName(ibt.symbol(), IPrincipalToken(pt).maturity())
        );

        assertEq(ICurveNGPool(curvePool).A(), curvePoolParams.A);
        assertEq(ICurveNGPool(curvePool).gamma(), curvePoolParams.gamma);
        assertEq(ICurveNGPool(curvePool).mid_fee(), curvePoolParams.mid_fee);
        assertEq(ICurveNGPool(curvePool).out_fee(), curvePoolParams.out_fee);
        assertEq(ICurveNGPool(curvePool).fee_gamma(), curvePoolParams.fee_gamma);
        assertEq(
            ICurveNGPool(curvePool).allowed_extra_profit(),
            curvePoolParams.allowed_extra_profit
        );
        assertEq(ICurveNGPool(curvePool).adjustment_step(), curvePoolParams.adjustment_step);
        assertEq(ICurveNGPool(curvePool).ma_time(), (curvePoolParams.ma_exp_time * 694) / 1000); // To get time in seconds, the parameter is multipled by ln(2)
    }

    function testFactoryDeployAllWithInitialLiquidityFuzz(
        uint256 amount,
        uint256 initialPrice,
        uint16 changeRate,
        bool increaseRate
    ) public {
        TestData memory data;
        amount = bound(amount, IBT_UNIT / 1000, 1_000_000_000_000_000 * IBT_UNIT);
        initialPrice = bound(initialPrice, 1e15, 1e20);
        int256 _changeRate = int256(bound(changeRate, 0, 10000));
        if (!increaseRate) {
            if (_changeRate > 99) {
                _changeRate = 99;
            }
        }
        _increaseRate(_changeRate);
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

        IFactory.CurvePoolParams memory curvePoolParams = IFactory.CurvePoolParams({
            A: 20000000,
            gamma: 100000000000000,
            mid_fee: 5000000,
            out_fee: 45000000,
            fee_gamma: 5000000000000000,
            allowed_extra_profit: 10000000000,
            adjustment_step: 5500000000000,
            ma_exp_time: 1200,
            initial_price: initialPrice
        });

        data.initialLiquidityInIBT = amount;

        {
            uint256 poolPTBalance = 10 ** IERC20Metadata(ibt).decimals();
            uint256 poolIBTBalance = poolPTBalance.mulDiv(initialPrice, CurvePoolUtil.CURVE_UNIT);
            uint256 currentIBTRate = ibt.previewRedeem(IBT_UNIT).toRay(underlying.decimals());

            // convert the worth of the fictive IBT balance in the pool to (not yet deployed) PT
            poolIBTBalance -= poolIBTBalance.mulDiv(
                TOKENIZATION_FEE,
                FEE_DIVISOR,
                Math.Rounding.Ceil
            );
            uint256 poolIBTBalanceInPT = poolIBTBalance.mulDiv(currentIBTRate, RayMath.RAY_UNIT);

            // compute the portion of IBT to deposit in PT
            uint256 ibtsToTokenize = data.initialLiquidityInIBT.mulDiv(
                poolPTBalance,
                poolIBTBalanceInPT + poolPTBalance
            );

            // convert the portion of IBT to (not yet deployed) PT
            ibtsToTokenize -= ibtsToTokenize.mulDiv(
                TOKENIZATION_FEE,
                FEE_DIVISOR,
                Math.Rounding.Ceil
            );
            data.minPTShares = ibtsToTokenize.mulDiv(currentIBTRate, RayMath.RAY_UNIT);
        }

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
            data.initialLiquidityInIBT,
            data.minPTShares
        );
        vm.stopPrank();

        data.ibtBalanceAfter1 = IERC4626(ibt).balanceOf(MOCK_ADDR_1);

        assertEq(IPrincipalToken(pt).underlying(), ibt.asset());
        assertEq(IPrincipalToken(pt).getDuration(), DURATION);
        assertEq(IPrincipalToken(pt).getIBT(), address(ibt));
        assertEq(ICurveNGPool(curvePool).symbol(), "SPT-PT/IBT");
        assertEq(ICurveNGPool(curvePool).name(), "Spectra-PT/IBT");

        assertEq(
            IPrincipalToken(pt).symbol(),
            NamingUtil.genPTSymbol(ibt.symbol(), IPrincipalToken(pt).maturity())
        );
        assertEq(
            IPrincipalToken(pt).name(),
            NamingUtil.genPTName(ibt.symbol(), IPrincipalToken(pt).maturity())
        );

        assertEq(ICurveNGPool(curvePool).A(), curvePoolParams.A);
        assertEq(ICurveNGPool(curvePool).gamma(), curvePoolParams.gamma);
        assertEq(ICurveNGPool(curvePool).mid_fee(), curvePoolParams.mid_fee);
        assertEq(ICurveNGPool(curvePool).out_fee(), curvePoolParams.out_fee);
        assertEq(ICurveNGPool(curvePool).fee_gamma(), curvePoolParams.fee_gamma);
        assertEq(
            ICurveNGPool(curvePool).allowed_extra_profit(),
            curvePoolParams.allowed_extra_profit
        );
        assertEq(ICurveNGPool(curvePool).adjustment_step(), curvePoolParams.adjustment_step);
        assertEq(ICurveNGPool(curvePool).ma_time(), (curvePoolParams.ma_exp_time * 694) / 1000); // To get time in seconds, the parameter is multipled by ln(2)
        assertEq(ICurveNGPool(curvePool).coins(0), address(ibt), "Curve pool has wrong coin 0");
        assertEq(ICurveNGPool(curvePool).coins(1), pt, "Curve pool has wrong coin 1");
        if (initialPrice > 1e18) {
            assertApproxGeAbs(
                ICurveNGPool(curvePool).balances(0),
                ICurveNGPool(curvePool).balances(1),
                10
            );
        } else {
            assertApproxGeAbs(
                ICurveNGPool(curvePool).balances(1),
                ICurveNGPool(curvePool).balances(0),
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
            ICurveNGPool(curvePool).balances(0),
            data.ibtBalanceAdded,
            100,
            "IBT balance of curve pool is wrong"
        );
        assertApproxEqAbs(
            ICurveNGPool(curvePool).balances(1),
            data.ptBalanceAdded,
            100,
            "PT balance of curve pool is wrong"
        );
        assertEq(
            data.ibtBalanceBefore,
            data.ibtBalanceAfter1 + data.initialLiquidityInIBT,
            "IBT balance of user is wrong"
        );

        {
            uint256 poolPTBalance = 10 ** IERC20Metadata(ibt).decimals();
            uint256 poolIBTBalance = poolPTBalance.mulDiv(initialPrice, CurvePoolUtil.CURVE_UNIT);
            // convert the worth of the fictive IBT balance in the pool to PT
            uint256 poolIBTBalanceInPT = IPrincipalToken(pt).previewDepositIBT(poolIBTBalance);

            // compute the portion of IBT to deposit in PT
            uint256 ibtsToTokenize = data.initialLiquidityInIBT.mulDiv(
                poolPTBalance,
                poolIBTBalanceInPT + poolPTBalance
            );

            data.minPTShares = IPrincipalToken(pt).previewDepositIBT(ibtsToTokenize);
        }

        // testing factory's deploy curve pool
        vm.startPrank(MOCK_ADDR_1);
        ibt.approve(address(factory), amount);
        address curvePool2 = IFactory(factory).deployCurvePool(
            pt,
            curvePoolParams,
            data.initialLiquidityInIBT,
            data.minPTShares
        );
        vm.stopPrank();

        data.ibtBalanceAfter2 = IERC4626(ibt).balanceOf(MOCK_ADDR_1);

        assertEq(ICurveNGPool(curvePool2).symbol(), "SPT-PT/IBT");
        assertEq(ICurveNGPool(curvePool2).name(), "Spectra-PT/IBT");
        assertEq(ICurveNGPool(curvePool2).A(), curvePoolParams.A);
        assertEq(ICurveNGPool(curvePool2).gamma(), curvePoolParams.gamma);
        assertEq(ICurveNGPool(curvePool2).mid_fee(), curvePoolParams.mid_fee);
        assertEq(ICurveNGPool(curvePool2).out_fee(), curvePoolParams.out_fee);
        assertEq(ICurveNGPool(curvePool2).fee_gamma(), curvePoolParams.fee_gamma);
        assertEq(
            ICurveNGPool(curvePool2).allowed_extra_profit(),
            curvePoolParams.allowed_extra_profit
        );
        assertEq(ICurveNGPool(curvePool2).adjustment_step(), curvePoolParams.adjustment_step);
        assertEq(ICurveNGPool(curvePool2).ma_time(), (curvePoolParams.ma_exp_time * 694) / 1000); // To get time in seconds, the parameter is multipled by ln(2)
        assertEq(ICurveNGPool(curvePool2).coins(0), address(ibt), "Curve pool has wrong coin 0");
        assertEq(ICurveNGPool(curvePool2).coins(1), pt, "Curve pool has wrong coin 1");
        if (initialPrice > 1e18) {
            assertApproxGeAbs(
                ICurveNGPool(curvePool2).balances(0),
                ICurveNGPool(curvePool2).balances(1),
                10
            );
        } else {
            assertApproxGeAbs(
                ICurveNGPool(curvePool2).balances(1),
                ICurveNGPool(curvePool2).balances(0),
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
            ICurveNGPool(curvePool2).balances(0),
            data.ibtBalanceAdded2,
            100,
            "IBT balance of curve pool is wrong"
        );
        assertApproxEqAbs(
            ICurveNGPool(curvePool2).balances(1),
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
        factory = Factory(
            factoryScript.deployForTest(
                address(registry2),
                curveFactoryAddress,
                address(accessManager)
            )
        );
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.ADMIN_ROLE, address(factory), 0);
        vm.prank(scriptAdmin);
        accessManager.grantRole(Roles.REGISTRY_ROLE, address(factory), 0);

        IFactory.CurvePoolParams memory curvePoolParams = IFactory.CurvePoolParams({
            A: 20000000,
            gamma: 100000000000000,
            mid_fee: 5000000,
            out_fee: 45000000,
            fee_gamma: 5000000000000000,
            allowed_extra_profit: 10000000000,
            adjustment_step: 5500000000000,
            ma_exp_time: 1200,
            initial_price: 1e18
        });

        bytes memory revertData = abi.encodeWithSelector(bytes4(keccak256("BeaconNotSet()")));

        vm.expectRevert(revertData);
        IFactory(factory).deployAll(address(ibt), DURATION, curvePoolParams, 0, 0);
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
