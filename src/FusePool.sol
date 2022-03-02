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

    function deposit(
        ERC20 asset,
        uint256 amount,
        bool enable
    ) external {}

    function withdraw(
        ERC20 asset,
        uint256 amount,
        bool disable
    ) external {}

    /*///////////////////////////////////////////////////////////////
                      BORROW/REPAYMENT INTERFACE
    //////////////////////////////////////////////////////////////*/

    function borrow(ERC20 asset, uint256 amount) external {}

    function repay(ERC20 asset, uint256 amount) external {}

    /*///////////////////////////////////////////////////////////////
                          FLASH BORROW INTERFACE
    //////////////////////////////////////////////////////////////*/

    function flashLoan(
        ERC20 asset,
        uint256 amount,
        bool enable
    ) external {}

    /*///////////////////////////////////////////////////////////////
                      COLLATERALIZATION INTERFACE
    //////////////////////////////////////////////////////////////*/

    mapping(address => ERC20[]) public userCollateral;
    mapping(address => mapping(ERC20 => bool)) public enabledCollateral;

    function enableAsset(ERC20 asset) public {}

    function disableAsset(ERC20 asset) public {}

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

    mapping(ERC20 => mapping(address => uint256)) internal internalBalanceUnits;
    mapping(ERC20 => uint256) internal totalInternalBalances;

    function balanceOf(ERC20 asset, address user) public view returns (uint256) {}

    function internalBalanceExchangeRate(ERC20) internal view returns (uint256) {}

    /*///////////////////////////////////////////////////////////////
                          DEBT ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    mapping(ERC20 => uint256) public cachedTotalBorrows;
    mapping(ERC20 => mapping(address => uint256)) internal internalDebtUnits;
    mapping(ERC20 => uint256) internal totalInternalDebt;

    function borrowBalance(ERC20 asset, uint256 user) public view returns (uint256) {}

    function internalDebtExchangeRate(ERC20) internal view returns (uint256) {}

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
