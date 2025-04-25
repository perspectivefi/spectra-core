// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

import {AggregatorV3Interface} from "src/interfaces/AggregatorV3Interface.sol";
import {BaseFeedCurvePTAssetSNG} from "src/spectra-oracles/chainlinkFeeds/stableswap-ng/BaseFeedCurvePTAsset.sol";

/// @dev Mock Curve PT price feed that gives the PT price in a provided IBT/PT Curve Pool in asset
contract MockPriceFeedCurvePTAssetSNG is BaseFeedCurvePTAssetSNG {
    string public constant description = "IBT/PT Curve Pool Oracle: PT price in asset";

    /* CONSTRUCTOR
     *****************************************************************************************************************/
    /**
     * @notice Constructor for a Mock Price Feed of a Curve Pool (in asset)
     */
    constructor(address _pt, address _pool) BaseFeedCurvePTAssetSNG(_pt, _pool) {}
}
