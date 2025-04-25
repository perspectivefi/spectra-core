// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

interface IFactory {
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
        uint256 gamma;
        uint256 mid_fee;
        uint256 out_fee;
        uint256 fee_gamma;
        uint256 allowed_extra_profit;
        uint256 adjustment_step;
        uint256 ma_exp_time;
        uint256 initial_price;
    }

    /**
     * @notice Deploys a PT.
     * @param _ibt The address of the ibt that will be associated with the PT.
     * @param _duration The duration of the PT.
     * @return pt The address of the deployed PT.
     */
    function deployPT(address _ibt, uint256 _duration) external returns (address pt);

    /**
     * @notice Deploys a Curve Pool for a PT and its associated IBT.
     * @param _pt The address of the PT.
     * @param curvePoolParams The curve pool parameters to be used in the deployment.
     * For example, the Curve Factory will deploy a pool like so:
     * abi.encodeWithSelector(initialize.selector, params)
     * List of parameters: name, symbol, coins [ibt,pt], A, gamma, mid_fee, out_fee,
     * fee_gamma, allowed_extra_profit, adjustment_step, ma_exp_time, initial_price
     * @param _initialLiquidityInIBT The initial IBT liquidity (to be split between IBT/PT) to be added to pool after deployment.
     * @param _minPTShares The minimum allowed shares from deposit in PT. Ignored if _initialLiquidityInIBT is 0.
     * @return curvePoolAddr The address of the deployed curve pool.
     */
    function deployCurvePool(
        address _pt,
        CurvePoolParams calldata curvePoolParams,
        uint256 _initialLiquidityInIBT,
        uint256 _minPTShares
    ) external returns (address curvePoolAddr);

    /**
     * @notice Deploys associated PT and Curve Pool.
     * @param _ibt The address of the ibt that will be associated with the pool.
     * @param curvePoolParams The curve pool parameters to be used in the deployment.
     * For example, the Curve Factory will deploy a pool like so:
     * abi.encodeWithSelector(initialize.selector, params)
     * List of parameters: name, symbol, coins [ibt,pt], A, gamma, mid_fee, out_fee,
     * fee_gamma, allowed_extra_profit, adjustment_step, ma_exp_time, initial_price
     * @param _initialLiquidityInIBT The initial IBT liquidity (to be split between IBT/PT) to be added to pool after deployment.
     * @param _minPTShares The minimum allowed shares from deposit in PT. Ignored if _initialLiquidityInIBT is 0.
     * @return pt The address of the deployed PT.
     * @return curvePoolAddr The address of the deployed curve pool.
     */
    function deployAll(
        address _ibt,
        uint256 _duration,
        CurvePoolParams calldata curvePoolParams,
        uint256 _initialLiquidityInIBT,
        uint256 _minPTShares
    ) external returns (address pt, address curvePoolAddr);

    /* GETTERS
     *****************************************************************************************************************/

    /**
     * @notice Getter for the registry address.
     * @return The address of the registry
     */
    function getRegistry() external view returns (address);

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
