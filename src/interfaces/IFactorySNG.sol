// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

interface IFactorySNG {
    /* Errors
     *****************************************************************************************************************/
    error BeaconNotSet();
    error CurveFactoryNotSet();
    error DeploymentFailed();
    error AddressError();
    error FailedToFetchCurveFactoryAddress();
    error UnregisteredPT();
    error CurvePoolCoinError();
    error ExpiredPT();

    struct CurvePoolParams {
        uint256 A;
        uint256 fee;
        uint256 fee_mul;
        uint256 ma_exp_time;
        uint256 initial_price;
        address rate_adjustment_oracle;
    }

    /**
     * @notice Deploys associated PT and Curve Pool.
     * @param _ibt The address of the ibt that will be associated with the pool.
     * @param curvePoolParams The curve pool parameters to be used in the deployment.
     * For example, the Curve Factory will deploy a pool like so:
     * abi.encodeWithSelector(initialize.selector, params)
     * List of parameters: name, symbol, coins [ibt,pt], A, gamma, mid_fee, out_fee,
     * allowed_extra_profit, fee_gamma, adjustment_step, admin_fee, ma_half_time, initial_price
     * @param _initialLiquidityInIBT The initial IBT liquidity (to be split between IBT/PT) to be added to pool after deployment.
     * @param _minPTShares The minimum allowed shares from deposit in PT. Ignored if _initialLiquidityInIBT is 0.
     * @return pt The address of the deployed PT.
     * @return rateAdjustmentOracle The address of the deployed rate adjustment oracle.
     * @return curvePoolAddr The address of the deployed curve pool.
     */
    function deployAll(
        address _ibt,
        uint256 _duration,
        CurvePoolParams calldata curvePoolParams,
        uint256 _initialLiquidityInIBT,
        uint256 _minPTShares
    ) external returns (address pt, address rateAdjustmentOracle, address curvePoolAddr);

    /* GETTERS
     *****************************************************************************************************************/

    /**
     * @notice Getter for the registry address.
     * @return The address of the registry
     */
    function getRegistry() external view returns (address);

    /**
     * @notice Getter for the rate oracle registry address.
     * @return The address of the rate oracle registry
     */
    function getRateOracleRegistry() external view returns (address);

    /**
     * @notice Getter for the Curve Factory address
     * @return The address of the Curve Factory
     */
    function getCurveFactory() external view returns (address);

    /* SETTERS
     *****************************************************************************************************************/

    /**
     * @notice Setter for the Curve factory address used for deploying curve pools.
     * Can only be called by admin.
     * @param _curveFactory The address of the Curve Factory.
     */
    function setCurveFactory(address _curveFactory) external;
}
