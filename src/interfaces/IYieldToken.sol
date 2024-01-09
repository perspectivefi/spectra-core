// SPDX-License-Identifier: BUSL-1.1

import "openzeppelin-contracts/interfaces/IERC20.sol";

pragma solidity 0.8.20;

interface IYieldToken is IERC20 {
    error CallerIsNotPtContract();

    /**
     * @notice Initializer of the contract.
     * @param name_ The name of the yt token.
     * @param symbol_ The symbol of the yt token.
     * @param pt The address of the PT associated with this yt token.
     */
    function initialize(string calldata name_, string calldata symbol_, address pt) external;

    /**
     * @notice returns the decimals of the yt tokens.
     */
    function decimals() external view returns (uint8);

    /**
     * @dev Returns the address of PT associated with this yt.
     */
    function getPT() external view returns (address);

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    /**
     * @notice checks for msg.sender to be pt and then calls _burn of ERC20Upgradeable.
     * See {ERC20Upgradeable- _burn}.
     * @param from address from which tokens will be burnt
     * @param amount to burn
     */
    function burnWithoutUpdate(address from, uint256 amount) external;

    /**
     * @notice checks for msg.sender to be pt and then calls _mint of ERC20Upgradeable.
     * See {ERC20Upgradeable- _mint}.
     * @param to address to mint YT's to
     * @param amount to mint
     */
    function mint(address to, uint256 amount) external;

    /**
     * @notice updates the yield of the caller and then calls _burn of ERC20Upgradeable.
     * See {ERC20Upgradeable-_burn}.
     * @param amount of YT's to burn
     */
    function burn(uint256 amount) external;

    /**
     * @dev Returns the amount of tokens owned by `account` before expiry, and 0 after expiry
     * @notice This behaviour is for UI/UX purposes only
     * @param account The address of the user to get the actual balance of YT from
     * @return The users balance of YTs before expiry, and 0 after expiry
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Returns the actual amount of tokens owned by `account` at any point in time
     * @param account The address of the user to get the actual balance of YT from
     * @return The actual users balance of YTs (before and after expiry)
     */
    function actualBalanceOf(address account) external view returns (uint256);
}
