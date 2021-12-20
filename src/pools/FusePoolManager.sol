// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {FusePoolToken} from "./FusePoolToken.sol";
import {IRateModel} from "./interfaces/IRateModel.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {Auth, Authority} from "lib/solmate/src/Auth/Auth.sol";

/// @title Fuse Pool Manager
/// @author Jet Jadeja <jet@rari.capital>
/// @notice This contract serves as the risk management layer for the Fuse Pool
/// and is directly responsible for managing assets, user positions, and liquidations.
contract FusePoolManager is Auth {
    /*///////////////////////////////////////////////////////////////
                            METADATA STORAGE
    //////////////////////////////////////////////////////////////*/
    /// @notice The name of the Fuse Pool.
    string public name;

    /// @notice The symbol of the Fuse Pool.
    string public symbol;

    /// @notice Deploy a new FusePoolManager contract
    /// @param authority The address of an authority contract
    /// @param _name The name of the Fuse Pool.
    /// @param _symbol The symbol of the Fuse Pool.
    constructor(
        Authority authority,
        string memory _name,
        string memory _symbol
    ) Auth(msg.sender, authority) {
        // Set the name and symbol of the contract.
        name = _name;
        symbol = _symbol;
    }

    /*///////////////////////////////////////////////////////////////
                            ASSET CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Maps underlying tokens to the FusePoolTokens that holds them.
    mapping(ERC20 => FusePoolToken) public poolTokens;

    /// @notice Maps FusePoolTokens to structs containing
    /// its lend and borrow factors.
    mapping(FusePoolToken => Asset) public assets;

    /// @notice Maps FusePoolTokens to a boolean indicating whether it has been initialized.
    mapping(FusePoolToken => bool) public initialized;

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

    /// @notice Deploy a new FusePoolToken
    /// @param token The address of the underlying ERC20 token.
    /// @param lendFactor Multiplier representing the value that one can borrow against their collateral.
    /// @param borrowFactor Multiplier representing the value that one can borrow against their borrowable value.
    /// @param rateModel The address RateModel contract.
    /// @param reserveRate The percentage of interest that will be set aside for reserves.
    /// @param feeRate The percentage of interest that will be set aside for fees.
    function deployFuseToken(
        ERC20 token,
        uint256 lendFactor,
        uint256 borrowFactor,
        IRateModel rateModel,
        uint256 reserveRate,
        uint256 feeRate
    ) external returns (FusePoolToken) {
        // Deploy a new FusePoolToken.
        FusePoolToken fusePoolToken = new FusePoolToken(token);
        fusePoolToken.initialize(rateModel, reserveRate, feeRate);

        // Register the FusePoolToken contract.
        poolTokens[token] = fusePoolToken;
        assets[fusePoolToken] = Asset({lendFactor: lendFactor, borrowFactor: borrowFactor});
        initialized[fusePoolToken] = true;

        // Return the address of the FusePoolToken.
        return fusePoolToken;
    }

    /*///////////////////////////////////////////////////////////////
                             ORACLE CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice The address of the oracle contract.
    /// @dev If this value is not set, price-reliant methods will fail.
    IPriceOracle public priceOracle;

    /// @notice Emitted when a new price oracle is deployed.
    /// @param priceOracle The address of the new price oracle contract.
    event NewPriceOracle(IPriceOracle indexed priceOracle);

    /// @notice Set a new price oracle contract.
    /// @param newPriceOracle The address of the new price oracle contract.
    function setPriceOracle(IPriceOracle newPriceOracle) external {
        // Set the new price oracle.
        priceOracle = newPriceOracle;

        // Emit the new price oracle event.
        emit NewPriceOracle(newPriceOracle);
    }

    /*///////////////////////////////////////////////////////////////
                            BORROW/REPAY LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Maps users to an array of assets that they have currently lent/borrowed.
    /// @dev The FusePoolToken will automatically add to the list when assets are supplied/borrowed
    /// and removed when assets are returned (and the balance drops to zero).
    mapping(address => FusePoolToken[]) public userAssets;

    /// @notice Maps users to a map indicating whether they have used the assets.
    /// @dev If this value is set to true, the asset is an element in the userAssets array.
    mapping(address => mapping(FusePoolToken => bool)) public userUsedAssets;

    /// @notice Execute a borrow request.
    /// @param user The address of the borrower.
    /// @param amount The amount being borrowed.
    /// @dev Can only be called by a registered fToken.
    function executeBorrow(address user, uint256 amount) external {
        // Ensure the caller is a verified fToken.
        require(initialized[FusePoolToken(msg.sender)], "CALLER_MUST_BE_FTOKEN");

        // Ensure the asset has been added to the user's list of used assets.
        if (!userUsedAssets[user][FusePoolToken(msg.sender)]) {
            userAssets[user].push(FusePoolToken(msg.sender));
            userUsedAssets[user][FusePoolToken(msg.sender)] = true;
        }

        // Ensure that the oracle is available.
        require(address(priceOracle) != address(0), "PRICE_ORACLE_NOT_SET");
    }

    /// @notice Execute a repayment request.
    /// @param user The address of the repayer.
    /// @param amount The amount being repaid.
    /// @dev Can only be called by a registered fToken.
    function executeRepay(address user, uint256 amount) external {}
}
