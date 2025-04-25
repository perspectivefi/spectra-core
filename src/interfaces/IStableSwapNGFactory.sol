// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

interface IStableSwapNGFactory {
    function deploy_plain_pool(
        string calldata _name,
        string calldata _symbol,
        address[] calldata _coins,
        uint256 A,
        uint256 fee,
        uint256 fee_mul,
        uint256 ma_exp_time,
        uint256 implementation_idx,
        uint8[] calldata asset_types,
        bytes4[] calldata method_ids,
        address[] calldata oracles
    ) external returns (address);
}
