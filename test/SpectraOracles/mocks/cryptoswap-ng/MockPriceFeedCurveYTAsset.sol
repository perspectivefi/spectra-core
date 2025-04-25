// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

import {AggregatorV3Interface} from "src/interfaces/AggregatorV3Interface.sol";
import {BaseFeedCurveYTAsset} from "src/spectra-oracles/chainlinkFeeds/cryptoswap-ng/BaseFeedCurveYTAsset.sol";

/// @dev Mock Curve YT price feed that gives the YT price in a provided IBT/PT Curve Pool in asset
contract MockPriceFeedCurveYTAsset is BaseFeedCurveYTAsset {
    string public constant description = "IBT/PT Curve Pool Oracle: YT price in asset";

    /* CONSTRUCTOR
     *****************************************************************************************************************/
    /**
     * @notice Constructor for a Mock Price Feed of a Curve Pool (in asset)
     */
    constructor(address _pt, address _pool) BaseFeedCurveYTAsset(_pt, _pool) {}
}
