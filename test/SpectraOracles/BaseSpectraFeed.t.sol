// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "script/00_deployAccessManager.s.sol";
import "script/01_deployRegistry.s.sol";
import "script/02_deployPrincipalTokenInstance.s.sol";
import "script/03_deployYTInstance.s.sol";
import "script/04_deployPrincipalTokenBeacon.s.sol";
import "script/05_deployYTBeacon.s.sol";
import "script/06_deployFactory.s.sol";
import "forge-std/Test.sol";
import "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IPrincipalToken} from "../../src/interfaces/IPrincipalToken.sol";
import {ICurveNGPool} from "../../src/interfaces/ICurveNGPool.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC4626} from "./mocks/MockERC4626.sol";

abstract contract BaseSpectraFeedTest is Test {
    using SafeERC20 for IERC20;

    uint256 constant MIN_PT_DURATION = 1 weeks;
    uint256 constant MAX_PT_DURATION = 104 weeks;

    uint256 internal MIN_INITIAL_PRICE = 1e17;
    uint256 internal MAX_INITIAL_PRICE = 1e18;

    uint256 internal constant TOKENIZATION_FEE = 0;
    uint256 internal constant YIELD_FEE = 0;
    uint256 internal constant PT_FLASH_LOAN_FEE = 0;

    address internal constant curveFactoryAddress = 0x98EE851a00abeE0d95D08cF4CA2BdCE32aeaAF7F;
    address internal constant feeCollector = 0x0000000000000000000000000000000000000FEE;

    string internal network;
    uint256 internal forkBlockNumber;

    address internal _accessManager_;
    address internal _factory_;
    address internal _registry_;
    address internal _ptInstance_;
    address internal _ytInstance_;
    address internal _ptBeacon_;
    address internal _ytBeacon_;
    address internal _underlying_;
    address internal _ibt_;
    address internal _pt_;
    address internal _curvePool_;
    address internal _priceFeed_;
    address internal _priceFeedInAsset_;
    address internal _priceFeedInIBT_;

    uint256 internal underlyingUnit;
    uint256 internal ibtUnit;
    uint256 internal maturity;

    struct Init {
        uint8 underlyingDecimals;
        uint8 ibtDecimalsOffset;
        uint256 ptDuration;
        uint256 initialLiquidityInIBT;
        uint256 initialPrice;
        int yield;
    }

    function setUp() public virtual {
        address scriptAdmin = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
        string memory envVar = string.concat(network, "_RPC_URL");
        string memory rpcUrl = vm.envString(envVar);

        uint256 fork;
        if (forkBlockNumber != 0) {
            fork = vm.createFork(rpcUrl, forkBlockNumber);
        } else {
            fork = vm.createFork(rpcUrl);
        }
        vm.selectFork(fork);

        AccessManagerDeploymentScript accessManagerScript = new AccessManagerDeploymentScript();
        _accessManager_ = accessManagerScript.deployForTest(scriptAdmin);
        vm.prank(scriptAdmin);
        AccessManager(_accessManager_).grantRole(Roles.REGISTRY_ROLE, scriptAdmin, 0);
        vm.prank(scriptAdmin);
        AccessManager(_accessManager_).grantRole(Roles.FEE_SETTER_ROLE, scriptAdmin, 0);
        vm.prank(scriptAdmin);
        AccessManager(_accessManager_).grantRole(Roles.UPGRADE_ROLE, scriptAdmin, 0);
        vm.prank(scriptAdmin);
        AccessManager(_accessManager_).grantRole(Roles.PAUSER_ROLE, scriptAdmin, 0);

        RegistryScript registryScript = new RegistryScript();

        _registry_ = registryScript.deployForTest(
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE,
            feeCollector,
            _accessManager_
        );

        PrincipalTokenInstanceScript principalTokenInstanceScript = new PrincipalTokenInstanceScript();
        YTInstanceScript ytInstanceScript = new YTInstanceScript();
        _ptInstance_ = principalTokenInstanceScript.deployForTest(_registry_);
        _ytInstance_ = ytInstanceScript.deployForTest();
        PrincipalTokenBeaconScript principalTokenBeaconScript = new PrincipalTokenBeaconScript();
        YTBeaconScript ytBeaconScript = new YTBeaconScript();
        _ptBeacon_ = principalTokenBeaconScript.deployForTest(
            _ptInstance_,
            _registry_,
            _accessManager_
        );
        _ytBeacon_ = ytBeaconScript.deployForTest(_ytInstance_, _registry_, _accessManager_);

        // deploy factory
        FactoryScript factoryScript = new FactoryScript();
        _factory_ = factoryScript.deployForTest(_registry_, curveFactoryAddress, _accessManager_);
        vm.prank(scriptAdmin);
        AccessManager(_accessManager_).grantRole(Roles.ADMIN_ROLE, _factory_, 0);
        vm.prank(scriptAdmin);
        AccessManager(_accessManager_).grantRole(Roles.REGISTRY_ROLE, _factory_, 0);
    }

    function setUpVaultsAndPool(Init memory init) public virtual {
        address scriptAdmin = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
        init.underlyingDecimals = uint8(bound(init.underlyingDecimals, 6, 18));
        init.ibtDecimalsOffset = uint8(
            bound(init.ibtDecimalsOffset, 0, 18 - init.underlyingDecimals)
        );
        _underlying_ = address(new MockERC20(init.underlyingDecimals));
        _ibt_ = address(new MockERC4626(_underlying_, init.ibtDecimalsOffset));

        underlyingUnit = 10 ** IERC20Metadata(_underlying_).decimals();
        ibtUnit = 10 ** IERC20Metadata(_ibt_).decimals();

        init.ptDuration = bound(init.ptDuration, MIN_PT_DURATION, MAX_PT_DURATION);
        maturity = init.ptDuration + block.timestamp;
        init.initialLiquidityInIBT = bound(init.initialLiquidityInIBT, ibtUnit, ibtUnit * 100);

        init.initialPrice = bound(init.initialPrice, MIN_INITIAL_PRICE, MAX_INITIAL_PRICE);

        // TODO add some of these curve params to fuzzed Init struct
        IFactory.CurvePoolParams memory curvePoolDeploymentData;
        curvePoolDeploymentData.A = 2e7;
        curvePoolDeploymentData.gamma = 1e15;
        curvePoolDeploymentData.mid_fee = 5000000;
        curvePoolDeploymentData.out_fee = 45000000;
        curvePoolDeploymentData.fee_gamma = 5000000000000000;
        curvePoolDeploymentData.allowed_extra_profit = 10000000000;
        curvePoolDeploymentData.adjustment_step = 5500000000000;
        curvePoolDeploymentData.ma_exp_time = 1200;
        curvePoolDeploymentData.initial_price = init.initialPrice;

        // get IBT for adding initial liquidity + some extra for later
        _deal_ibt(address(this), init.initialLiquidityInIBT + (1e16 * ibtUnit));
        _approve(_ibt_, address(this), _factory_, init.initialLiquidityInIBT);

        (_pt_, _curvePool_) = IFactory(_factory_).deployAll(
            _ibt_,
            init.ptDuration,
            curvePoolDeploymentData,
            init.initialLiquidityInIBT,
            0
        );

        // get some PT
        _approve(_ibt_, address(this), _pt_, 1e8 * ibtUnit);
        IPrincipalToken(_pt_).depositIBT(1e8 * ibtUnit, address(this));
    }

    function setUpIBTYield(Init memory init) public virtual {
        uint256 vaultBalance = IERC20(_underlying_).balanceOf(_ibt_);
        if (init.yield >= 0) {
            // gain
            init.yield = int(bound(uint256(init.yield), 0, 1e18));
            deal({token: _underlying_, to: _ibt_, give: vaultBalance + uint256(init.yield)});
        } else {
            // loss
            vm.assume(init.yield > type(int).min); // avoid overflow in conversion
            uint256 loss = bound(uint256(-1 * init.yield), 0, vaultBalance);
            init.yield = -1 * int(loss);
            deal({token: _underlying_, to: _ibt_, give: vaultBalance - loss});
        }
    }

    function test_description() public virtual;

    function test_version() public virtual;

    function test_decimals_fuzz(uint8 _underlyingDecimals, uint8 _ibtDecimalsOffset) public virtual;

    function test_getRoundDataAsset_basic_fuzz(Init memory init, uint80 roundId) public virtual;

    function test_getRoundDataIBT_basic_fuzz(Init memory init, uint80 roundId) public virtual;

    function test_latestRoundDataAsset_basic_fuzz(Init memory init) public virtual;

    function test_latestRoundDataIBT_basic_fuzz(Init memory init) public virtual;

    function test_latestRoundData_fuzz(
        Init memory init,
        bool swapInputBool,
        uint256 swapInputAmount,
        uint8 swapIterations
    ) public virtual;

    function test_compare_grd_lrd_fuzz(Init memory init, uint80 roundId) public virtual;

    /* Utils
     *****************************************************************************************************************/

    function _approve(address token, address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        IERC20(token).forceApprove(spender, amount);
    }

    function _deal_ibt(address receiver, uint256 amount) internal virtual {
        uint256 assets = IERC4626(_ibt_).previewMint(amount);
        deal({token: _underlying_, to: address(this), give: assets, adjust: true});
        _approve(_underlying_, address(this), _ibt_, assets);
        IERC4626(_ibt_).mint(amount, receiver);
    }
}
