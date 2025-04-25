// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

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
import "forge-std/Test.sol";
import {IFactorySNG} from "../../src/interfaces/IFactorySNG.sol";
import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IPrincipalToken} from "../../src/interfaces/IPrincipalToken.sol";
import {ICurveNGPool} from "../../src/interfaces/ICurveNGPool.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC4626} from "./mocks/MockERC4626.sol";

abstract contract BaseSpectraFeedSNGTest is Test {
    using SafeERC20 for IERC20;
    using Math for uint256;

    uint256 constant MIN_PT_DURATION = 1 weeks;
    uint256 constant MAX_PT_DURATION = 104 weeks;

    uint256 internal MIN_INITIAL_PRICE = 1e17;
    uint256 internal MAX_INITIAL_PRICE = 1e18;

    uint256 internal constant TOKENIZATION_FEE = 0;
    uint256 internal constant YIELD_FEE = 0;
    uint256 internal constant PT_FLASH_LOAN_FEE = 0;

    address internal constant curveFactoryAddress = 0x6A8cbed756804B16E05E741eDaBd5cB544AE21bf;
    // default account for deploying scripts contracts. refer to line 35 of
    // https://github.com/foundry-rs/foundry/blob/master/evm/src/lib.rs for more details
    address internal constant scriptAdmin = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
    address internal constant feeCollector = 0x0000000000000000000000000000000000000FEE;

    string internal network;
    uint256 internal forkBlockNumber;

    address internal _accessManager_;
    address internal _factorySNG_;
    address internal _raoRegistry_;
    address internal _registry_;
    address internal _underlying_;
    address internal _ibt_;
    address internal _pt_;
    address internal _rao_;
    address internal _ptInstance_;
    address internal _ytInstance_;
    address internal _raoInstance_;
    address internal _ptBeacon_;
    address internal _ytBeacon_;
    address internal _raoBeacon_;
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

        // deploy registry
        RegistryScript registryScript = new RegistryScript();
        _registry_ = registryScript.deployForTest(
            TOKENIZATION_FEE,
            YIELD_FEE,
            PT_FLASH_LOAN_FEE,
            feeCollector,
            _accessManager_
        );
        vm.prank(scriptAdmin);
        AccessManager(_accessManager_).grantRole(Roles.REGISTRY_ROLE, scriptAdmin, 0);
        vm.prank(scriptAdmin);
        AccessManager(_accessManager_).grantRole(Roles.FEE_SETTER_ROLE, scriptAdmin, 0);
        vm.prank(scriptAdmin);
        AccessManager(_accessManager_).grantRole(Roles.REGISTRY_ROLE, scriptAdmin, 0);
        vm.prank(scriptAdmin);
        AccessManager(_accessManager_).grantRole(Roles.UPGRADE_ROLE, scriptAdmin, 0);
        vm.prank(scriptAdmin);
        AccessManager(_accessManager_).grantRole(Roles.PAUSER_ROLE, scriptAdmin, 0);
        // setting tokenization fees to 0 (for convenience since they were added after all those tests)
        vm.prank(scriptAdmin);
        IRegistry(_registry_).setTokenizationFee(0);

        RateOracleRegistryScript rateOracleRegistryScript = new RateOracleRegistryScript();
        _raoRegistry_ = rateOracleRegistryScript.deployForTest(_accessManager_);

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

        // deploy rate adjustment oracle
        RateAdjustmentOracleInstanceScript raoScript = new RateAdjustmentOracleInstanceScript();
        _raoInstance_ = raoScript.deployForTest();
        RateAdjustmentOracleBeaconScript raoBeaconScript = new RateAdjustmentOracleBeaconScript();
        _raoBeacon_ = raoBeaconScript.deployForTest(_raoInstance_, _raoRegistry_, _accessManager_);

        // deploy factory
        FactorySNGScript factoryScript = new FactorySNGScript();
        _factorySNG_ = factoryScript.deployForTest(
            _registry_,
            _raoRegistry_,
            curveFactoryAddress,
            _accessManager_
        );

        vm.prank(scriptAdmin);
        AccessManager(_accessManager_).grantRole(Roles.ADMIN_ROLE, _factorySNG_, 0);
        vm.prank(scriptAdmin);
        AccessManager(_accessManager_).grantRole(Roles.REGISTRY_ROLE, _factorySNG_, 0);
    }

    function setUpVaultsAndPool(Init memory init) public virtual {
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
        init.initialLiquidityInIBT = bound(init.initialLiquidityInIBT, ibtUnit, ibtUnit * 1e15);

        init.initialPrice = bound(init.initialPrice, MIN_INITIAL_PRICE, MAX_INITIAL_PRICE);

        // TODO add some of these curve params to fuzzed Init struct
        uint256 initialPrice = init.initialPrice;
        IFactorySNG.CurvePoolParams memory curvePoolParams = IFactorySNG.CurvePoolParams({
            A: 300,
            fee: 1000000,
            fee_mul: 20000000000,
            ma_exp_time: 600,
            initial_price: initialPrice,
            rate_adjustment_oracle: address(0)
        });

        // get IBT for adding initial liquidity + some extra for later
        _deal_ibt(address(this), init.initialLiquidityInIBT + (1e16 * ibtUnit));
        _approve(_ibt_, address(this), _factorySNG_, init.initialLiquidityInIBT);

        (_pt_, _rao_, _curvePool_) = IFactorySNG(_factorySNG_).deployAll(
            _ibt_,
            init.ptDuration,
            curvePoolParams,
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
            init.yield = int(bound(uint256(init.yield), 0, 1e17));
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

    function test_getRoundDataAssetSNG_basic_fuzz(Init memory init, uint80 roundId) public virtual;

    function test_getRoundDataIBT_basic_fuzz(Init memory init, uint80 roundId) public virtual;

    function test_latestRoundDataAssetSNG_basic_fuzz(Init memory init) public virtual;

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

    function _rate_adjusted_price_oracle(
        address _curvePool
    ) internal view virtual returns (uint256) {
        uint256[] memory stored_rates = IStableSwapNG(_curvePool).stored_rates();
        return IStableSwapNG(_curvePool_).price_oracle(0).mulDiv(stored_rates[1], stored_rates[0]);
    }
}
