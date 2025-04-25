// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

/**
 * @title NamingUtil library
 * @author Spectra Finance
 * @notice Provides miscellaneous utils for token naming.
 */
library NamingUtil {
    function genYTSymbol(
        string memory _ibtSymbol,
        uint256 _dateOfExpiry
    ) internal pure returns (string memory) {
        string memory date = uintToString(_dateOfExpiry);
        string memory symbol = concatenate(_ibtSymbol, "-");
        return concatenate(concatenate("YT-", symbol), date);
    }

    function genYTName(
        string memory _ibtSymbol,
        uint256 _dateOfExpiry
    ) internal pure returns (string memory) {
        string memory date = uintToString(_dateOfExpiry);
        string memory symbol = concatenate(_ibtSymbol, "-");
        return concatenate(concatenate("Yield Token: ", symbol), date);
    }

    function genPTSymbol(
        string memory _ibtSymbol,
        uint256 _dateOfExpiry
    ) internal pure returns (string memory) {
        string memory date = uintToString(_dateOfExpiry);
        string memory symbol = concatenate(_ibtSymbol, "-");
        return concatenate(concatenate("PT-", symbol), date);
    }

    function genPTName(
        string memory _ibtSymbol,
        uint256 _dateOfExpiry
    ) internal pure returns (string memory) {
        string memory date = uintToString(_dateOfExpiry);
        string memory symbol = concatenate(_ibtSymbol, "-");
        return concatenate(concatenate("Principal Token: ", symbol), date);
    }

    function concatenate(string memory a, string memory b) internal pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }

    function uintToString(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
}
