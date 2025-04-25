// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

interface IRateAdjustmentOracle {
    /* ERRORS
     *****************************************************************************************************************/

    error AddressError();
    error AddressesNotSet();
    error PostInitCalledBeforeInit();

    /* Functions
     *****************************************************************************************************************/

    /**
     * @notice First function called after contract depoyment, sets the contract authority
     * @param _initialAuthority Initial authority of the rate oracle
     */
    function initialize(address _initialAuthority) external;

    /**
     * @dev Function called after deployment of the associated Curve Pool to initialize the remaining state.
     * @dev Deployment of the Curve Pool requires the address of the rate adjustment oracle, while the rate adjustment
     * @dev oracle needs the address of the Curve Pool to make function calls. Therefore, initialization is done in two steps.
     * @param _startTimestamp The PT deployment time
     * @param _expiry The PT expiry
     * @param _initialPrice The initial PT/IBT exchange rate
     * @param _curvePoolAddress Address of the curve pool
     */
    function post_initialize(
        uint256 _startTimestamp,
        uint256 _expiry,
        uint256 _initialPrice,
        address _curvePoolAddress
    ) external;

    /**
     * @notice Function reporting the oracle value used in curve stableswap pool
     * @return Multiplicative adjustment factor for last_prices in between each two trades
     */
    function value() external view returns (uint256);

    /**
     * @notice Function to change the current initial price
     * @param _newInitialPrice new initial price we want to set
     */
    function setInitialPrice(uint256 _newInitialPrice) external;

    /**
     * @notice Getter for the current initial price
     * @return current initial price
     */
    function getInitialPrice() external view returns (uint256);

    /**
     * @notice Getter for the curve pool address of the rate adjustment oracle
     * @return curve pool address
     */
    function getCurvePoolAddress() external view returns (address);

    /**
     * Getter for the start time of the pt
     * @return start time of the pt
     */
    function getStartTime() external view returns (uint256);

    /**
     * @notice Getter for the expiry of the pt
     * @return expiry of the pt
     */
    function getExpiry() external view returns (uint256);
}
