// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "openzeppelin-contracts/interfaces/IERC4626.sol";

contract RateOracle {
    /* ATTRIBUTES
     *****************************************************************************************************************/

    mapping(address => mapping(uint256 => uint256)) private ibtDailyRate; // mapping from date to IBT 4626 rate
    mapping(address => uint256) private ibtLastPokedDate; // mapping from IBT 4626 to last poked date

    /* EVENTS
     *****************************************************************************************************************/
    event IBTRatesDataUpdated(address indexed ibt, uint256 indexed date, uint256 indexed rate);

    /* FUNCTIONS
     *****************************************************************************************************************/

    /**
     * @dev Stores the current rate of the given ibt.
     * @param _ibt The address of the IBT 4626 to store the rate of.
     * @return The stored rate of the given ibt.
     */
    function pokeRate(address _ibt) external returns (uint256) {
        uint256 curDate = block.timestamp / 1 days;
        uint256 curRate = ibtDailyRate[_ibt][curDate];
        if (curRate != 0) {
            return curRate;
        }
        uint256 ibtUnit = 10 ** IERC4626(_ibt).decimals();
        curRate = IERC4626(_ibt).convertToAssets(ibtUnit);
        ibtDailyRate[_ibt][curDate] = curRate;
        ibtLastPokedDate[_ibt] = curDate;
        emit IBTRatesDataUpdated(_ibt, curDate, curRate);
        return curRate;
    }

    /* GETTERS
     *****************************************************************************************************************/

    /**
     * @notice Getter for the rate of a given IBT at a given date.
     * @param _ibt Address of the ibt to get the rate of.
     * @param _date Date of the rate to get (in number of days since Jan. 1st 1970 UTC GMT).
     * @return Rate of the given ibt at the given date.
     */
    function getRateOfVaultOnDate(address _ibt, uint256 _date) external view returns (uint256) {
        return ibtDailyRate[_ibt][_date];
    }

    /**
     * @notice Getter for the last date the rate got poked for the given ibt.
     * @param _ibt Address of the ibt to get the last poked date of.
     * @return The date of the last time a poke happened on the given ibt.
     *         In number of days since Jan. 1st 1970 UTC GMT.
     */
    function getLastPokedDateOfVault(address _ibt) external view returns (uint256) {
        return ibtLastPokedDate[_ibt];
    }
}
