// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "openzeppelin-math/Math.sol";
import "openzeppelin-contracts/access/manager/IAccessManager.sol";
import "openzeppelin-contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import "openzeppelin-contracts/proxy/beacon/BeaconProxy.sol";
import "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IFactorySNG.sol";
import "../interfaces/IStableSwapNGFactory.sol";
import "../interfaces/IRateAdjustmentOracle.sol";
import "../interfaces/IPrincipalToken.sol";
import "../interfaces/IRegistry.sol";
import "../interfaces/IStableSwapNG.sol";
import "../interfaces/IRateOracleRegistry.sol";
import "../libraries/CurvePoolUtil.sol";
import "../libraries/Roles.sol";

/**
 * @title Factory SNG
 * @author Spectra Finance
 * @notice Factory used to deploy Spectra core with Curve Stable Swap NG integration.
 */
contract FactorySNG is IFactorySNG, AccessManagedUpgradeable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // Curve constants
    uint256 constant IMPLEMENTATION_ID = 0;
    uint8 constant PT_ASSET_TYPE = 1; // @dev: using an exchange rate oracle for PTs
    uint8 constant IBT_ASSET_TYPE = 3; // @dev: no exchange rate oracle for IBTs

    // hash of the first four bytes of the rate oracle exchange rate method
    bytes4 constant RATE_ADJUSTMENT_ORACLE_METHOD_SIG = bytes4(keccak256("value()"));

    // selectors
    bytes4 constant SET_INIT_PRICE_SELECTOR =
        IRateAdjustmentOracle(address(0)).setInitialPrice.selector;

    bytes4 constant PAUSE_SELECTOR = IPrincipalToken(address(0)).pause.selector;
    bytes4 constant UNPAUSE_SELECTOR = IPrincipalToken(address(0)).unPause.selector;
    bytes4 constant SET_REWARDS_PROXY_SELECTOR =
        IPrincipalToken(address(0)).setRewardsProxy.selector;
    bytes4 constant CLAIM_REWARDS_SELECTOR = IPrincipalToken(address(0)).claimRewards.selector;

    /* State
     *****************************************************************************************************************/

    /** @notice Factory of Curve protocol, used to deploy pools */
    address private curveFactory;
    /** @notice registry of the protocol */
    address private immutable registry;
    /** @notice rate oracle registry implementation*/
    address private immutable rateOracleRegistry;

    /* Events
     *****************************************************************************************************************/

    event PTDeployed(address indexed pt, address indexed poolCreator);
    event RateAdjustmentOracleDeployed(
        address indexed rateAdjustmentOracle,
        address indexed poolCreator
    );
    event CurvePoolDeployed(address indexed poolAddress, address indexed ibt, address indexed pt);
    event RegistryChange(address indexed previousRegistry, address indexed newRegistry);
    event CurveFactoryChange(address indexed previousFactory, address indexed newFactory);

    /**
     * @notice Constructor of the contract. Separate registry used for Spectra core contracts and rate
     * oracle contracts.
     * @param _registry The address of the registry.
     * @param _rateOracleRegistry The address of the registry.
     */
    constructor(address _registry, address _rateOracleRegistry) {
        if (_registry == address(0) || _rateOracleRegistry == address(0)) {
            revert AddressError();
        }
        registry = _registry;
        rateOracleRegistry = _rateOracleRegistry;
        _disableInitializers(); // using this so that the deployed logic contract later cannot be initialized.
    }

    /**
     * @notice Initializer of the contract
     * @param _initialAuthority The address of the access manager.
     */
    function initialize(address _initialAuthority, address _curveFactory) external initializer {
        __AccessManaged_init(_initialAuthority);
        _setCurveFactory(_curveFactory);
    }

    /** @dev See {IFactory-deployAll}. */
    function deployAll(
        address _ibt,
        uint256 _duration,
        CurvePoolParams memory _curvePoolParams,
        uint256 _initialLiquidityInIBT,
        uint256 _minPTShares
    ) public returns (address pt, address rateAdjustmentOracle, address curvePool) {
        // deploy PT
        address ptBeacon = IRegistry(registry).getPTBeacon();
        if (ptBeacon == address(0)) {
            revert BeaconNotSet();
        }
        address accessManager = authority();
        bytes memory _encodedData = abi.encodeWithSelector(
            IPrincipalToken(address(0)).initialize.selector,
            _ibt,
            _duration,
            accessManager
        );

        pt = address(new BeaconProxy(ptBeacon, _encodedData));
        emit PTDeployed(pt, msg.sender);
        IRegistry(registry).addPT(pt);
        IAccessManager(accessManager).setTargetFunctionRole(pt, getPauserSigs(), Roles.PAUSER_ROLE);
        IAccessManager(accessManager).setTargetFunctionRole(
            pt,
            getClaimRewardsProxySelectors(),
            Roles.REWARDS_HARVESTER_ROLE
        );

        IAccessManager(accessManager).setTargetFunctionRole(
            pt,
            getSetRewardsProxySelectors(),
            Roles.REWARDS_PROXY_SETTER_ROLE
        );

        // Deploy the rate oracle
        address rateOracleBeacon = IRateOracleRegistry(rateOracleRegistry).getRateOracleBeacon();
        if (rateOracleBeacon == address(0)) {
            revert BeaconNotSet();
        }

        _encodedData = abi.encodeWithSelector(
            IRateAdjustmentOracle(address(0)).initialize.selector,
            accessManager
        );

        rateAdjustmentOracle = address(new BeaconProxy(rateOracleBeacon, _encodedData));
        emit RateAdjustmentOracleDeployed(rateAdjustmentOracle, msg.sender);
        IRateOracleRegistry(rateOracleRegistry).addRateOracle(pt, rateAdjustmentOracle);
        IAccessManager(accessManager).setTargetFunctionRole(
            rateAdjustmentOracle,
            getSetRateOracleInitialPriceSelectors(),
            Roles.RATE_ADJUSTMENT_ORACLE_SETTER_ROLE
        );

        // deploy Curve Pool
        address[] memory coins = new address[](2);
        coins[0] = _ibt;
        coins[1] = pt;

        _curvePoolParams.rate_adjustment_oracle = rateAdjustmentOracle;

        curvePool = _deployCurvePool(coins, _curvePoolParams);
        emit CurvePoolDeployed(curvePool, _ibt, pt);

        // initialise rate adjutment oracle

        IRateAdjustmentOracle(rateAdjustmentOracle).post_initialize(
            block.timestamp,
            IPrincipalToken(pt).maturity(),
            _curvePoolParams.initial_price,
            curvePool
        );

        if (_initialLiquidityInIBT != 0) {
            _addInitialLiquidity(
                curvePool,
                _initialLiquidityInIBT,
                _minPTShares,
                _curvePoolParams.initial_price
            );
        }
    }

    /* GETTERS
     *****************************************************************************************************************/

    /** @dev See {IFactory-getRegistry}. */
    function getRegistry() external view override returns (address) {
        return registry;
    }

    /** @dev See {IFactory-getRateOracleRegistry}. */
    function getRateOracleRegistry() external view override returns (address) {
        return rateOracleRegistry;
    }

    /** @dev See {IFactory-getCurveFactory}. */
    function getCurveFactory() external view override returns (address) {
        return curveFactory;
    }

    /**
     * @notice Getter for pause and unpause selectors, used for access management
     */
    function getPauserSigs() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = PAUSE_SELECTOR;
        selectors[1] = UNPAUSE_SELECTOR;
        return selectors;
    }

    /**
     * @notice Getter for the reward proxy setter selector, used for access management
     */
    function getSetRewardsProxySelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = SET_REWARDS_PROXY_SELECTOR;
        return selectors;
    }

    /**
     * @notice Getter for the claim rewards selector, used for access management
     */
    function getClaimRewardsProxySelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = CLAIM_REWARDS_SELECTOR;
        return selectors;
    }

    /**
     * @notice Getter for the set initial price selector in the rate adjustment oracle, used for access management
     */
    function getSetRateOracleInitialPriceSelectors() internal pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = SET_INIT_PRICE_SELECTOR;
        return selectors;
    }

    /* SETTERS
     *****************************************************************************************************************/

    /** @dev See {IFactory-setCurveFactory}. */
    function setCurveFactory(address _curveFactory) public override restricted {
        _setCurveFactory(_curveFactory);
    }

    /**
     * @dev Splits the given IBT amount into IBT and PT based on pool initial price, and adds liquidity to the pool.
     * @param _curvePool The address of the Curve Pool in which the user adds initial liquidity to
     * @param _initialLiquidityInIBT The initial liquidity to seed the Curve Pool with (in IBT)
     * @param _minPTShares The minimum allowed shares from deposit in PT
     * @param _initialPrice The initial price of the Curve Pool
     */
    function _addInitialLiquidity(
        address _curvePool,
        uint256 _initialLiquidityInIBT,
        uint256 _minPTShares,
        uint256 _initialPrice
    ) internal {
        address ibt = IStableSwapNG(_curvePool).coins(0);
        address pt = IStableSwapNG(_curvePool).coins(1);

        {
            // support for fee-on-transfer tokens
            uint256 balBefore = IERC20(ibt).balanceOf(address(this));
            IERC20(ibt).safeTransferFrom(msg.sender, address(this), _initialLiquidityInIBT);
            _initialLiquidityInIBT = IERC20(ibt).balanceOf(address(this)) - balBefore;
        }

        // using fictive pool balances, the user is adding liquidity in a ratio that (closely) matches the empty pool's initial price
        // with ptBalance = IBT_UNIT for having a fictive PT balance reference, ibtBalance = IBT_UNIT x initialPrice
        uint256 ptBalance = 10 ** IERC20Metadata(ibt).decimals();
        uint256 ibtBalance = ptBalance.mulDiv(_initialPrice, CurvePoolUtil.CURVE_UNIT);
        // compute the worth of the fictive IBT balance in the pool in PT
        uint256 ibtBalanceInPT = IPrincipalToken(pt).previewDepositIBT(ibtBalance);
        // compute the portion of IBT to deposit in PT
        uint256 ibtsToTokenize = _initialLiquidityInIBT.mulDiv(
            ptBalance,
            ibtBalanceInPT + ptBalance
        );

        // IBT amount to deposit in the Curve Pool
        uint256 amount0 = _initialLiquidityInIBT - ibtsToTokenize;
        uint256 allowancePT = IERC20(ibt).allowance(address(this), pt);

        if (allowancePT < ibtsToTokenize) {
            IERC20(ibt).forceApprove(pt, type(uint256).max);
        }

        // PT amount to deposit in Curve Pool
        uint256 amount1 = IPrincipalToken(pt).depositIBT(
            ibtsToTokenize,
            address(this),
            msg.sender,
            _minPTShares
        );

        IERC20(ibt).safeIncreaseAllowance(_curvePool, amount0);
        IERC20(pt).safeIncreaseAllowance(_curvePool, amount1);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount0;
        amounts[1] = amount1;
        IStableSwapNG(_curvePool).add_liquidity(amounts, 0, msg.sender);
    }

    /**
     * @dev Calls the Curve factory and deploys a new Curve v2 crypto pool
     */
    function _deployCurvePool(
        address[] memory _coins,
        CurvePoolParams memory _p
    ) internal returns (address curvePoolAddr) {
        if (curveFactory == address(0)) {
            revert CurveFactoryNotSet();
        }

        uint8[] memory assetTypes = new uint8[](2);
        assetTypes[0] = IBT_ASSET_TYPE;
        assetTypes[1] = PT_ASSET_TYPE;

        bytes4[] memory oracleMethodSigs = new bytes4[](2);
        oracleMethodSigs[0] = bytes4(0x0);
        oracleMethodSigs[1] = RATE_ADJUSTMENT_ORACLE_METHOD_SIG;

        address[] memory oracleAddresses = new address[](2);
        oracleAddresses[0] = address(0);
        oracleAddresses[1] = _p.rate_adjustment_oracle;

        curvePoolAddr = IStableSwapNGFactory(curveFactory).deploy_plain_pool(
            "Spectra-PT/IBT",
            "SPT-PT/IBT",
            _coins,
            _p.A,
            _p.fee,
            _p.fee_mul,
            _p.ma_exp_time,
            IMPLEMENTATION_ID,
            assetTypes,
            oracleMethodSigs,
            oracleAddresses
        );
    }

    function _setCurveFactory(address _curveFactory) internal {
        if (_curveFactory == address(0)) {
            revert AddressError();
        }
        emit CurveFactoryChange(curveFactory, _curveFactory);
        curveFactory = _curveFactory;
    }
}
