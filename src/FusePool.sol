// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {FusePoolFactory} from "./FusePoolFactory.sol";

import {ERC20} from "solmate-next/tokens/ERC20.sol";
import {ERC4626} from "solmate-next/mixins/ERC4626.sol";
import {Auth, Authority} from "solmate-next/auth/Auth.sol";

import {PriceOracle} from "./interface/PriceOracle.sol";
import {InterestRateModel} from "./interface/InterestRateModel.sol";
import {FlashBorrower} from "./interface/FlashBorrower.sol";

import {SafeTransferLib} from "solmate-next/utils/SafeTransferLib.sol";
import {SafeCastLib} from "solmate-next/utils/SafeCastLib.sol";
import {FixedPointMathLib} from "solmate-next/utils/FixedPointMathLib.sol";

/// @title Fuse Pool
/// @author Jet Jadeja <jet@rari.capital>
/// @notice Minimal, gas optimized lending market
contract FusePool is Auth {
    using SafeTransferLib for ERC20;
    using SafeCastLib for uint256;
    using FixedPointMathLib for uint256;

    /*///////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Pool name.
    string public name;

    /// @notice Create a new Fuse Pool.
    /// @dev Retrieves the pool name from the FusePoolFactory contract.
    constructor() Auth(Auth(msg.sender).owner(), Auth(msg.sender).authority()) {
        // Retrieve the name from the factory contract.
        name = FusePoolFactory(msg.sender).poolDeploymentName();
    }

    /*///////////////////////////////////////////////////////////////
                          ORACLE CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Address of the price oracle contract.
    PriceOracle public oracle;

    /// @notice Emitted when the price oracle is changed.
    /// @param user The authorized user who triggered the change.
    /// @param newOracle The new price oracle address.
    event OracleUpdated(address indexed user, PriceOracle indexed newOracle);

    /// @notice Sets a new oracle contract.
    /// @param newOracle The address of the new oracle.
    function setOracle(PriceOracle newOracle) external requiresAuth {
        // Update the oracle.
        oracle = newOracle;

        // Emit the event.
        emit OracleUpdated(msg.sender, newOracle);
    }

    /*///////////////////////////////////////////////////////////////
                          IRM CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Maps ERC20 token addresses to their respective Interest Rate Model.
    mapping(ERC20 => InterestRateModel) public interestRateModels;

    /// @notice Emitted when an InterestRateModel is changed.
    /// @param user The authorized user who triggered the change.
    /// @param asset The underlying asset whose IRM was modified.
    /// @param newInterestRateModel The new IRM address.
    event InterestRateModelUpdated(address user, ERC20 asset, InterestRateModel newInterestRateModel);

    /// @notice Sets a new Interest Rate Model for a specfic asset.
    /// @param asset The underlying asset.
    /// @param newInterestRateModel The new IRM address.
    function setInterestRateModel(ERC20 asset, InterestRateModel newInterestRateModel) external requiresAuth {
        // Update the asset's Interest Rate Model.
        interestRateModels[asset] = newInterestRateModel;

        // Emit the event.
        emit InterestRateModelUpdated(msg.sender, asset, newInterestRateModel);
    }

    /*///////////////////////////////////////////////////////////////
                          ASSET CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Maps underlying tokens to the ERC4626 vaults where they are held.
    mapping(ERC20 => ERC4626) public vaults;

    /// @notice Maps underlying tokens to their configurations.
    mapping(ERC20 => Configuration) public configurations;

    /// @notice Maps underlying assets to their base units.
    /// 10**asset.decimals().
    mapping(ERC20 => uint256) public baseUnits;

    /// @notice Emitted when a new asset is added to the FusePool.
    /// @param user The authorized user who triggered the change.
    /// @param asset The underlying asset.
    /// @param vault The ERC4626 vault where the underlying tokens will be held.
    /// @param configuration The lend/borrow factors for the asset.
    event AssetConfigured(
        address indexed user,
        ERC20 indexed asset,
        ERC4626 indexed vault,
        Configuration configuration
    );

    /// @notice Emitted when an asset configuration is updated.
    /// @param user The authorized user who triggered the change.
    /// @param asset The underlying asset.
    /// @param newConfiguration The new lend/borrow factors for the asset.
    event AssetConfigurationUpdated(address indexed user, ERC20 indexed asset, Configuration newConfiguration);

    /// @dev Asset configuration struct.
    struct Configuration {
        uint256 lendFactor;
        uint256 borrowFactor;
    }

    /// @notice Adds a new asset to the Fuse Pool.
    /// @param asset The underlying asset.
    /// @param vault The ERC4626 vault where the underlying tokens will be held.
    /// @param configuration The lend/borrow factors for the asset.
    function configureAsset(
        ERC20 asset,
        ERC4626 vault,
        Configuration memory configuration
    ) external requiresAuth {
        // Ensure that this asset has not been configured.
        require(address(vaults[asset]) == address(0), "ASSET_ALREADY_CONFIGURED");

        // Configure the asset.
        vaults[asset] = vault;
        configurations[asset] = configuration;
        baseUnits[asset] = 10**asset.decimals();

        // Emit the event.
        emit AssetConfigured(msg.sender, asset, vault, configuration);
    }

    /// @notice Updates the lend/borrow factors of an asset.
    /// @param asset The underlying asset.
    /// @param newConfiguration The new lend/borrow factors for the asset.
    function updateConfiguration(ERC20 asset, Configuration memory newConfiguration) external requiresAuth {
        // Update the asset configuration.
        configurations[asset] = newConfiguration;

        // Emit the event.
        emit AssetConfigurationUpdated(msg.sender, asset, newConfiguration);
    }

    /*///////////////////////////////////////////////////////////////
                       DEPOSIT/WITHDRAW INTERFACE
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted after a sucessful deposit.
    /// @param from The address that triggered the deposit.
    /// @param asset The underlying asset.
    /// @param amount The amount being deposited.
    event Deposit(address indexed from, ERC20 indexed asset, uint256 amount);

    /// @notice Emitted after a successful withdrawal.
    /// @param from The address that triggered the withdrawal.
    /// @param asset The underlying asset.
    /// @param amount The amount being withdrew.
    event Withdraw(address indexed from, ERC20 indexed asset, uint256 amount);

    /// @notice Deposit underlying tokens into the Fuse Pool.
    /// @param asset The underlying asset.
    /// @param amount The amount to be deposited.
    /// @param enable A boolean indicating whether to enable the underlying asset as collateral.
    function deposit(
        ERC20 asset,
        uint256 amount,
        bool enable
    ) external {
        // Ensure the amount is valid.
        require(amount > 0, "INVALID_AMOUNT");

        // Calculate the amount of internal balance units to be stored.
        uint256 shares = amount.fdiv(internalBalanceExchangeRate(asset), baseUnits[asset]);

        // Modify the internal balance of the sender.
        internalBalances[asset][msg.sender] += shares;

        // Add to the asset's total internal supply.
        totalInternalBalances[asset] += shares;

        // Transfer underlying in from the user.
        asset.safeTransferFrom(msg.sender, address(this), amount);

        // Deposit the underlying tokens into the designated vault.
        ERC4626 vault = vaults[asset];
        asset.approve(address(vault), amount);
        vault.deposit(address(this), amount);

        // Enable the asset as collateral if `enable` is set to true.
        if (enable) enableAsset(asset);

        // Emit the event.
        emit Deposit(msg.sender, asset, amount);
    }

    /// @notice Withdraw underlying tokens from the Fuse Pool.
    /// @param asset The underlying asset.
    /// @param amount The amount to be withdrawn.
    /// @param disable A boolean indicating whether to disable the underlying asset as collateral.
    function withdraw(
        ERC20 asset,
        uint256 amount,
        bool disable
    ) external {
        // Ensure the amount is valid.
        require(amount > 0, "AMOUNT_TOO_LOW");

        // Calculate the amount of internal balance units to be subtracted.
        uint256 shares = amount.fdiv(internalBalanceExchangeRate(asset), baseUnits[asset]);

        // Modify the internal balance of the sender.
        internalBalances[asset][msg.sender] -= shares;

        // Subtract from the asset's total internal supply.
        totalInternalBalances[asset] -= shares;

        // Withdraw the underlying tokens from the designated vault.
        vaults[asset].withdraw(address(this), amount);

        // Transfer underlying to the user.
        asset.safeTransfer(msg.sender, amount);

        // If `disable` is set to true, disable the asset as collateral.
        if (disable) disableAsset(asset);

        // Emit the event.
        emit Withdraw(msg.sender, asset, amount);
    }

    /*///////////////////////////////////////////////////////////////
                      BORROW/REPAYMENT INTERFACE
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted after a successful borrow.
    /// @param from The address that triggered the borrow.
    /// @param asset The underlying asset.
    /// @param amount The amount being borrowed.
    event Borrow(address indexed from, ERC20 indexed asset, uint256 amount);

    /// @notice Emitted after a successful repayment.
    /// @param from The address that triggered the repayment.
    /// @param asset The underlying asset.
    /// @param amount The amount being repaid.
    event Repay(address indexed from, ERC20 indexed asset, uint256 amount);

    /// @notice Borrow underlying tokens from the Fuse Pool.
    /// @param asset The underlying asset.
    /// @param amount The amount to borrow.
    function borrow(ERC20 asset, uint256 amount) external {}

    /// @notice Repay underlying tokens to the Fuse Pool.
    /// @param asset The underlying asset.
    /// @param amount The amount to repay.
    function repay(ERC20 asset, uint256 amount) external {}

    /*///////////////////////////////////////////////////////////////
                          FLASH BORROW INTERFACE
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted after a successful flash borrow.
    /// @param from The address that triggered the flash borrow.
    /// @param borrower The borrower.
    event FlashBorrow(address indexed from, FlashBorrower indexed borrower, ERC20 indexed asset, uint256 amount);

    function flashBorrow(
        FlashBorrower borrower,
        bytes memory data,
        ERC20 asset,
        uint256 amount
    ) external {}

    /*///////////////////////////////////////////////////////////////
                      COLLATERALIZATION INTERFACE
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted after an asset has been collateralized.
    /// @param from The address that triggered the enablement.
    /// @param asset The underlying asset.
    event AssetEnabled(address indexed from, ERC20 indexed asset);

    /// @notice Emitted after an asset has been disabled.
    /// @param from The address that triggered the disablement.
    /// @param asset The underlying asset.
    event AssetDisabled(address indexed from, ERC20 indexed asset);

    /// @notice Maps users to an array of assets they have listed as collateral.
    mapping(address => ERC20[]) public userCollateral;

    /// @notice Maps users to a map from assets to boleans indicating whether they have listed as collateral.
    mapping(address => mapping(ERC20 => bool)) public enabledCollateral;

    /// @notice Enable an asset as collateral.
    function enableAsset(ERC20 asset) public {
        // Ensure the user has not enabled this asset as collateral.
        if (enabledCollateral[msg.sender][asset]) {
            return;
        }

        // Enable the asset as collateral.
        userCollateral[msg.sender].push(asset);
        enabledCollateral[msg.sender][asset] = true;

        // Emit the event.
        emit AssetEnabled(msg.sender, asset);
    }

    /// @notice Disable an asset as collateral.
    function disableAsset(ERC20 asset) public {
        // Ensure that the user is not borrowing this asset.
        if (internalDebt[asset][msg.sender] > 0) return;

        // Ensure the user has already enabled this asset as collateral.
        if (!enabledCollateral[msg.sender][asset]) return;

        // Remove the asset from the user's list of collateral.
        for (uint256 i = 0; i < userCollateral[msg.sender].length; i++) {
            if (userCollateral[msg.sender][i] == asset) {
                // Copy the value of the last element in the array.
                ERC20 last = userCollateral[msg.sender][userCollateral[msg.sender].length - 1];

                // Remove the last element from the array.
                delete userCollateral[msg.sender][userCollateral[msg.sender].length - 1];

                // Replace the disabled asset with the new asset.
                userCollateral[msg.sender][i] = last;
            }
        }

        // Disable the asset as collateral.
        enabledCollateral[msg.sender][asset] = false;

        // Emit the event.
        emit AssetDisabled(msg.sender, asset);
    }

    /*///////////////////////////////////////////////////////////////
                        LIQUIDITY ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the total amount of underlying tokens held by and owed to the Fuse Pool.
    /// @param asset The underlying asset.
    function totalUnderlying(ERC20 asset) public view returns (uint256) {
        // TODO: account for funds owed to the contract.

        // Return the Fuse Pool's underlying balance in the designated ERC4626 vault.
        return vaults[asset].balanceOfUnderlying(address(this));
    }

    /// @notice Returns the amount of underlying tokens held in this contract.
    /// @param asset The underlying asset.
    function availableLiquidity(ERC20 asset) public view returns (uint256) {
        // Return the Fuse Pool's underlying balance in the designated ERC4626 vault.
        return vaults[asset].balanceOfUnderlying(address(this));
    }

    /*///////////////////////////////////////////////////////////////
                        BALANCE ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev Maps assets to user addresses to their balances, which are not denominated in underlying.
    /// Instead, these values are denominated in internal balance units, which internally account
    /// for user balances, increasing in value as the Fuse Pool earns more interest.
    mapping(ERC20 => mapping(address => uint256)) internal internalBalances;

    /// @dev Maps assets to the total number of internal balance units "distributed" amongst lenders.
    mapping(ERC20 => uint256) internal totalInternalBalances;

    /// @notice Returns the underlying balance of an address.
    /// @param asset The underlying asset.
    /// @param user The user to get the underlying balance of.
    function balanceOf(ERC20 asset, address user) public view returns (uint256) {
        // Multiply the user's internal balance units by the internal exchange rate of the asset.
        return internalBalances[asset][user].fmul(internalBalanceExchangeRate(asset), baseUnits[asset]);
    }

    /// @dev Returns the exchange rate between underlying tokens and internal balance units.
    /// In other words, this function returns the value of one internal balance unit, denominated in underlying.
    function internalBalanceExchangeRate(ERC20 asset) internal view returns (uint256) {
        // Retrieve the total internal balance supply.
        uint256 totalInternalBalance = totalInternalBalances[asset];

        // If it is 0, return an exchange rate of 1.
        if (totalInternalBalance == 0) return baseUnits[asset];

        // Otherwise, divide the total supplied underlying by the total internal balance units.
        return totalUnderlying(asset).fdiv(totalInternalBalance, baseUnits[asset]);
    }

    /*///////////////////////////////////////////////////////////////
                          DEBT ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev Maps assets to the total number of underlying loaned out to borrowers.
    /// Note that these values are not updated, instead recording the total borrow amount
    /// each time a borrow/repayment occurs.
    mapping(ERC20 => uint256) internal cachedTotalBorrows;

    /// @dev Maps assets to user addresses to their debt, which are not denominated in underlying.
    /// Instead, these values are denominated in internal debt units, which internally account
    /// for user debt, increasing in value as the Fuse Pool earns more interest.
    mapping(ERC20 => mapping(address => uint256)) internal internalDebt;

    /// @dev Maps assets to the total number of internal debt units "distributed" amongst borrowers.
    mapping(ERC20 => uint256) internal totalInternalDebt;

    /// @notice Returns the total amount of underlying tokens being loaned out to borrowers.
    /// @param asset The underlying asset.
    function totalBorrows(ERC20 asset) public view returns (uint256) {}

    /// @notice Returns the underlying borrow balance of an address.
    /// @param asset The underlying asset.
    /// @param user The user to get the underlying borrow balance of.
    function borrowBalance(ERC20 asset, address user) public view returns (uint256) {
        // Multiply the user's internal debt units by the internal debt exchange rate of the asset.
        return internalDebt[asset][user].fmul(internalDebtExchangeRate(asset), baseUnits[asset]);
    }

    /// @dev Returns the exchange rate between underlying tokens and internal debt units.
    /// In other words, this function returns the value of one internal debt unit, denominated in underlying.
    function internalDebtExchangeRate(ERC20 asset) internal view returns (uint256) {
        // Retrieve the total debt balance supply.
        uint256 totalInternalDebt = totalInternalDebt[asset];

        // If it is 0, return an exchange rate of 1.
        if (totalInternalDebt == 0) return baseUnits[asset];

        // Otherwise, divide the total borrowed underlying by the total amount of internal debt units.
        return totalBorrows(asset).fdiv(totalInternalDebt, baseUnits[asset]);
    }

    /*///////////////////////////////////////////////////////////////
                      BORROW ALLOWANCE CHECKS
    //////////////////////////////////////////////////////////////*/

    /// @dev Store account liquidity details whilst avoiding stack depth errors.
    struct AccountLiquidity {
        // A user's total borrow balance in ETH.
        uint256 borrowBalance;
        // A user's maximum borrowable value. If their borrowed value
        // reaches this point, they will get liquidated.
        uint256 maximumBorrowawble;
        // A user's borrow balance in ETH multiplied by the average borrow factor.
        // TODO: need a better name for this
        uint256 borrowBalancesTimesBorrowFactors;
        // A user's actual borrowable value. If their borrowed value
        // is greater than or equal to this number, the system will
        // not allow them to borrow any more assets.
        uint256 actualBorrowable;
    }

    function canBorrow(
        ERC20 asset,
        address user,
        uint256 amount
    ) internal view returns (bool) {}
}
