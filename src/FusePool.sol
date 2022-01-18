// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {ERC4626} from "solmate-next/mixins/ERC4626.sol";
import {Auth, Authority} from "solmate-next/auth/Auth.sol";

// TODO: Should not have to import ERC20 from here
import {ERC20, SafeTransferLib} from "solmate-next/utils/SafeTransferLib.sol";
import {SafeCastLib} from "solmate-next/utils/SafeCastLib.sol";
import {FixedPointMathLib} from "solmate-next/utils/FixedPointMathLib.sol";

import {FusePoolFactory} from "./FusePoolFactory.sol";

/// @title Fuse Pool
/// @author Jet Jadeja <jet@rari.capital>
/// @notice Minimal, gas optimized lending market
contract FusePool is Auth {
    using SafeCastLib for uint256;
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /*///////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The name of the Fuse Pool.
    string public name;

    /// @notice Creates a new FusePool.
    /// @dev Retrieves the pool name from the state of the FusePoolFactory.
    constructor() Auth(Auth(msg.sender).owner(), Auth(msg.sender).authority()) {
        // Retrieve the name from the FusePoolFactory
        // and set it as the name of the FusePool.
        name = FusePoolFactory(msg.sender).poolDeploymentName();
    }

    /*///////////////////////////////////////////////////////////////
                          ASSET CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Maps underlying tokens to the ERC4626 Vaults where they are held.
    mapping(ERC20 => ERC4626) public vaults;

    /// @notice Maps underlying tokens to structs containing their lend/borrow factors.
    mapping(ERC20 => Asset) public configurations;

    /// @notice Maps underlying tokens to the base units that we use when interacting with them.
    /// @dev This is 10**asset.decimals().
    mapping(ERC20 => uint256) public baseUnits;

    /// @dev Asset configuration.
    struct Asset {
        /// @notice Multiplier representing the value that one can borrow against their collateral.
        /// A value of 0.5 means that the borrower can borrow up to 50% of the value of their collateral
        /// @dev Fixed point value scaled by 1e18.
        uint256 lendFactor;
        /// @notice Multiplier representing the value that one can borrow against their borrowable value.
        /// If the collateral factor of an asset is 0.8, and the borrow factor is 0.5,
        /// while the collateral factor dictates that one can borrow 80% of the value of their collateral,
        /// since the borrow factor is 0.5, the borrower can borrow up to 50% of the value of their borrowable value.
        /// Which is the equivalent of 40% of the value of their collateral.
        /// @dev Fixed point value scaled by 1e18.
        uint256 borrowFactor;
    }

    /// @notice Emitted when a new asset is added to the FusePool.
    /// @param asset The address of the underlying token.
    /// @param vault The address of the ERC4626 vault where the underlying token is held.
    event AssetAdded(ERC20 indexed asset, ERC4626 indexed vault);

    /// @notice Adds a new asset to the FusePool.
    /// @param asset The address of the underlying token.
    /// @param vault The address of the ERC4626 vault where the underlying token is held.
    /// @param parameters The parameters of the asset.
    function addAsset(
        ERC20 asset,
        ERC4626 vault,
        Asset memory parameters
    ) external {
        // Set storage variables.
        vaults[asset] = vault;
        configurations[asset] = parameters;
        baseUnits[asset] = 10**asset.decimals();

        // Emit the event.
        emit AssetAdded(asset, vault);
    }

    /*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAW LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted after a successful deposit.
    /// @param from The address that triggered the deposit.
    /// @param asset The address of the underlying token.
    /// @param amount The amount of underlying tokens deposited.
    event Deposit(address indexed from, ERC20 indexed asset, uint256 amount);

    /// @notice Emitted after a successful withdrawal.
    /// @param from The address that triggered the withdrawal.
    /// @param asset The address of the underlying token.
    /// @param amount The amount of underlying tokens withdrew.
    event Withdraw(address indexed from, ERC20 indexed asset, uint256 amount);

    /// @notice Deposit underlying tokens into the Fuse Pool.
    /// @param asset The address of the underlying token.
    /// @param amount The amount of underlying tokens deposited.
    function deposit(ERC20 asset, uint256 amount) public {
        // Ensure the amount is valid.
        require(amount > 0, "AMOUNT_TOO_LOW");

        // Modify the internal balance of the sender.
        balances[msg.sender][asset] += amount.fdiv(exchangeRate(asset), baseUnits[asset]);

        // Transfer tokens from the user to the fToken contract.
        asset.safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @notice Withdraw underlying tokens from the Fuse Pool.
    /// @param asset The address of the underlying token.
    /// @param amount The amount of underlying tokens withdrawn.
    function withdraw(ERC20 asset, uint256 amount) public {
        // Ensure the amount is valid.
        require(amount > 0, "AMOUNT_TOO_LOW");

        // Modify the internal balance of the sender.
        // This code will fail if the sender does not have a large enough balance.
        balances[msg.sender][asset] -= amount.fdiv(exchangeRate(asset), baseUnits[asset]);

        // Transfer tokens to the user.
        asset.safeTransfer(msg.sender, amount);
    }

    /*///////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    // TODO: be more concise here
    /// @notice Maps underlying tokens to a map containing the balances of users.
    /// Since underlying balances fluctuate, the values we store don't exactly
    /// represent the underlying balances. We store user balances similarly to how fTokens
    /// store balances, however in Fuse v2, we do this internally rather than using ERC20
    /// compliant representations.
    mapping(address => mapping(ERC20 => uint256)) public balances;

    /// @notice Maps underlying tokens to a number representing the amount of internal tokens
    /// used to represent user balances. Think of this as fToken.totalSupply().
    mapping(ERC20 => uint256) public totalSupplies;

    /// @notice Returns the total amount of underlying tokens held by the Fuse Pool.
    /// @param asset The address of the underlying token.
    function totalUnderlying(ERC20 asset) public view returns (uint256) {
        // TODO: Add other methods to account for funds not in the contract.

        // Retrive the total amount of underlying held in the asset vault.
        return vaults[asset].balanceOfUnderlying(address(this));
    }

    /// @notice Returns an exchange rate between underlying tokens and
    /// the Fuse Pools internal balance values.
    function exchangeRate(ERC20 asset) public view returns (uint256) {
        // Retrieve the totalSupply of the internal balance token.
        uint256 supply = totalSupplies[asset];

        // If the totaly supply is 0, return 0.
        if (supply == 0) return baseUnits[asset];

        // Return the exchangeRate.
        return totalUnderlying(asset).fdiv(supply, baseUnits[asset]);
    }
}
