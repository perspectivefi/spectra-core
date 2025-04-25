// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

interface IRateOracleRegistry {
    /* Errors
     *****************************************************************************************************************/
    error AddressError();
    error PTRateOracleMismatch();
    error RegistryOverwriteAttempt(address _pt, address _rateOracleRegistry);

    /* GETTERS
     *****************************************************************************************************************/

    function getFactorySNG() external view returns (address);

    function getRateOracleBeacon() external view returns (address);

    function getRateOracle(address _pt) external view returns (address);

    /* SETTERS
     *****************************************************************************************************************/

    /**
     * @notice set the factory with rate oracle pool
     * @param _factorySNG address of the factory
     */
    function setFactorySNG(address _factorySNG) external;

    /**
     * @notice set the rate oracle beacon
     * @param _rateOracleBeacon The address of yt beacon
     */
    function setRateOracleBeacon(address _rateOracleBeacon) external;

    /**
     * @notice Add a rate oracle to the registry
     * @param _pt The address of the pt in the pool using the rate oracle
     * @param _rateOracle The address of the rate oracle to add to the registry
     */
    function addRateOracle(address _pt, address _rateOracle) external;

    /**
     * @notice Remove a rate oracle from the registry
     * @param _pt The address of the pt in the pool using the rate oracle
     * @param _rateOracle The address of the rate oracle to remove from the registry
     */
    function removeRateOracle(address _pt, address _rateOracle) external;
}
