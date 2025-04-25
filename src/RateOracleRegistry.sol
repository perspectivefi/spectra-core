// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "openzeppelin-contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import "./interfaces/IRateOracleRegistry.sol";

/**
 * @title Rate Oracle Registry Contract
 * @author Spectra Finance
 * @notice Keeps a record of rate oracle addresses associated with Stableswap NG pools.
 */
contract RateOracleRegistry is IRateOracleRegistry, AccessManagedUpgradeable {
    /* Events
     *****************************************************************************************************************/

    event FactorySNGChange(address indexed previousFactorySNG, address indexed newFactorySNG);

    event RateOracleBeaconChange(
        address indexed previousRateOracleBeacon,
        address indexed newRateOracleBeacon
    );
    event RateOracleAdded(address indexed pt, address indexed rateOracle);
    event RateOracleRemoved(address indexed pt, address indexed rateOracle);

    // Factory
    address private factorySNG;
    // Beacons
    address private rateOracleBeacon;

    /** @dev stores the rate oracle associated to the pool holding the given PT */
    mapping(address => address) private ptToRateOracle;

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

    function getFactorySNG() external view returns (address) {
        return factorySNG;
    }

    /** @dev See {IRateOracleRegistry-getRateOracleBeacon}. */
    function getRateOracleBeacon() external view returns (address) {
        return rateOracleBeacon;
    }

    /** @dev See {IRateOracleRegistry-getRateOracle}. */
    function getRateOracle(address _pt) external view returns (address) {
        return ptToRateOracle[_pt];
    }

    /* SETTERS
     *****************************************************************************************************************/

    function setFactorySNG(address _factorySNG) external override restricted {
        if (_factorySNG == address(0)) {
            revert AddressError();
        }
        emit FactorySNGChange(factorySNG, _factorySNG);
        factorySNG = _factorySNG;
    }

    /** @dev See {IRateOracleRegistry-setRateOracleBeacon}. */
    function setRateOracleBeacon(address _rateOracleBeacon) external override restricted {
        if (_rateOracleBeacon == address(0)) {
            revert AddressError();
        }
        emit RateOracleBeaconChange(rateOracleBeacon, _rateOracleBeacon);
        rateOracleBeacon = _rateOracleBeacon;
    }

    /** @dev See {IRateOracleRegistry-addRateOracle}. */
    function addRateOracle(address _pt, address _rateOracle) external override restricted {
        if (_pt == address(0) || _rateOracle == address(0)) {
            revert AddressError();
        }
        // @dev: do not overwrite exisiting bindings
        if (ptToRateOracle[_pt] != address(0)) {
            revert RegistryOverwriteAttempt(_pt, ptToRateOracle[_pt]);
        }

        ptToRateOracle[_pt] = _rateOracle;

        emit RateOracleAdded(_pt, _rateOracle);
    }

    /** @dev See {IRateOracleRegistry-addRateOracle}. */
    function removeRateOracle(address _pt, address _rateOracle) external override restricted {
        if (ptToRateOracle[_pt] != _rateOracle) {
            revert PTRateOracleMismatch();
        }
        delete ptToRateOracle[_pt];

        emit RateOracleRemoved(_pt, _rateOracle);
    }
}
