// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {Auth, Authority} from "solmate-next/auth/Auth.sol";
import {ERC20, ERC4626} from "solmate-next/mixins/ERC4626.sol";

import {FusePoolFactory} from "./FusePoolFactory.sol";

/// @title Fuse Pool
/// @author Jet Jadeja <jet@rari.capital>
/// @notice Minimal, gas optimized lending market
contract FusePool is Auth {
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
    mapping(ERC20 => ERC4626) public poolVaults;

    /// @notice Maps underlying tokens to structs containing their lend/borrow factors.
    mapping(ERC20 => Asset) public poolFactors;

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
    /// @param asset s
    /// @param vault s
    /// @param parameters s
    function addAsset(
        ERC20 asset,
        ERC4626 vault,
        Asset memory parameters
    ) external {
        // Set storage variables.
        poolVaults[asset] = vault;
        poolFactors[asset] = parameters;

        // Emit the event.
        emit AssetAdded(asset, vault);
    }
}
