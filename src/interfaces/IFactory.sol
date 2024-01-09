// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

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
        uint256 allowed_extra_profit;
        uint256 fee_gamma;
        uint256 adjustment_step;
        uint256 admin_fee;
        uint256 ma_half_time;
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
     * allowed_extra_profit, fee_gamma, adjustment_step, admin_fee, ma_half_time, initial_price
     * @return curvePoolAddr The address of the deployed curve pool.
     */
    function deployCurvePool(
        address _pt,
        CurvePoolParams calldata curvePoolParams,
        uint256 _initialLiquidityInIBT
    ) external returns (address curvePoolAddr);

    /**
     * @notice Deploys associated PT and Curve Pool.
     * @param _ibt The address of the ibt that will be associated with the pool.
     * @param curvePoolParams The curve pool parameters to be used in the deployment.
     * For example, the Curve Factory will deploy a pool like so:
     * abi.encodeWithSelector(initialize.selector, params)
     * List of parameters: name, symbol, coins [ibt,pt], A, gamma, mid_fee, out_fee,
     * allowed_extra_profit, fee_gamma, adjustment_step, admin_fee, ma_half_time, initial_price
     * @return pt The address of the deployed PT.
     * @return curvePoolAddr The address of the deployed curve pool.
     */
    function deployAll(
        address _ibt,
        uint256 _duration,
        CurvePoolParams calldata curvePoolParams,
        uint256 _initialLiquidityInIBT
    ) external returns (address pt, address curvePoolAddr);

    /* GETTERS
     *****************************************************************************************************************/

    /**
     * @notice Getter for the registry address.
     * @return The address of the registry
     */
    function getRegistry() external view returns (address);

    /**
     * @notice Getter for the Curve Address Provider address
     * @return The address of the Curve Address Provider
     */
    function getCurveAddressProvider() external view returns (address);

    /**
     * @notice Getter for the Curve Factory address
     * @return The address of the Curve Factory
     */
    function getCurveFactory() external view returns (address);

    /* SETTERS
     *****************************************************************************************************************/

    /**
     * @notice Setter for the registry address. Can only be called by the owner.
     * @param _newRegistry The address of the registry.
     */
    function setRegistry(address _newRegistry) external;

    /**
     * @notice Function which sets the curveAddressProvider address used in
      getting the curve factory address. Can only be called by owner.
     * @param _curveAddressProvider The address of the curveAddressProvider.
     */
    function setCurveAddressProvider(address _curveAddressProvider) external;
}
