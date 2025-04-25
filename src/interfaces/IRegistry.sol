// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

interface IRegistry {
    /* Errors
     *****************************************************************************************************************/
    error FeeGreaterThanMaxValue();
    error PTListUpdateFailed();
    error ReductionTooBig();
    error AddressError();

    /* GETTERS
     *****************************************************************************************************************/

    /**
     * @notice Getter for the factory address
     * @return The address of token factory
     */
    function getFactory() external view returns (address);

    /**
     * @notice Get the address of the router
     * @return The address of the router
     */
    function getRouter() external view returns (address);

    /**
     * @notice Get the address of the routerUtil
     * @return The address of the routerUtil
     */
    function getRouterUtil() external view returns (address);

    /**
     * @notice Get the address of the pt beacon
     * @return The address of PT beacon
     */
    function getPTBeacon() external view returns (address);

    /**
     * @notice Get the address of the yt beacon
     * @return The address of yt beacon
     */
    function getYTBeacon() external view returns (address);

    /**
     * @notice Get the value of tokenization fee
     * @return The value of tokenization fee
     */
    function getTokenizationFee() external view returns (uint256);

    /**
     * @notice Get the value of yield fee
     * @return The value of yield fee
     */
    function getYieldFee() external view returns (uint256);

    /**
     * @notice Get the value of PT flash loan fee
     * @return The value of PT flash loan fee
     */
    function getPTFlashLoanFee() external view returns (uint256);

    /**
     * @notice Get the address of the fee collector
     * @return The address of fee collector
     */
    function getFeeCollector() external view returns (address);

    /**
     * @notice Get the fee reduction of the given user for the given pt
     * @param _pt The address of the pt
     * @param _user The address of the user
     * @return The fee reduction of the given user for the given pt
     */
    function getFeeReduction(address _pt, address _user) external view returns (uint256);

    /**
     * @notice Getter to check if a pt is registered
     * @param _pt the address of the pt to check the registration of
     * @return true if it is, false otherwise
     */
    function isRegisteredPT(address _pt) external view returns (bool);

    /**
     * @notice Getter for the pt registered at an index
     * @param _index the index of the pt to return
     * @return The address of the corresponding pt
     */
    function getPTAt(uint256 _index) external view returns (address);

    /**
     * @notice Getter for number of PT registered
     * @return The number of PT registered
     */
    function pTCount() external view returns (uint256);

    /* SETTERS
     *****************************************************************************************************************/

    /**
     * @notice Setter for the tokens factory address
     * @param _newFactory The address of the new factory
     */
    function setFactory(address _newFactory) external;

    /**
     * @notice set the router
     * @param _router The address of the router
     */
    function setRouter(address _router) external;

    /**
     * @notice set the routerUtil
     * @param _routerUtil The address of the routerUtil
     */
    function setRouterUtil(address _routerUtil) external;

    /**
     * @notice set the tokenization fee
     * @param _tokenizationFee The value of tokenization fee
     */
    function setTokenizationFee(uint256 _tokenizationFee) external;

    /**
     * @notice set the yield fee
     * @param _yieldFee The value of yield fee
     */
    function setYieldFee(uint256 _yieldFee) external;

    /**
     * @notice set the PT flash loan fee
     * @param _ptFlashLoanFee The value of PT flash loan fee
     */
    function setPTFlashLoanFee(uint256 _ptFlashLoanFee) external;

    /**
     * @notice set the fee collector
     * @param _feeCollector The address of fee collector
     */
    function setFeeCollector(address _feeCollector) external;

    /**
     * @notice Set the fee reduction of the given pt for the given user
     * @param _pt The address of the pt
     * @param _user The address of the user
     * @param _reduction The fee reduction
     */
    function reduceFee(address _pt, address _user, uint256 _reduction) external;

    /**
     * @notice set the pt beacon
     * @param _ptBeacon The address of PT beacon
     */
    function setPTBeacon(address _ptBeacon) external;

    /**
     * @notice set the yt beacon
     * @param _ytBeacon The address of yt beacon
     */
    function setYTBeacon(address _ytBeacon) external;

    /**
     * @notice Add a pt to the registry
     * @param _pt The address of the pt to add to the registry
     */
    function addPT(address _pt) external;

    /**
     * @notice Remove a pt from the registry
     * @param _pt The address of the pt to remove from the registry
     */
    function removePT(address _pt) external;
}
