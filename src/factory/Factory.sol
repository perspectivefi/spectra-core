// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "openzeppelin-math/Math.sol";
import "../libraries/CurvePoolUtil.sol";
import "../interfaces/IFactory.sol";
import "../interfaces/ICurvePool.sol";
import "../interfaces/ICurveFactory.sol";
import "../interfaces/IPrincipalToken.sol";
import "../interfaces/IRegistry.sol";
import "../libraries/Roles.sol";
import "openzeppelin-contracts/access/manager/IAccessManager.sol";
import "openzeppelin-contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import "openzeppelin-contracts/proxy/beacon/BeaconProxy.sol";
import "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

contract Factory is IFactory, AccessManagedUpgradeable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    bytes4 constant PAUSE_SELECTOR = IPrincipalToken(address(0)).pause.selector;
    bytes4 constant UNPAUSE_SELECTOR = IPrincipalToken(address(0)).unPause.selector;
    bytes4 constant SET_REWARDS_PROXY_SELECTOR =
        IPrincipalToken(address(0)).setRewardsProxy.selector;
    bytes4 constant CLAIM_REWARDS_SELECTOR = IPrincipalToken(address(0)).claimRewards.selector;
    /* State
     *****************************************************************************************************************/

    address private registry;
    address private curveAddressProvider;
    address private curveFactory;

    /* Events
     *****************************************************************************************************************/

    event PTDeployed(address indexed pt, address indexed poolCreator);
    event CurvePoolDeployed(address indexed poolAddress, address indexed ibt, address indexed pt);
    event RegistryChange(address indexed previousRegistry, address indexed newRegistry);
    event CurveFactoryChange(address indexed previousFactory, address indexed newFactory);
    event CurveAddressProviderChange(
        address indexed previousCurveAddressProvider,
        address indexed newCurveAddressProvider
    );

    /**
     * @notice Constructor of the contract
     */
    constructor() {
        _disableInitializers(); // using this so that the deployed logic contract later cannot be initialized.
    }

    /**
     * @notice Initializer of the contract
     * @param _registry The address of the registry.
     * @param _initialAuthority The address of the access manager.
     */
    function initialize(address _registry, address _initialAuthority) external initializer {
        __AccessManaged_init(_initialAuthority);
        setRegistry(_registry);
    }

    /** @dev See {IFactory-deployPT}. */
    function deployPT(address _ibt, uint256 _duration) public override returns (address pt) {
        address ptBeacon = IRegistry(registry).getPTBeacon();
        if (ptBeacon == address(0)) {
            revert BeaconNotSet();
        }

        address accessManager = authority();
        bytes memory _data = abi.encodeWithSelector(
            IPrincipalToken(address(0)).initialize.selector,
            _ibt,
            _duration,
            accessManager
        );
        pt = address(new BeaconProxy(ptBeacon, _data));
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
    }

    /** @dev See {IFactory-deployCurvePool}. */
    function deployCurvePool(
        address _pt,
        CurvePoolParams calldata _curvePoolParams,
        uint256 _initialLiquidityInIBT
    ) public returns (address curvePool) {
        if (curveFactory == address(0)) {
            revert CurveFactoryNotSet();
        }
        if (!IRegistry(registry).isRegisteredPT(_pt)) {
            revert UnregisteredPT();
        }
        if (IPrincipalToken(_pt).maturity() < block.timestamp) {
            revert ExpiredPT();
        }
        address ibt = IPrincipalToken(_pt).getIBT();
        address[2] memory coins;
        {
            coins[0] = ibt;
            coins[1] = _pt;
        }
        curvePool = _deployCurvePool(coins, _curvePoolParams);
        emit CurvePoolDeployed(curvePool, ibt, _pt);

        if (_initialLiquidityInIBT != 0) {
            _addInitialLiquidity(curvePool, _initialLiquidityInIBT, _curvePoolParams.initial_price);
        }
    }

    /** @dev See {IFactory-deployAll}. */
    function deployAll(
        address _ibt,
        uint256 _duration,
        CurvePoolParams calldata _curvePoolParams,
        uint256 _initialLiquidityInIBT
    ) public returns (address pt, address curvePool) {
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

        // deploy Curve Pool
        if (curveFactory == address(0)) {
            revert CurveFactoryNotSet();
        }
        address[2] memory coins;
        {
            coins[0] = _ibt;
            coins[1] = pt;
        }
        curvePool = _deployCurvePool(coins, _curvePoolParams);
        emit CurvePoolDeployed(curvePool, _ibt, pt);

        if (_initialLiquidityInIBT != 0) {
            _addInitialLiquidity(curvePool, _initialLiquidityInIBT, _curvePoolParams.initial_price);
        }
    }

    /* GETTERS
     *****************************************************************************************************************/

    /** @dev See {IFactory-getRegistry}. */
    function getRegistry() external view override returns (address) {
        return registry;
    }

    /** @dev See {IFactory-getCurveAddressProvider}. */
    function getCurveAddressProvider() external view override returns (address) {
        return curveAddressProvider;
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

    /* SETTERS
     *****************************************************************************************************************/

    /** @dev See {IFactory-setCurveAddressProvider}. */
    function setCurveAddressProvider(address _curveAddressProvider) external override restricted {
        if (_curveAddressProvider == address(0)) {
            revert AddressError();
        }
        emit CurveAddressProviderChange(curveAddressProvider, _curveAddressProvider);
        curveAddressProvider = _curveAddressProvider;
        _setCurveFactory();
    }

    /** @dev See {IFactory-setRegistry}. */
    function setRegistry(address _newRegistry) public override restricted {
        if (_newRegistry == address(0)) {
            revert AddressError();
        }
        emit RegistryChange(registry, _newRegistry);
        registry = _newRegistry;
    }

    /**
     * @dev Splits the given IBT amount into IBT and PT based on pool initial price, and adds liquidity to the pool.
     * @param _curvePool The address of the Curve Pool in which the user adds initial liquidity to
     * @param _initialLiquidityInIBT The initial liquidity to seed the Curve Pool with (in IBT)
     * @param _initialPrice The initial price of the Curve Pool
     */
    function _addInitialLiquidity(
        address _curvePool,
        uint256 _initialLiquidityInIBT,
        uint256 _initialPrice
    ) internal {
        address ibt = ICurvePool(_curvePool).coins(0);
        address pt = ICurvePool(_curvePool).coins(1);

        IERC20(ibt).safeTransferFrom(msg.sender, address(this), _initialLiquidityInIBT);

        // using fictive pool balances, the user is adding liquidity in a ratio that (closely) matches the empty pool's initial price
        // with ptBalance = IBT_UNIT for having a fictive PT balance reference, ibtBalance = IBT_UNIT x initialPrice
        uint256 ptBalance = 10 ** IERC20Metadata(ibt).decimals();
        uint256 ibtBalance = ptBalance.mulDiv(_initialPrice, 10 ** CurvePoolUtil.CURVE_DECIMALS);
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
            IERC20(ibt).safeIncreaseAllowance(pt, type(uint256).max - allowancePT);
        }
        // PT amount to deposit in Curve Pool
        uint256 amount1;
        if (IPrincipalToken(pt).previewDepositIBT(ibtsToTokenize) != 0) {
            amount1 = IPrincipalToken(pt).depositIBT(ibtsToTokenize, address(this), msg.sender);
        }

        IERC20(ibt).safeIncreaseAllowance(_curvePool, amount0);
        IERC20(pt).safeIncreaseAllowance(_curvePool, amount1);
        ICurvePool(_curvePool).add_liquidity([amount0, amount1], 0, false, msg.sender);
    }

    /**
     * @dev Sets the curve factory address used for deploying the curve pool. Can only be called by owner.
     */
    function _setCurveFactory() internal {
        // keccack's first 4 bytes of getter get_address(uint256) of curveAddressProvider is 0x493f4f74
        // currently curve factory address is stored at index 6 on MAINNET.
        uint256 index = 6;
        (bool success, bytes memory responseData) = curveAddressProvider.call(
            abi.encodeWithSelector(0x493f4f74, index)
        );
        if (!(success)) {
            revert FailedToFetchCurveFactoryAddress();
        }
        address newCurveFactory = abi.decode(responseData, (address));
        emit CurveFactoryChange(curveFactory, newCurveFactory);
        curveFactory = newCurveFactory;
    }

    /**
     * @dev Calls the Curve factory and deploys a new Curve v2 crypto pool
     */
    function _deployCurvePool(
        address[2] memory _coins,
        CurvePoolParams calldata _p
    ) internal returns (address curvePoolAddr) {
        bytes memory name = bytes("Spectra-PT/IBT");
        bytes memory symbol = bytes("SPT-PT/IBT");
        bytes memory cd = new bytes(576); // calldata to the curve factory
        address coin0 = _coins[0];
        address coin1 = _coins[1];
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
        (bool success, bytes memory result) = address(curveFactory).call(cd);
        if (!success) {
            revert DeploymentFailed();
        }

        assembly {
            curvePoolAddr := mload(add(add(result, 12), 20))
        }
    }
}
