// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

interface IRewardsProxy {
    /**
     * @notice Claims rewards based on the provided data.
     * @dev This function should be called using `delegatecall`, and should handle the logic for claiming rewards
     * based on the input data. The specific format and structure of `data` should be defined by the implementation.
     * @param _data ABI-encoded data containing the necessary information to claim rewards.
     */
    function claimRewards(bytes memory _data) external;
}
