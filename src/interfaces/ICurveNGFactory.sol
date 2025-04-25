// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

/**
 * @dev Interface for Curve TwoCrypto-NG Factory
 */
interface ICurveNGFactory {
    function deploy_pool(
        string calldata _name,
        string calldata _symbol,
        address[2] calldata _coins,
        uint256 implementation_id,
        uint256 A,
        uint256 gamma,
        uint256 mid_fee,
        uint256 out_fee,
        uint256 fee_gamma,
        uint256 allowed_extra_profit,
        uint256 adjustment_step,
        uint256 ma_exp_time,
        uint256 initial_price
    ) external returns (address);
}
