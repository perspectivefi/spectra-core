// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-math/Math.sol";
import "openzeppelin-erc20-extensions/ERC20PermitUpgradeable.sol";
import "openzeppelin-contracts/proxy/beacon/BeaconProxy.sol";
import "openzeppelin-contracts/interfaces/IERC3156FlashBorrower.sol";
import "openzeppelin-contracts/interfaces/IERC4626.sol";

import "./MockPrincipalTokenUtilV2.sol";
import "../libraries/NamingUtil.sol";
import "../libraries/RayMath.sol";
import "../interfaces/IRegistry.sol";
import "../interfaces/IPrincipalToken.sol";
import "../interfaces/IYieldToken.sol";
import "../interfaces/IRewardsProxy.sol";

/**
 * @dev This contract is used to test upgradeability of PrincipalToken.sol.
 * Only differences with PrincipalToken.sol are the symbol and name, suffixed here with "V2",
 * maxDeposit decreased by 1 and using MockPrincipalTokenUtilV2.
 */
contract MockPrincipalTokenV2 is
    ERC20PermitUpgradeable,
    AccessManagedUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    IPrincipalToken
{
    using SafeERC20 for IERC20;
    using RayMath for uint256;
    using Math for uint256;

    uint256 private constant MIN_DECIMALS = 6;
    uint256 private constant MAX_DECIMALS = 18;
    bytes32 private constant ON_FLASH_LOAN = keccak256("ERC3156FlashBorrower.onFlashLoan");

    address private immutable registry;

    address private rewardsProxy;
    bool private ratesAtExpiryStored;
    address private ibt; // address of the Interest Bearing Token 4626 held by this PT vault
    address private _asset; // the asset of this PT vault (which is also the asset of the IBT 4626)
    address private yt; // YT corresponding to this PT, deployed at initialization
    uint256 private ibtUnit; // equal to one unit of the IBT held by this PT vault (10^decimals)
    uint256 private _ibtDecimals;
    uint256 private _assetDecimals;

    uint256 private ptRate; // or PT price in asset (in Ray)
    uint256 private ibtRate; // or IBT price in asset (in Ray)
    uint256 private unclaimedFeesInIBT; // unclaimed fees
    uint256 private totalFeesInIBT; // total fees
    uint256 private expiry; // date of maturity (set at initialization)
    uint256 private duration; // duration to maturity

    mapping(address => uint256) private ibtRateOfUser; // stores each user's IBT rate (in Ray)
    mapping(address => uint256) private ptRateOfUser; // stores each user's PT rate (in Ray)
    mapping(address => uint256) private yieldOfUserInIBT; // stores each user's yield generated from YTs

    /* EVENTS
     *****************************************************************************************************************/
    event Redeem(address indexed from, address indexed to, uint256 amount);
    event Mint(address indexed from, address indexed to, uint256 amount);
    event YTDeployed(address indexed yt);
    event YieldUpdated(address indexed user, uint256 indexed yieldInIBT);
    event YieldClaimed(address indexed owner, address indexed receiver, uint256 indexed yieldInIBT);
    event FeeClaimed(
        address indexed user,
        uint256 indexed redeemedIbts,
        uint256 indexed receivedAssets
    );
    event RatesStoredAtExpiry(uint256 indexed ibtRate, uint256 indexed ptRate);
    event RewardsProxyChange(address indexed oldRewardsProxy, address indexed newRewardsProxy);

    /* MODIFIERS
     *****************************************************************************************************************/

    /// @notice Ensures the current block timestamp is before expiry
    modifier notExpired() virtual {
        if (block.timestamp >= expiry) {
            revert PTExpired();
        }
        _;
    }

    /// @notice Ensures the current block timestamp is at or after expiry
    modifier afterExpiry() virtual {
        if (block.timestamp < expiry) {
            revert PTNotExpired();
        }
        _;
    }

    /* CONSTRUCTOR
     *****************************************************************************************************************/
    constructor(address _registry) {
        if (_registry == address(0)) {
            revert AddressError();
        }
        registry = _registry;
        _disableInitializers(); // using this so that the deployed logic contract cannot later be initialized
    }

    /* INITIALIZER
     *****************************************************************************************************************/

    /**
     * @dev First function called after deployment of the contract
     * it deploys yt and intializes values of required variables
     * @param _ibt The token which PT contract holds
     * @param _duration The duration (in s) to expiry/maturity of the PT contract
     * @param _initialAuthority The initial authority of the PT contract
     */
    function initialize(
        address _ibt,
        uint256 _duration,
        address _initialAuthority
    ) external initializer {
        if (_ibt == address(0) || _initialAuthority == address(0)) {
            revert AddressError();
        }
        if (IERC4626(_ibt).totalAssets() == 0) {
            revert RateError();
        }
        _asset = IERC4626(_ibt).asset();
        duration = _duration;
        expiry = _duration + block.timestamp;
        string memory _ibtSymbol = IERC4626(_ibt).symbol();
        string memory name = string.concat(NamingUtil.genPTName(_ibtSymbol, expiry), "V2");
        __ERC20_init(name, string.concat(NamingUtil.genPTSymbol(_ibtSymbol, expiry), "V2"));
        __ERC20Permit_init(name);
        __Pausable_init();
        __ReentrancyGuard_init();
        __AccessManaged_init(_initialAuthority);
        _ibtDecimals = IERC4626(_ibt).decimals();
        _assetDecimals = MockPrincipalTokenUtilV2._tryGetTokenDecimals(_asset);
        if (
            _assetDecimals < MIN_DECIMALS ||
            _assetDecimals > _ibtDecimals ||
            _ibtDecimals > MAX_DECIMALS
        ) {
            revert InvalidDecimals();
        }
        ibt = _ibt;
        ibtUnit = 10 ** _ibtDecimals;
        ibtRate = IERC4626(ibt).previewRedeem(ibtUnit).toRay(_assetDecimals);
        ptRate = RayMath.RAY_UNIT;
        yt = _deployYT(
            NamingUtil.genYTName(_ibtSymbol, expiry),
            NamingUtil.genYTSymbol(_ibtSymbol, expiry)
        );
    }

    /** @dev See {PausableUpgradeable-_pause}. */
    function pause() external override restricted {
        _pause();
    }

    /** @dev See {PausableUpgradeable-_unPause}. */
    function unPause() external override restricted {
        _unpause();
    }

    /** @dev See {IPrincipalToken-deposit}. */
    function deposit(uint256 assets, address receiver) external override returns (uint256 shares) {
        shares = deposit(assets, receiver, receiver);
    }

    /** @dev See {IPrincipalToken-deposit}. */
    function deposit(
        uint256 assets,
        address ptReceiver,
        address ytReceiver
    ) public override returns (uint256 shares) {
        IERC20(_asset).safeTransferFrom(msg.sender, address(this), assets);
        IERC20(_asset).safeIncreaseAllowance(ibt, assets);
        uint256 ibts = IERC4626(ibt).deposit(assets, address(this));
        shares = _depositIBT(ibts, ptReceiver, ytReceiver);
    }

    /** @dev See {IPrincipalToken-deposit}. */
    function deposit(
        uint256 assets,
        address ptReceiver,
        address ytReceiver,
        uint256 minShares
    ) external override returns (uint256 shares) {
        shares = deposit(assets, ptReceiver, ytReceiver);
        if (shares < minShares) {
            revert ERC5143SlippageProtectionFailed();
        }
    }

    /** @dev See {IPrincipalToken-depositIBT}. */
    function depositIBT(uint256 ibts, address receiver) external override returns (uint256 shares) {
        shares = depositIBT(ibts, receiver, receiver);
    }

    /** @dev See {IPrincipalToken-depositIBT}. */
    function depositIBT(
        uint256 ibts,
        address ptReceiver,
        address ytReceiver
    ) public override returns (uint256 shares) {
        IERC20(ibt).safeTransferFrom(msg.sender, address(this), ibts);
        shares = _depositIBT(ibts, ptReceiver, ytReceiver);
    }

    /** @dev See {IPrincipalToken-depositIBT}. */
    function depositIBT(
        uint256 ibts,
        address ptReceiver,
        address ytReceiver,
        uint256 minShares
    ) external override returns (uint256 shares) {
        shares = depositIBT(ibts, ptReceiver, ytReceiver);
        if (shares < minShares) {
            revert ERC5143SlippageProtectionFailed();
        }
    }

    /** @dev See {IPrincipalToken-redeem}. */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {
        _beforeRedeem(shares, owner);
        assets = IERC4626(ibt).redeem(_convertSharesToIBTs(shares, false), receiver, address(this));
        emit Redeem(owner, receiver, shares);
    }

    /** @dev See {IPrincipalToken-redeem}. */
    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        uint256 minAssets
    ) external override returns (uint256 assets) {
        assets = redeem(shares, receiver, owner);
        if (assets < minAssets) {
            revert ERC5143SlippageProtectionFailed();
        }
    }

    /** @dev See {IPrincipalToken-redeemForIBT}. */
    function redeemForIBT(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 ibts) {
        _beforeRedeem(shares, owner);
        ibts = _convertSharesToIBTs(shares, false);
        IERC20(ibt).safeTransfer(receiver, ibts);
        emit Redeem(owner, receiver, shares);
    }

    /** @dev See {IPrincipalToken-redeemForIBT}. */
    function redeemForIBT(
        uint256 shares,
        address receiver,
        address owner,
        uint256 minIbts
    ) external override returns (uint256 ibts) {
        ibts = redeemForIBT(shares, receiver, owner);
        if (ibts < minIbts) {
            revert ERC5143SlippageProtectionFailed();
        }
    }

    /** @dev See {IPrincipalToken-withdraw}. */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256 shares) {
        _beforeWithdraw(assets, owner);
        (uint256 _ptRate, uint256 _ibtRate) = _getPTandIBTRates(false);
        uint256 ibts = IERC4626(ibt).withdraw(assets, receiver, address(this));
        shares = _withdrawShares(ibts, receiver, owner, _ptRate, _ibtRate);
    }

    /** @dev See {IPrincipalToken-withdraw}. */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner,
        uint256 maxShares
    ) external override returns (uint256 shares) {
        shares = withdraw(assets, receiver, owner);
        if (shares > maxShares) {
            revert ERC5143SlippageProtectionFailed();
        }
    }

    /** @dev See {IPrincipalToken-withdrawIBT}. */
    function withdrawIBT(
        uint256 ibts,
        address receiver,
        address owner
    ) public override returns (uint256 shares) {
        _beforeWithdraw(IERC4626(ibt).previewRedeem(ibts), owner);
        (uint256 _ptRate, uint256 _ibtRate) = _getPTandIBTRates(false);
        shares = _withdrawShares(ibts, receiver, owner, _ptRate, _ibtRate);
        // send IBTs from this contract to receiver
        IERC20(ibt).safeTransfer(receiver, ibts);
    }

    /** @dev See {IPrincipalToken-withdrawIBT}. */
    function withdrawIBT(
        uint256 ibts,
        address receiver,
        address owner,
        uint256 maxShares
    ) external override returns (uint256 shares) {
        shares = withdrawIBT(ibts, receiver, owner);
        if (shares > maxShares) {
            revert ERC5143SlippageProtectionFailed();
        }
    }

    /** @dev See {IPrincipalToken-claimFees}. */
    function claimFees() external override returns (uint256 assets) {
        if (msg.sender != IRegistry(registry).getFeeCollector()) {
            revert UnauthorizedCaller();
        }
        uint256 ibts = unclaimedFeesInIBT;
        unclaimedFeesInIBT = 0;
        assets = IERC4626(ibt).redeem(ibts, msg.sender, address(this));
        emit FeeClaimed(msg.sender, ibts, assets);
    }

    /** @dev See {IPrincipalToken-updateYield}. */
    function updateYield(address _user) public override returns (uint256 updatedUserYieldInIBT) {
        (uint256 _ptRate, uint256 _ibtRate) = _updatePTandIBTRates();

        uint256 _oldIBTRateUser = ibtRateOfUser[_user];
        if (_oldIBTRateUser != _ibtRate) {
            ibtRateOfUser[_user] = _ibtRate;
        }
        uint256 _oldPTRateUser = ptRateOfUser[_user];
        if (_oldPTRateUser != _ptRate) {
            ptRateOfUser[_user] = _ptRate;
        }

        // Check for skipping yield update when the user deposits for the first time or rates decreased to 0.
        if (_oldIBTRateUser != 0) {
            updatedUserYieldInIBT = MockPrincipalTokenUtilV2._computeYield(
                _user,
                yieldOfUserInIBT[_user],
                _oldIBTRateUser,
                _ibtRate,
                _oldPTRateUser,
                _ptRate,
                yt
            );
            yieldOfUserInIBT[_user] = updatedUserYieldInIBT;
            emit YieldUpdated(_user, updatedUserYieldInIBT);
        }
    }

    /** @dev See {IPrincipalToken-claimYield}. */
    function claimYield(address _receiver) public override returns (uint256 yieldInAsset) {
        uint256 yieldInIBT = _claimYield();
        if (yieldInIBT != 0) {
            yieldInAsset = IERC4626(ibt).redeem(yieldInIBT, _receiver, address(this));
        }
    }

    /** @dev See {IPrincipalToken-claimYieldInIBT}. */
    function claimYieldInIBT(address _receiver) public override returns (uint256 yieldInIBT) {
        yieldInIBT = _claimYield();
        if (yieldInIBT != 0) {
            IERC20(ibt).safeTransfer(_receiver, yieldInIBT);
        }
    }

    /** @dev See {IPrincipalToken-beforeYtTransfer}. */
    function beforeYtTransfer(address _from, address _to) external override {
        if (msg.sender != yt) {
            revert UnauthorizedCaller();
        }
        updateYield(_from);
        updateYield(_to);
    }

    /** @dev See {IPrincipalToken-claimRewards}. */
    function claimRewards(bytes memory _data) external restricted {
        if (rewardsProxy == address(0)) {
            revert NoRewardsProxySet();
        }
        _data = abi.encodeWithSelector(IRewardsProxy(rewardsProxy).claimRewards.selector, _data);
        (bool success, ) = rewardsProxy.delegatecall(_data);
        if (!success) {
            revert ClaimRewardsFailed();
        }
    }

    /* SETTERS
     *****************************************************************************************************************/

    /** @dev See {IPrincipalToken-storeRatesAtExpiry}. */
    function storeRatesAtExpiry() public override afterExpiry {
        if (ratesAtExpiryStored) {
            revert RatesAtExpiryAlreadyStored();
        }
        ratesAtExpiryStored = true;
        // PT rate not rounded up here
        (ptRate, ibtRate) = _getCurrentPTandIBTRates(false);
        emit RatesStoredAtExpiry(ibtRate, ptRate);
    }

    /** @dev See {IPrincipalToken-setRewardsProxy}. */
    function setRewardsProxy(address _rewardsProxy) external restricted {
        // Note: address zero is allowed in order to disable the claim proxy
        emit RewardsProxyChange(rewardsProxy, _rewardsProxy);
        rewardsProxy = _rewardsProxy;
    }

    /* GETTERS
     *****************************************************************************************************************/

    /** @dev See {IPrincipalToken-previewDeposit}. */
    function previewDeposit(uint256 assets) public view override returns (uint256) {
        uint256 ibts = IERC4626(ibt).previewDeposit(assets);
        return _previewDepositIBT(ibts);
    }

    /** @dev See {IPrincipalToken-previewDepositIBT}. */
    function previewDepositIBT(uint256 ibts) external view override returns (uint256) {
        return _previewDepositIBT(ibts);
    }

    /** @dev See {IPrincipalToken-maxDeposit}. */
    function maxDeposit(address) external pure override returns (uint256) {
        return type(uint256).max - 1;
    }

    /** @dev See {IPrincipalToken-previewWithdraw}. */
    function previewWithdraw(
        uint256 assets
    ) external view override whenNotPaused returns (uint256) {
        uint256 ibts = IERC4626(ibt).previewWithdraw(assets);
        return previewWithdrawIBT(ibts);
    }

    /** @dev See {IPrincipalToken-previewWithdrawIBT}. */
    function previewWithdrawIBT(uint256 ibts) public view override whenNotPaused returns (uint256) {
        return _convertIBTsToShares(ibts, true);
    }

    /** @dev See {IPrincipalToken-maxWithdraw}.
     */
    function maxWithdraw(address owner) public view override whenNotPaused returns (uint256) {
        return convertToUnderlying(_maxBurnable(owner));
    }

    /** @dev See {IPrincipalToken-maxWithdrawIBT}.
     */
    function maxWithdrawIBT(address owner) public view override whenNotPaused returns (uint256) {
        return _convertSharesToIBTs(_maxBurnable(owner), false);
    }

    /** @dev See {IPrincipalToken-previewRedeem}. */
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        return IERC4626(ibt).previewRedeem(previewRedeemForIBT(shares));
    }

    /** @dev See {IPrincipalToken-previewRedeemForIBT}. */
    function previewRedeemForIBT(
        uint256 shares
    ) public view override whenNotPaused returns (uint256) {
        return _convertSharesToIBTs(shares, false);
    }

    /** @dev See {IPrincipalToken-maxRedeem}. */
    function maxRedeem(address owner) public view override returns (uint256) {
        return _maxBurnable(owner);
    }

    /** @dev See {IPrincipalToken-convertToPrincipal}. */
    function convertToPrincipal(uint256 underlyingAmount) external view override returns (uint256) {
        return _convertIBTsToShares(IERC4626(ibt).previewDeposit(underlyingAmount), false);
    }

    /** @dev See {IPrincipalToken-convertToUnderlying}. */
    function convertToUnderlying(uint256 principalAmount) public view override returns (uint256) {
        return IERC4626(ibt).previewRedeem(_convertSharesToIBTs(principalAmount, false));
    }

    /** @dev See {IPrincipalToken-totalAssets}. */
    function totalAssets() public view override returns (uint256) {
        return IERC4626(ibt).previewRedeem(IERC4626(ibt).balanceOf(address(this)));
    }

    /** @dev See {IERC20Metadata-decimals} */
    function decimals() public view override(IERC20Metadata, ERC20Upgradeable) returns (uint8) {
        return IERC4626(ibt).decimals();
    }

    /** @dev See {IPrincipalToken-underlying}. */
    function underlying() external view override returns (address) {
        return _asset;
    }

    /** @dev See {IPrincipalToken-maturity}. */
    function maturity() external view override returns (uint256) {
        return expiry;
    }

    /** @dev See {IPrincipalToken-getDuration}. */
    function getDuration() external view override returns (uint256) {
        return duration;
    }

    /** @dev See {IPrincipalToken-getIBT}. */
    function getIBT() external view override returns (address) {
        return ibt;
    }

    /** @dev See {IPrincipalToken-getYT}. */
    function getYT() external view override returns (address) {
        return yt;
    }

    /** @dev See {IPrincipalToken-getIBTRate}. */
    function getIBTRate() external view override returns (uint256) {
        (, uint256 _ibtRate) = _getPTandIBTRates(false);
        return _ibtRate;
    }

    /** @dev See {IPrincipalToken-getPTRate}. */
    function getPTRate() external view override returns (uint256) {
        (uint256 _ptRate, ) = _getPTandIBTRates(false);
        return _ptRate;
    }

    /** @dev See {IPrincipalToken-getIBTUnit}. */
    function getIBTUnit() external view override returns (uint256) {
        return ibtUnit;
    }

    /** @dev See {IPrincipalToken-getUnclaimedFeesInIBT}. */
    function getUnclaimedFeesInIBT() external view override returns (uint256) {
        return unclaimedFeesInIBT;
    }

    /** @dev See {IPrincipalToken-getTotalFeesInIBT}. */
    function getTotalFeesInIBT() external view override returns (uint256) {
        return totalFeesInIBT;
    }

    /** @dev See {IPrincipalToken-getCurrentYieldOfUserInIBT}. */
    function getCurrentYieldOfUserInIBT(
        address _user
    ) external view override returns (uint256 _yieldOfUserInIBT) {
        (uint256 _ptRate, uint256 _ibtRate) = _getPTandIBTRates(false);
        uint256 _oldIBTRate = ibtRateOfUser[_user];
        uint256 _oldPTRate = ptRateOfUser[_user];
        if (_oldIBTRate != 0) {
            _yieldOfUserInIBT = MockPrincipalTokenUtilV2._computeYield(
                _user,
                yieldOfUserInIBT[_user],
                _oldIBTRate,
                _ibtRate,
                _oldPTRate,
                _ptRate,
                yt
            );
            _yieldOfUserInIBT -= MockPrincipalTokenUtilV2._computeYieldFee(
                _yieldOfUserInIBT,
                registry
            );
        }
    }

    /**
     * @dev See {IERC3156FlashLender-maxFlashLoan}.
     */
    function maxFlashLoan(address _token) public view override returns (uint256) {
        if (_token != ibt) {
            return 0;
        }
        // Entire IBT balance of the contract can be borrowed
        return IERC4626(ibt).balanceOf(address(this));
    }

    /**
     * @dev See {IERC3156FlashLender-flashFee}.
     */
    function flashFee(address _token, uint256 _amount) public view override returns (uint256) {
        if (_token != ibt) revert AddressError();
        return MockPrincipalTokenUtilV2._computeFlashloanFee(_amount, registry);
    }

    /**
     * @dev See {IPrincipalToken-tokenizationFee}.
     */
    function getTokenizationFee() public view override returns (uint256) {
        return IRegistry(registry).getTokenizationFee();
    }

    /**
     * @dev See {IERC3156FlashLender-flashLoan}.
     */
    function flashLoan(
        IERC3156FlashBorrower _receiver,
        address _token,
        uint256 _amount,
        bytes calldata _data
    ) external override returns (bool) {
        if (_amount > maxFlashLoan(_token)) revert FlashLoanExceedsMaxAmount();

        uint256 fee = flashFee(_token, _amount);
        _updateFees(fee);

        // Initiate the flash loan by lending the requested IBT amount
        IERC20(ibt).safeTransfer(address(_receiver), _amount);

        // Execute the flash loan
        if (_receiver.onFlashLoan(msg.sender, _token, _amount, fee, _data) != ON_FLASH_LOAN)
            revert FlashLoanCallbackFailed();

        // Repay the debt + fee
        IERC20(ibt).safeTransferFrom(address(_receiver), address(this), _amount + fee);

        return true;
    }

    /* INTERNAL FUNCTIONS
     *****************************************************************************************************************/

    /**
     * @dev Preview the amount of shares that would be minted for a given amount (ibts) of IBT. This method is used both to preview a deposit with assets and a deposit with IBTs.
     * @param _ibts The amount of IBT to deposit
     * @return The amount of shares that would be minted
     */
    function _previewDepositIBT(
        uint256 _ibts
    ) internal view notExpired whenNotPaused returns (uint256) {
        uint256 tokenizationFee = MockPrincipalTokenUtilV2._computeTokenizationFee(
            _ibts,
            address(this),
            registry
        );

        return _convertIBTsToSharesPreview(_ibts - tokenizationFee);
    }

    /**
     * @dev Converts amount of PT shares to amount of IBT with current rates
     * @param _shares amount of shares to convert to IBTs
     * @param _roundUp true if result should be rounded up
     * @return ibts resulting amount of IBT
     */
    function _convertSharesToIBTs(
        uint256 _shares,
        bool _roundUp
    ) internal view returns (uint256 ibts) {
        (uint256 _ptRate, uint256 _ibtRate) = _getPTandIBTRates(false);
        if (_ibtRate == 0) {
            revert RateError();
        }
        ibts = _shares.mulDiv(
            _ptRate,
            _ibtRate,
            _roundUp ? Math.Rounding.Ceil : Math.Rounding.Floor
        );
    }

    /**
     * @dev Converts amount of IBT to amount of PT shares with current rates
     * @param _ibts amount of IBT to convert to shares
     * @param _roundUp true if result should be rounded up
     * @return shares resulting amount of shares
     */
    function _convertIBTsToShares(
        uint256 _ibts,
        bool _roundUp
    ) internal view returns (uint256 shares) {
        (uint256 _ptRate, uint256 _ibtRate) = _getPTandIBTRates(false);
        if (_ptRate == 0) {
            revert RateError();
        }
        shares = _ibts.mulDiv(
            _ibtRate,
            _ptRate,
            _roundUp ? Math.Rounding.Ceil : Math.Rounding.Floor
        );
    }

    /**
     * @dev Converts amount of IBT to amount of PT shares with current rates.
     * This method also rounds the result of the new PTRate computation in case of negative rate
     * @param ibts amount of IBT to convert to shares
     * @return shares resulting amount of shares
     */
    function _convertIBTsToSharesPreview(uint256 ibts) internal view returns (uint256 shares) {
        (uint256 _ptRate, uint256 _ibtRate) = _getPTandIBTRates(true); // to round up the shares, the PT rate must round down
        if (_ptRate == 0) {
            revert RateError();
        }
        shares = ibts.mulDiv(_ibtRate, _ptRate);
    }

    /**
     * @dev Updates unclaimed fees and total fees upon tokenization and yield claiming
     * @param _feesInIBT The fees in IBT currently being paid
     */
    function _updateFees(uint256 _feesInIBT) internal {
        unclaimedFeesInIBT += _feesInIBT;
        totalFeesInIBT += _feesInIBT;
    }

    /**
     * @dev Deploys a yt for this pt, called while initializing.
     * @param _name Name of the yt.
     * @param _symbol Symbol of the yt.
     * @return _yt The address of deployed yt.
     */
    function _deployYT(string memory _name, string memory _symbol) internal returns (address _yt) {
        address ytBeacon = IRegistry(registry).getYTBeacon();
        if (ytBeacon == address(0)) {
            revert BeaconNotSet();
        }
        _yt = address(
            new BeaconProxy(
                ytBeacon,
                abi.encodeWithSelector(
                    IYieldToken(address(0)).initialize.selector,
                    _name,
                    _symbol,
                    address(this)
                )
            )
        );
        emit YTDeployed(_yt);
    }

    /**
     * @dev Internal function for minting pt & yt to depositing user. Also updates yield before minting.
     * @param _ibts The amount of IBT being deposited by the user
     * @param _ptReceiver The address of the PT receiver
     * @param _ytReceiver The address of the YT receiver
     * @return shares The amount of shares being minted to the receiver
     */
    function _depositIBT(
        uint256 _ibts,
        address _ptReceiver,
        address _ytReceiver
    ) internal notExpired nonReentrant whenNotPaused returns (uint256 shares) {
        updateYield(_ytReceiver);
        uint256 tokenizationFee = MockPrincipalTokenUtilV2._computeTokenizationFee(
            _ibts,
            address(this),
            registry
        );
        _updateFees(tokenizationFee);
        shares = _convertIBTsToShares(_ibts - tokenizationFee, false);
        if (shares == 0) {
            revert RateError();
        }
        _mint(_ptReceiver, shares);
        emit Mint(msg.sender, _ptReceiver, shares);
        IYieldToken(yt).mint(_ytReceiver, shares);
    }

    /**
     * @dev Internal function for burning PT and YT. Also updates yield before burning
     * @param _ibts The amount of IBT that are withdrawn for burning shares
     * @param _receiver The addresss of the receiver of the assets
     * @param _owner The address of the owner of the shares
     * @param _ptRate The PT rate (expressed in Ray) to be used
     * @param _ibtRate The IBT rate (expressed in Ray) to be used
     * @return shares The amount of owner's shares being burned
     */
    function _withdrawShares(
        uint256 _ibts,
        address _receiver,
        address _owner,
        uint256 _ptRate,
        uint256 _ibtRate
    ) internal returns (uint256 shares) {
        if (_ptRate == 0) {
            revert RateError();
        }
        // convert ibts to shares using provided rates
        shares = _ibts.mulDiv(_ibtRate, _ptRate, Math.Rounding.Ceil);
        // burn owner's shares (YT and PT)
        if (block.timestamp < expiry) {
            IYieldToken(yt).burnWithoutUpdate(_owner, shares);
        }
        _burn(_owner, shares);
        emit Redeem(_owner, _receiver, shares);
    }

    /**
     * @dev Internal function for preparing redeems
     * @param _shares The amount of shares being redeemed
     * @param _owner The address of shares' owner
     */
    function _beforeRedeem(uint256 _shares, address _owner) internal nonReentrant whenNotPaused {
        if (_owner != msg.sender) {
            revert UnauthorizedCaller();
        }
        if (_shares > _maxBurnable(_owner)) {
            revert UnsufficientBalance();
        }
        if (block.timestamp >= expiry) {
            if (!ratesAtExpiryStored) {
                storeRatesAtExpiry();
            }
        } else {
            updateYield(_owner);
            IYieldToken(yt).burnWithoutUpdate(_owner, _shares);
        }
        _burn(_owner, _shares);
    }

    /**
     * @dev Internal function for preparing withdraw
     * @param _assets The amount of assets to withdraw
     * @param _owner The address of shares' owner
     */
    function _beforeWithdraw(uint256 _assets, address _owner) internal whenNotPaused nonReentrant {
        if (_owner != msg.sender) {
            revert UnauthorizedCaller();
        }
        if (block.timestamp >= expiry) {
            if (!ratesAtExpiryStored) {
                storeRatesAtExpiry();
            }
        } else {
            updateYield(_owner);
        }
        if (maxWithdraw(_owner) < _assets) {
            revert UnsufficientBalance();
        }
    }

    /**
     * @dev Internal function for handling the claims of caller's unclaimed yield
     * @return yieldInIBT The unclaimed yield in IBT that is about to be claimed
     */
    function _claimYield() internal returns (uint256 yieldInIBT) {
        yieldInIBT = updateYield(msg.sender);
        if (yieldInIBT == 0) {
            return 0;
        } else {
            yieldOfUserInIBT[msg.sender] = 0;
            uint256 yieldFeeInIBT = MockPrincipalTokenUtilV2._computeYieldFee(yieldInIBT, registry);
            _updateFees(yieldFeeInIBT);
            yieldInIBT -= yieldFeeInIBT;
            emit YieldClaimed(msg.sender, msg.sender, yieldInIBT);
        }
    }

    /**
     * @notice Computes the maximum amount of burnable shares for a user
     * @param _user The address of the user
     * @return maxBurnable The maximum amount of burnable shares
     */
    function _maxBurnable(address _user) internal view returns (uint256 maxBurnable) {
        if (block.timestamp >= expiry) {
            maxBurnable = balanceOf(_user);
        } else {
            uint256 ptBalance = balanceOf(_user);
            uint256 ytBalance = IYieldToken(yt).balanceOf(_user);
            maxBurnable = (ptBalance > ytBalance) ? ytBalance : ptBalance;
        }
    }

    /**
     * @dev Internal function for updating PT and IBT rates i.e. depegging PT if negative yield happened
     */
    function _updatePTandIBTRates() internal returns (uint256 _ptRate, uint256 _ibtRate) {
        if (block.timestamp >= expiry) {
            if (!ratesAtExpiryStored) {
                storeRatesAtExpiry();
            }
        }
        (_ptRate, _ibtRate) = _getPTandIBTRates(false);
        if (block.timestamp < expiry) {
            if (_ibtRate != ibtRate) {
                ibtRate = _ibtRate;
            }
            if (_ptRate != ptRate) {
                ptRate = _ptRate;
            }
        }
    }

    /**
     * @dev View function to get current IBT and PT rate
     * @param roundUpPTRate true if the ptRate resulting from mulDiv computation in case of negative rate should be rounded up
     * @return new pt and ibt rates
     */
    function _getCurrentPTandIBTRates(bool roundUpPTRate) internal view returns (uint256, uint256) {
        uint256 currentIBTRate = IERC4626(ibt).previewRedeem(ibtUnit).toRay(_assetDecimals);
        if (IERC4626(ibt).totalAssets() == 0 && IERC4626(ibt).totalSupply() != 0) {
            currentIBTRate = 0;
        }
        uint256 currentPTRate = currentIBTRate < ibtRate
            ? ptRate.mulDiv(
                currentIBTRate,
                ibtRate,
                roundUpPTRate ? Math.Rounding.Ceil : Math.Rounding.Floor
            )
            : ptRate;
        return (currentPTRate, currentIBTRate);
    }

    /**
     * @dev View function to get IBT and PT rates
     * @param roundUpPTRate true if the PTRate result from mulDiv computation in case of negative rate should be rounded up
     * @return PT and IBT rates
     */
    function _getPTandIBTRates(bool roundUpPTRate) internal view returns (uint256, uint256) {
        if (ratesAtExpiryStored) {
            return (ptRate, ibtRate);
        } else {
            return _getCurrentPTandIBTRates(roundUpPTRate);
        }
    }
}
