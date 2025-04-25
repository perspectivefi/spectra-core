// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import {BaseOracle} from "src/spectra-oracles/oracles/BaseOracle.sol";

/**
 * @title BaseOracleCurvePT contract
 * @author Spectra Finance
 * @notice A base oracle implementation for the PT
 */
abstract contract BaseOracleCurvePT is BaseOracle {
    constructor(address _pt, address _pool) BaseOracle(_pt, _pool) {}

    /* INTERNAL
     *****************************************************************************************************************/

    function _getQuoteAmount() internal view override returns (uint256) {
        return _PTPrice();
    }

    /**
     * @dev Depending on the pool you should use:
     * getPTToAssetRate() should be used,
     * or getPTToIBTRate() if the asset is not easily tradable with IBT
     */
    function _PTPrice() internal view virtual returns (uint256);
}
