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

import "../libraries/PrincipalTokenUtil.sol";
import "../libraries/NamingUtil.sol";
import "../libraries/RayMath.sol";
import "../interfaces/IRegistry.sol";
import "../interfaces/IPrincipalToken.sol";
import "../interfaces/IYieldToken.sol";
import "../interfaces/IRewardsProxy.sol";

/**
 * @title PrincipalToken contract
 * @author Spectra Finance
 * @notice A PrincipalToken (PT) is an ERC5095 vault that allows user to tokenize their yield in a permissionless manner.
 * The shares of the vaults are composed by PT/YT pairs. These are always minted at same times and amounts upon deposits.
 * Until expiry burning shares necessitates to burn both tokens. At expiry, burning PTs is sufficient.
 */
contract PrincipalToken is
    ERC20PermitUpgradeable,
    AccessManagedUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    IPrincipalToken
{
    using SafeERC20 for IERC20;
    using PrincipalTokenUtil for address;
    using PrincipalTokenUtil for uint256;
    using RayMath for uint256;
    using Math for uint256;

    /** @dev minimum allowed decimals for underlying and IBT */
    uint256 private constant MIN_DECIMALS = 6;
    /** @dev maximum allowed decimals for underlying and IBT */
    uint256 private constant MAX_DECIMALS = 18;
    /** @dev Rates At Expiry not stored */
    uint256 private constant RAE_NOT_STORED = 0;
    /** @dev Rates At Expiry stored */
    uint256 private constant RAE_STORED = 1;
    /** @dev expected return value from borrowers onFlashLoan function */
    bytes32 private constant ON_FLASH_LOAN = keccak256("ERC3156FlashBorrower.onFlashLoan");

    /** @notice registry of the protocol */
    address private immutable registry;

    /** @notice rewards proxy for this specific instance of PT */
    address private rewardsProxy;

    /** @dev decimals of the IBT */
    uint8 private ibtDecimals;
    /** @dev decimals of the underlying asset */
    uint8 private underlyingDecimals;

    /** @notice Interest Bearing Token 4626 held by this PT vault */
    address private ibt;
    /** @notice underlying asset of this PT vault (which is also the underlying of the IBT 4626) */
    address private underlying_;
    /** @notice YT corresponding to this PT, deployed at initialization */
    address private yt;
    /** @dev represents one unit of the IBT held by this PT vault (10^decimals) */
    uint256 private ibtUnit;

    /** @dev PT price in asset (in Ray) */
    uint256 private ptRate;
    /** @dev IBT price in asset (in Ray) */
    uint256 private ibtRate;
    /** @dev unclaimed fees */
    uint256 private unclaimedFeesInIBT;
    /** @dev total fees */
    uint256 private totalFeesInIBT;
    /** @dev date of maturity (set at initialization) */
    uint256 private expiry;
    /** @dev duration to maturity */
    uint256 private duration;
    /** @dev uint256 flag acting as a boolean to track whether PT and IBT rates have been stored after expiry */
    uint256 private ratesAtExpiryStored;

    /** @dev stores each user's IBT rate (in Ray) */
    mapping(address user => uint256 lastIBTRate) private ibtRateOfUser;
    /** @dev stores each user's PT rate (in Ray) */
    mapping(address user => uint256 lastPTRate) private ptRateOfUser;
    /** @dev stores each user's yield generated from YTs */
    mapping(address user => uint256 yieldInIBT) private yieldOfUserInIBT;

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

    /** @notice Ensures the current block timestamp is before expiry */
    modifier notExpired() virtual {
        if (block.timestamp >= expiry) {
            revert PTExpired();
        }
        _;
    }

    /** @notice Ensures the current block timestamp is at or after expiry */
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
     * it deploys yt and initializes values of required variables
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
        duration = _duration;
        uint256 _expiry = _duration + block.timestamp;
        expiry = _expiry;
        string memory _ibtSymbol = IERC4626(_ibt).symbol();
        string memory _name = NamingUtil.genPTName(_ibtSymbol, _expiry);
        __ERC20_init(_name, NamingUtil.genPTSymbol(_ibtSymbol, _expiry));
        __ERC20Permit_init(_name);
        __Pausable_init();
        __ReentrancyGuard_init();
        __AccessManaged_init(_initialAuthority);
        underlying_ = IERC4626(_ibt).asset();
        uint8 _underlyingDecimals = underlying_.tryGetTokenDecimals();
        uint8 _ibtDecimals = IERC4626(_ibt).decimals();
        if (
            _underlyingDecimals < MIN_DECIMALS ||
            _underlyingDecimals > _ibtDecimals ||
            _ibtDecimals > MAX_DECIMALS
        ) {
            revert InvalidDecimals();
        }
        underlyingDecimals = _underlyingDecimals;
        ibtDecimals = _ibtDecimals;
        ibt = _ibt;
        ibtUnit = 10 ** _ibtDecimals;
        ibtRate = IERC4626(_ibt).previewRedeem(ibtUnit).toRay(_underlyingDecimals);
        ptRate = RayMath.RAY_UNIT;
        yt = _deployYT(
            NamingUtil.genYTName(_ibtSymbol, _expiry),
            NamingUtil.genYTSymbol(_ibtSymbol, _expiry)
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
    ) public override nonReentrant returns (uint256 shares) {
        address _ibt = ibt;
        address _underlying = underlying_;
        IERC20(_underlying).safeTransferFrom(msg.sender, address(this), assets);
        IERC20(_underlying).safeIncreaseAllowance(_ibt, assets);
        uint256 ibts = IERC4626(_ibt).deposit(assets, address(this));
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
    ) public override nonReentrant returns (uint256 shares) {
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
    ) public override nonReentrant returns (uint256 assets) {
        _beforeRedeem(shares, owner);
        emit Redeem(owner, receiver, shares);
        assets = IERC4626(ibt).redeem(_convertSharesToIBTs(shares, false), receiver, address(this));
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
    ) public override nonReentrant returns (uint256 ibts) {
        _beforeRedeem(shares, owner);
        ibts = _convertSharesToIBTs(shares, false);
        emit Redeem(owner, receiver, shares);
        if (ibts != 0) {
            IERC20(ibt).safeTransfer(receiver, ibts);
        }
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
    ) public override nonReentrant returns (uint256 shares) {
        _beforeWithdraw(assets, owner);
        (uint256 _ptRate, uint256 _ibtRate) = _getPTandIBTRates(false);
        uint256 ibts = IERC4626(ibt).withdraw(assets, receiver, address(this));
        shares = _burnSharesForWithdraw(ibts, receiver, owner, _ptRate, _ibtRate);
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
    ) public override nonReentrant returns (uint256 shares) {
        address _ibt = ibt;
        _beforeWithdraw(IERC4626(_ibt).previewRedeem(ibts), owner);
        (uint256 _ptRate, uint256 _ibtRate) = _getPTandIBTRates(false);
        shares = _burnSharesForWithdraw(ibts, receiver, owner, _ptRate, _ibtRate);
        // send IBTs from this contract to receiver
        IERC20(_ibt).safeTransfer(receiver, ibts);
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
    function claimFees(
        uint256 _minAssets
    ) external override whenNotPaused returns (uint256 assets) {
        if (msg.sender != IRegistry(registry).getFeeCollector()) {
            revert UnauthorizedCaller();
        }
        uint256 ibts = unclaimedFeesInIBT;
        unclaimedFeesInIBT = 0;
        emit FeeClaimed(msg.sender, ibts, assets);
        assets = IERC4626(ibt).redeem(ibts, msg.sender, address(this));
        if (_minAssets > assets) {
            revert ERC5143SlippageProtectionFailed();
        }
    }

    /** @dev See {IPrincipalToken-updateYield}. */
    function updateYield(
        address _user
    ) public override whenNotPaused returns (uint256 updatedUserYieldInIBT) {
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
            updatedUserYieldInIBT = _user.computeYield(
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
    function claimYield(
        address _receiver,
        uint256 _minAssets
    ) public override returns (uint256 yieldInAsset) {
        uint256 yieldInIBT = _claimYield();
        emit YieldClaimed(msg.sender, _receiver, yieldInIBT);
        if (yieldInIBT != 0) {
            yieldInAsset = IERC4626(ibt).redeem(yieldInIBT, _receiver, address(this));
        }
        if (_minAssets > yieldInAsset) {
            revert ERC5143SlippageProtectionFailed();
        }
    }

    /** @dev See {IPrincipalToken-claimYieldInIBT}. */
    function claimYieldInIBT(
        address _receiver,
        uint256 _minIBT
    ) public override returns (uint256 yieldInIBT) {
        yieldInIBT = _claimYield();
        if (_minIBT > yieldInIBT) {
            revert ERC5143SlippageProtectionFailed();
        }
        emit YieldClaimed(msg.sender, _receiver, yieldInIBT);
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
    function claimRewards(bytes memory _data) external restricted whenNotPaused {
        address _rewardsProxy = rewardsProxy;
        if (_rewardsProxy == address(0) || _rewardsProxy.code.length == 0) {
            revert NoRewardsProxy();
        }
        bytes memory _data2 = abi.encodeCall(IRewardsProxy(address(0)).claimRewards, (_data));
        (bool success, ) = _rewardsProxy.delegatecall(_data2);
        if (!success) {
            revert ClaimRewardsFailed();
        }
    }

    /** @dev See {IERC3156FlashLender-flashLoan}. */
    function flashLoan(
        IERC3156FlashBorrower _receiver,
        address _token,
        uint256 _amount,
        bytes calldata _data
    ) external override whenNotPaused returns (bool) {
        if (_amount > maxFlashLoan(_token)) revert FlashLoanExceedsMaxAmount();

        uint256 fee = flashFee(_token, _amount);
        _updateFees(fee);

        // Initiate the flash loan by lending the requested IBT amount
        address _ibt = ibt;
        IERC20(_ibt).safeTransfer(address(_receiver), _amount);

        // Execute the flash loan
        if (_receiver.onFlashLoan(msg.sender, _token, _amount, fee, _data) != ON_FLASH_LOAN)
            revert FlashLoanCallbackFailed();

        // Repay the debt + fee
        IERC20(_ibt).safeTransferFrom(address(_receiver), address(this), _amount + fee);

        return true;
    }

    /* SETTERS
     *****************************************************************************************************************/

    /** @dev See {IPrincipalToken-storeRatesAtExpiry}. */
    function storeRatesAtExpiry() public override afterExpiry whenNotPaused {
        if (ratesAtExpiryStored == RAE_STORED) {
            revert RatesAtExpiryAlreadyStored();
        }
        ratesAtExpiryStored = RAE_STORED;
        // PT rate not rounded up here
        (uint256 _ptRate, uint256 _ibtRate) = _getCurrentPTandIBTRates(false);
        ptRate = _ptRate;
        ibtRate = _ibtRate;
        emit RatesStoredAtExpiry(_ibtRate, _ptRate);
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
    function previewDeposit(uint256 assets) external view override returns (uint256) {
        uint256 ibts = IERC4626(ibt).previewDeposit(assets);
        return previewDepositIBT(ibts);
    }

    /** @dev See {IPrincipalToken-previewDepositIBT}. */
    function previewDepositIBT(
        uint256 ibts
    ) public view override notExpired whenNotPaused returns (uint256) {
        uint256 tokenizationFee = ibts._computeTokenizationFee(address(this), registry);
        return _convertIBTsToSharesPreview(ibts - tokenizationFee);
    }

    /** @dev See {IPrincipalToken-maxDeposit}. */
    function maxDeposit(address /* receiver */) external view override returns (uint256) {
        return paused() || (block.timestamp >= expiry) ? 0 : type(uint256).max;
    }

    /** @dev See {IPrincipalToken-previewWithdraw}. */
    function previewWithdraw(uint256 assets) external view override returns (uint256) {
        uint256 ibts = IERC4626(ibt).previewWithdraw(assets);
        return previewWithdrawIBT(ibts);
    }

    /** @dev See {IPrincipalToken-previewWithdrawIBT}. */
    function previewWithdrawIBT(uint256 ibts) public view override whenNotPaused returns (uint256) {
        return _convertIBTsToShares(ibts, true);
    }

    /** @dev See {IPrincipalToken-maxWithdraw}.
     */
    function maxWithdraw(address owner) public view override returns (uint256) {
        return paused() ? 0 : convertToUnderlying(_maxBurnable(owner));
    }

    /** @dev See {IPrincipalToken-maxWithdrawIBT}.
     */
    function maxWithdrawIBT(address owner) public view override returns (uint256) {
        return paused() ? 0 : _convertSharesToIBTs(_maxBurnable(owner), false);
    }

    /** @dev See {IPrincipalToken-previewRedeem}. */
    function previewRedeem(uint256 shares) external view override returns (uint256) {
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
        return paused() ? 0 : _maxBurnable(owner);
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
        address _ibt = ibt;
        return IERC4626(_ibt).previewRedeem(IERC4626(_ibt).balanceOf(address(this)));
    }

    /** @dev See {IERC20Metadata-decimals} */
    function decimals() public view override(IERC20Metadata, ERC20Upgradeable) returns (uint8) {
        return ibtDecimals;
    }

    /** @dev See {IPrincipalToken-paused}. */
    function paused() public view override(IPrincipalToken, PausableUpgradeable) returns (bool) {
        return super.paused();
    }

    /** @dev See {IPrincipalToken-maturity}. */
    function maturity() external view override returns (uint256) {
        return expiry;
    }

    /** @dev See {IPrincipalToken-getDuration}. */
    function getDuration() external view override returns (uint256) {
        return duration;
    }

    /** @dev See {IPrincipalToken-underlying}. */
    function underlying() external view override returns (address) {
        return underlying_;
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
        uint256 _oldIBTRate = ibtRateOfUser[_user];
        if (_oldIBTRate != 0) {
            (uint256 _ptRate, uint256 _ibtRate) = _getPTandIBTRates(false);
            uint256 _oldPTRate = ptRateOfUser[_user];
            _yieldOfUserInIBT = _user.computeYield(
                yieldOfUserInIBT[_user],
                _oldIBTRate,
                _ibtRate,
                _oldPTRate,
                _ptRate,
                yt
            );
            _yieldOfUserInIBT = _yieldOfUserInIBT - _yieldOfUserInIBT._computeYieldFee(registry);
        }
    }

    /** @dev See {IERC3156FlashLender-maxFlashLoan}. */
    function maxFlashLoan(address _token) public view override returns (uint256) {
        address _ibt = ibt;
        if (_token != _ibt) {
            return 0;
        }
        // Entire IBT balance of the contract can be borrowed
        return IERC4626(_ibt).balanceOf(address(this));
    }

    /** @dev See {IERC3156FlashLender-flashFee}. */
    function flashFee(address _token, uint256 _amount) public view override returns (uint256) {
        if (_token != ibt) revert AddressError();
        return _amount._computeFlashloanFee(registry);
    }

    /** @dev See {IPrincipalToken-tokenizationFee}. */
    function getTokenizationFee() public view override returns (uint256) {
        return IRegistry(registry).getTokenizationFee();
    }

    /* INTERNAL FUNCTIONS
     *****************************************************************************************************************/

    /**
     * @dev See {ERC20Upgradeable-_update}.
     * @dev The contract must not be paused.
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal virtual override whenNotPaused {
        super._update(from, to, value);
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
        // to round up the shares, the PT rate must round down
        (uint256 _ptRate, uint256 _ibtRate) = _getPTandIBTRates(true);
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
        unclaimedFeesInIBT = unclaimedFeesInIBT + _feesInIBT;
        totalFeesInIBT = totalFeesInIBT + _feesInIBT;
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
                abi.encodeCall(IYieldToken(address(0)).initialize, (_name, _symbol, address(this)))
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
    ) internal notExpired returns (uint256 shares) {
        updateYield(_ytReceiver);
        uint256 tokenizationFee = _ibts._computeTokenizationFee(address(this), registry);
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
     * @dev Internal function for preparing redeem and burning PT:YT shares.
     * @param _shares The amount of shares being redeemed
     * @param _owner The address of shares' owner
     */
    function _beforeRedeem(uint256 _shares, address _owner) internal {
        if (_owner != msg.sender) {
            _spendAllowance(_owner, msg.sender, _shares);
        }
        if (_shares > _maxBurnable(_owner)) {
            revert InsufficientBalance();
        }
        if (block.timestamp >= expiry) {
            if (ratesAtExpiryStored == RAE_NOT_STORED) {
                storeRatesAtExpiry();
            }
        } else {
            updateYield(_owner);
            IYieldToken(yt).burnWithoutYieldUpdate(_owner, msg.sender, _shares);
        }
        _burn(_owner, _shares);
    }

    /**
     * @dev Internal function for preparing withdraw.
     * @param _assets The amount of assets to withdraw
     * @param _owner The address of shares' owner
     */
    function _beforeWithdraw(uint256 _assets, address _owner) internal {
        if (block.timestamp >= expiry) {
            if (ratesAtExpiryStored == RAE_NOT_STORED) {
                storeRatesAtExpiry();
            }
        } else {
            updateYield(_owner);
        }
        if (_assets > maxWithdraw(_owner)) {
            revert InsufficientBalance();
        }
    }

    /**
     * @dev Internal function for burning PT and YT as part of withdrawal process.
     * @param _ibts The amount of IBT that are withdrawn for burning shares
     * @param _receiver The addresss of the receiver of the assets
     * @param _owner The address of the owner of the shares
     * @param _ptRate The PT rate (expressed in Ray) to be used
     * @param _ibtRate The IBT rate (expressed in Ray) to be used
     * @return shares The amount of burnt owner's shares
     */
    function _burnSharesForWithdraw(
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
        if (_owner != msg.sender) {
            _spendAllowance(_owner, msg.sender, shares);
        }
        // burn owner's shares (YT and PT)
        if (block.timestamp < expiry) {
            IYieldToken(yt).burnWithoutYieldUpdate(_owner, msg.sender, shares);
        }
        _burn(_owner, shares);
        emit Redeem(_owner, _receiver, shares);
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
            uint256 yieldFeeInIBT = yieldInIBT._computeYieldFee(registry);
            _updateFees(yieldFeeInIBT);
            yieldInIBT = yieldInIBT - yieldFeeInIBT;
        }
    }

    /**
     * @dev Computes the maximum amount of burnable shares for a user
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
     * @return _ptRate The new PT rate
     * @return _ibtRate The new IBT rate
     */
    function _updatePTandIBTRates() internal returns (uint256 _ptRate, uint256 _ibtRate) {
        uint256 _expiry = expiry;
        if (block.timestamp >= _expiry) {
            if (ratesAtExpiryStored == RAE_NOT_STORED) {
                storeRatesAtExpiry();
            }
        }
        (_ptRate, _ibtRate) = _getPTandIBTRates(false);
        if (block.timestamp < _expiry) {
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
     * @param roundUpPTRate true if the ptRate resulting from mulDiv computation in case of negative rate should
     * be rounded up
     * @return _ptRate The new PT rate
     * @return _ibtRate The new IBT rate
     */
    function _getCurrentPTandIBTRates(
        bool roundUpPTRate
    ) internal view returns (uint256 _ptRate, uint256 _ibtRate) {
        address _ibt = ibt;
        _ibtRate = IERC4626(_ibt).previewRedeem(ibtUnit).toRay(underlyingDecimals);
        if (IERC4626(_ibt).totalAssets() == 0 && IERC4626(_ibt).totalSupply() != 0) {
            _ibtRate = 0;
        }
        _ptRate = _ibtRate < ibtRate
            ? ptRate.mulDiv(
                _ibtRate,
                ibtRate,
                roundUpPTRate ? Math.Rounding.Ceil : Math.Rounding.Floor
            )
            : ptRate;
    }

    /**
     * @dev View function to get IBT and PT rates
     * @param roundUpPTRate true if the PTRate result from mulDiv computation in case of negative rate should
     * be rounded up
     * @return _ptRate The new PT rate
     * @return _ibtRate The new IBT rate
     */
    function _getPTandIBTRates(
        bool roundUpPTRate
    ) internal view returns (uint256 _ptRate, uint256 _ibtRate) {
        if (ratesAtExpiryStored == RAE_NOT_STORED) {
            (_ptRate, _ibtRate) = _getCurrentPTandIBTRates(roundUpPTRate);
        } else {
            (_ptRate, _ibtRate) = (ptRate, ibtRate);
        }
    }
}
