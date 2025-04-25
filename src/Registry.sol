// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "openzeppelin-utils/structs/EnumerableSet.sol";
import "openzeppelin-contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import "./interfaces/IRegistry.sol";

/**
 * @title Registry Contract
 * @author Spectra Finance
 * @notice Keeps a record of all valid contract addresses currently used in the protocol.
 */
contract Registry is IRegistry, AccessManagedUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 constant MAX_TOKENIZATION_FEE = 1e16;
    uint256 constant MAX_YIELD_FEE = 5e17;
    uint256 constant MAX_PT_FLASH_LOAN_FEE = 1e18;
    uint256 constant FEE_DIVISOR = 1e18;

    /// Addresses
    address private factory;
    address private router;
    address private routerUtil;

    /// Beacons
    address private ptBeacon;
    address private ytBeacon;

    /// Fees
    uint256 private tokenizationFee;
    uint256 private yieldFee;
    uint256 private ptFlashLoanFee;
    address private feeCollector;

    EnumerableSet.AddressSet private pts;

    /** @dev For each pt, a list of whitelisted users get to see their fees reduced */
    mapping(address => mapping(address => uint256)) private feeReduction;

    /* Events
     *****************************************************************************************************************/
    event FactoryChange(address indexed previousFactory, address indexed newFactory);
    event RouterChange(address indexed previousRouter, address indexed newRouter);
    event RouterUtilChange(address indexed previousRouterUtil, address indexed newRouterUtil);
    event PTBeaconChange(address indexed previousPtBeacon, address indexed newPtBeacon);
    event YTBeaconChange(address indexed previousYtBeacon, address indexed newYtBeacon);
    event RateOracleBeaconChange(
        address indexed previousRateOracleBeacon,
        address indexed newRateOracleBeacon
    );
    event TokenizationFeeChange(uint256 previousTokenizationFee, uint256 newTokenizationFee);
    event YieldFeeChange(uint256 previousYieldFee, uint256 newYieldFee);
    event PTFlashLoanFeeChange(uint256 previousPTFlashLoanFee, uint256 newPtFlashLoanFee);
    event FeeCollectorChange(address indexed previousFeeCollector, address indexed newFeeCollector);
    event FeeReduced(address indexed pt, address indexed user, uint256 reduction);
    event PTAdded(address indexed pt);
    event PTRemoved(address indexed pt);

    constructor() {
        _disableInitializers(); // using this so that the deployed logic contract later cannot be initialized.
    }

    /**
     * @notice Initializer of the contract
     */
    function initialize(address _initialAuthority) external initializer {
        __AccessManaged_init(_initialAuthority);
    }

    /* GETTERS
     *****************************************************************************************************************/

    /** @dev See {IRegistry-getFactory}. */
    function getFactory() external view override returns (address) {
        return factory;
    }

    /** @dev See {IRegistry-getRouter}. */
    function getRouter() external view override returns (address) {
        return router;
    }

    /** @dev See {IRegistry-getRouterUtil}. */
    function getRouterUtil() external view override returns (address) {
        return routerUtil;
    }

    /** @dev See {IRegistry-getPTBeacon}. */
    function getPTBeacon() external view override returns (address) {
        return ptBeacon;
    }

    /** @dev See {IRegistry-getYTBeacon}. */
    function getYTBeacon() external view override returns (address) {
        return ytBeacon;
    }

    /** @dev See {IRegistry-getTokenizationFee}. */
    function getTokenizationFee() external view override returns (uint256) {
        return tokenizationFee;
    }

    /** @dev See {IRegistry-getYieldFee}. */
    function getYieldFee() external view override returns (uint256) {
        return yieldFee;
    }

    /** @dev See {IRegistry-getPTFlashLoanFee}. */
    function getPTFlashLoanFee() external view override returns (uint256) {
        return ptFlashLoanFee;
    }

    /** @dev See {IRegistry-getFeeCollector}. */
    function getFeeCollector() external view override returns (address) {
        return feeCollector;
    }

    /** @dev See {IRegistry-getFeeReduction}. */
    function getFeeReduction(address _pt, address _user) external view override returns (uint256) {
        return feeReduction[_pt][_user];
    }

    /** @dev See {IRegistry-isRegisteredPT}. */
    function isRegisteredPT(address _pt) public view override returns (bool) {
        return pts.contains(_pt);
    }

    /** @dev See {IRegistry-getPTAt}. */
    function getPTAt(uint256 _index) external view override returns (address) {
        return pts.at(_index);
    }

    /** @dev See {IRegistry-pTCount}. */
    function pTCount() external view override returns (uint256) {
        return pts.length();
    }

    /* SETTERS
     *****************************************************************************************************************/

    /** @dev See {IRegistry-setFactory}. */
    function setFactory(address _newFactory) external override restricted {
        if (_newFactory == address(0)) {
            revert AddressError();
        }
        emit FactoryChange(factory, _newFactory);
        factory = _newFactory;
    }

    /** @dev See {IRegistry-setRouter}. */
    function setRouter(address _router) external override restricted {
        if (_router == address(0)) {
            revert AddressError();
        }
        emit RouterChange(router, _router);
        router = _router;
    }

    /** @dev See {IRegistry-setRouterUtil}. */
    function setRouterUtil(address _routerUtil) external override restricted {
        if (_routerUtil == address(0)) {
            revert AddressError();
        }
        emit RouterUtilChange(routerUtil, _routerUtil);
        routerUtil = _routerUtil;
    }

    /** @dev See {IRegistry-setPTBeacon}. */
    function setPTBeacon(address _ptBeacon) external override restricted {
        if (_ptBeacon == address(0)) {
            revert AddressError();
        }
        emit PTBeaconChange(ptBeacon, _ptBeacon);
        ptBeacon = _ptBeacon;
    }

    /** @dev See {IRegistry-setYTBeacon}. */
    function setYTBeacon(address _ytBeacon) external override restricted {
        if (_ytBeacon == address(0)) {
            revert AddressError();
        }
        emit YTBeaconChange(ytBeacon, _ytBeacon);
        ytBeacon = _ytBeacon;
    }

    /** @dev See {IRegistry-setTokenizationFee}. */
    function setTokenizationFee(uint256 _tokenizationFee) external override restricted {
        if (_tokenizationFee > MAX_TOKENIZATION_FEE) {
            revert FeeGreaterThanMaxValue();
        }
        emit TokenizationFeeChange(tokenizationFee, _tokenizationFee);
        tokenizationFee = _tokenizationFee;
    }

    /** @dev See {IRegistry-setYieldFee}. */
    function setYieldFee(uint256 _yieldFee) external override restricted {
        if (_yieldFee > MAX_YIELD_FEE) {
            revert FeeGreaterThanMaxValue();
        }
        emit YieldFeeChange(yieldFee, _yieldFee);
        yieldFee = _yieldFee;
    }

    /** @dev See {IRegistry-setPTFlashLoanFee}. */
    function setPTFlashLoanFee(uint256 _ptFlashLoanFee) external override restricted {
        if (_ptFlashLoanFee > MAX_PT_FLASH_LOAN_FEE) {
            revert FeeGreaterThanMaxValue();
        }
        emit PTFlashLoanFeeChange(ptFlashLoanFee, _ptFlashLoanFee);
        ptFlashLoanFee = _ptFlashLoanFee;
    }

    /** @dev See {IRegistry-setFeeCollector}. */
    function setFeeCollector(address _feeCollector) external override restricted {
        if (_feeCollector == address(0)) {
            revert AddressError();
        }
        emit FeeCollectorChange(feeCollector, _feeCollector);
        feeCollector = _feeCollector;
    }

    /** @dev See {IRegistry-reduceFee}. */
    function reduceFee(
        address _pt,
        address _user,
        uint256 _reduction
    ) external override restricted {
        if (_reduction > FEE_DIVISOR) {
            revert ReductionTooBig();
        }
        emit FeeReduced(_pt, _user, _reduction);
        feeReduction[_pt][_user] = _reduction;
    }

    /** @dev See {IRegistry-addPT}. */
    function addPT(address _pt) external override restricted {
        if (!(pts.add(_pt))) {
            revert PTListUpdateFailed();
        }
        emit PTAdded(_pt);
    }

    /** @dev See {IRegistry-removePT}. */
    function removePT(address _pt) external override restricted {
        if (!(pts.remove(_pt))) {
            revert PTListUpdateFailed();
        }
        emit PTRemoved(_pt);
    }
}
