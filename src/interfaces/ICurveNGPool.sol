// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @dev Interface for Curve TwoCrypto-NG pool
 */
interface ICurveNGPool is IERC20Metadata {
    function coins(uint256 index) external view returns (address);

    function balances(uint256 index) external view returns (uint256);

    function A() external view returns (uint256);

    function gamma() external view returns (uint256);

    function D() external view returns (uint256);

    function token() external view returns (address);

    function price_scale() external view returns (uint256);

    function price_oracle() external view returns (uint256);

    function future_A_gamma_time() external view returns (uint256);

    function future_A_gamma() external view returns (uint256);

    function initial_A_gamma_time() external view returns (uint256);

    function initial_A_gamma() external view returns (uint256);

    function fee_gamma() external view returns (uint256);

    function mid_fee() external view returns (uint256);

    function out_fee() external view returns (uint256);

    function allowed_extra_profit() external view returns (uint256);

    function adjustment_step() external view returns (uint256);

    function admin_fee() external view returns (uint256);

    function ma_time() external view returns (uint256);

    function get_virtual_price() external view returns (uint256);

    function fee() external view returns (uint256);

    function get_dy(uint256 i, uint256 j, uint256 dx) external view returns (uint256);

    function get_dx(uint256 i, uint256 j, uint256 dy) external view returns (uint256);

    function last_prices() external view returns (uint256);

    function calc_token_amount(
        uint256[2] calldata amounts,
        bool deposit
    ) external view returns (uint256);

    function calc_withdraw_one_coin(
        uint256 _token_amount,
        uint256 i
    ) external view returns (uint256);

    function exchange(uint256 i, uint256 j, uint256 dx, uint256 min_dy) external returns (uint256);

    function exchange(
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 min_dy,
        address receiver
    ) external returns (uint256);

    function add_liquidity(
        uint256[2] calldata amounts,
        uint256 min_mint_amount
    ) external returns (uint256);

    function add_liquidity(
        uint256[2] calldata amounts,
        uint256 min_mint_amount,
        address receiver
    ) external returns (uint256);

    function remove_liquidity(uint256 amount, uint256[2] calldata min_amounts) external;

    function remove_liquidity(
        uint256 amount,
        uint256[2] calldata min_amounts,
        address receiver
    ) external;

    function remove_liquidity_one_coin(
        uint256 token_amount,
        uint256 i,
        uint256 min_amount
    ) external;

    function remove_liquidity_one_coin(
        uint256 token_amount,
        uint256 i,
        uint256 min_amount,
        address receiver
    ) external;
}
