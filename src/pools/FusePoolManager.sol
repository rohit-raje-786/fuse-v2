// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {FusePoolToken} from "./FusePoolToken.sol";
import {IRateModel} from "./interfaces/IRateModel.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {Auth, Authority} from "lib/solmate/src/Auth/Auth.sol";
import {FixedPointMathLib} from "lib/solmate/src/utils/FixedPointMathLib.sol";

/// @title Fuse Pool Manager
/// @author Jet Jadeja <jet@rari.capital>
/// @notice This contract serves as the risk management layer for the Fuse Pool
/// and is directly responsible for managing assets, user positions, and liquidations.
contract FusePoolManager is Auth {
    using FixedPointMathLib for uint256;

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

    /// @notice Emitted when a new FusePoolToken is deployed.
    /// @param deployer The address of the contract deployer.
    /// @param token The address of the FusePoolToken that was deployed.
    event NewFusePoolToken(address indexed deployer, FusePoolToken indexed token);

    /// @notice Deploy a new FusePoolToken
    /// @param token The address of the underlying ERC20 token.
    /// @param lendFactor Multiplier representing the value that one can borrow against their collateral.
    /// @param borrowFactor Multiplier representing the value that one can borrow against their borrowable value.
    /// @param rateModel The address RateModel contract.
    /// @param reserveRate The percentage of interest that will be set aside for reserves.
    /// @param feeRate The percentage of interest that will be set aside for fees.
    function deployFusePoolToken(
        ERC20 token,
        uint256 lendFactor,
        uint256 borrowFactor,
        IRateModel rateModel,
        uint256 reserveRate,
        uint256 feeRate
    ) external requiresAuth returns (FusePoolToken) {
        // Deploy a new FusePoolToken.
        FusePoolToken fusePoolToken = new FusePoolToken(token);
        fusePoolToken.initialize(rateModel, reserveRate, feeRate);

        // Register the FusePoolToken contract.
        poolTokens[token] = fusePoolToken;
        assets[fusePoolToken] = Asset({lendFactor: lendFactor, borrowFactor: borrowFactor});
        initialized[fusePoolToken] = true;

        // Emit the NewFusePoolToken event.
        emit NewFusePoolToken(msg.sender, fusePoolToken);

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
                            USER ASSET LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Maps users to an array of assets that they have currently lent/borrowed.
    /// @dev The FusePoolToken will automatically add to the list when assets are supplied/borrowed
    /// and removed when assets are returned (and the balance drops to zero).
    mapping(address => FusePoolToken[]) public userCollateral;

    /// @notice Maps users to a map indicating whether they have used the assets.
    /// @dev If this value is set to true, the asset is an element in the userCollateral array.
    mapping(address => mapping(FusePoolToken => bool)) public userEnabledCollateral;

    /// @notice Emitted when a new asset is added for a certain user.
    /// @param user The address of the user.
    /// @param asset The address of the fToken representing the asset.
    // TODO: rename this
    event NewUserCollateral(address indexed user, FusePoolToken indexed asset);

    /// @notice Add asset to a user's list of used assets.
    /// @param user The address of the user enabling the collateral.
    /// @dev This function can only be called by a valid fToken contract.
    function enableUserCollateral(address user) external {
        // Ensure that the caller is a verified fToken.
        require(initialized[FusePoolToken(msg.sender)], "CALLER_MUST_BE_FTOKEN");

        // Add the asset to the user's list of used assets.
        addCollateral(user, FusePoolToken(msg.sender));
    }

    /// @notice Enable an asset as collateral for the sender.
    /// @param asset The address of the fToken representing the underlying asset.
    function enableCollateral(FusePoolToken asset) external {
        addCollateral(msg.sender, asset);
    }

    /// @notice Remove asset from the sender's list of used assets.
    /// @param asset The address of the fToken representing the asset being removed.
    /// @dev If the asset is not in the user's list, this function will simply return.
    function removeAsset(FusePoolToken asset) external {
        // Ensure that the asset is not being borrowed. If a user removes an
        // asset that is being borrowed from their array, they're borrow balance for that asset
        // will not be accounted for..
        require(asset.borrowBalance(msg.sender) == 0, "ASSET_IS_BEING_BORROWED");

        // Remove the asset from the user's list of used assets.
        userEnabledCollateral[msg.sender][asset] = false;

        // Remove the asset from the user's usedAssets array.
        uint256 index;

        // TODO: Gas optimizations
        // We need to iterate over the array to find the index of the asset.
        for (; index < userCollateral[msg.sender].length; index++) {
            if (userCollateral[msg.sender][index] == asset) break;
        }

        // TODO: Optimizations :D
        userCollateral[msg.sender][index] = userCollateral[msg.sender][userCollateral[msg.sender].length - 1];
        userCollateral[msg.sender].pop();
    }

    /// @dev Internal method to add a new asset to the user's list of assets.
    /// @param user The address of the user.
    /// @param asset The address of the fToken representing the asset.
    function addCollateral(address user, FusePoolToken asset) internal {
        if (userEnabledCollateral[user][asset]) return;

        // Add the asset to the user's list of used assets.
        userEnabledCollateral[user][asset] = true;
        userCollateral[user].push(asset);

        // Emit the new asset event.
        emit NewUserCollateral(user, asset);
    }

    /*///////////////////////////////////////////////////////////////
                            BORROW/REPAY LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Execute a borrow request.
    /// @param user The address of the borrower.
    /// @param amount The amount being borrowed.
    /// @dev Can only be called by a registered fToken.
    function executeBorrow(address user, uint256 amount) external {
        // Ensure that the caller is a verified fToken.
        require(initialized[FusePoolToken(msg.sender)], "CALLER_MUST_BE_FTOKEN");

        // Ensure the asset has been added to the user's list of used assets.
        if (!userEnabledCollateral[user][FusePoolToken(msg.sender)]) {
            userCollateral[user].push(FusePoolToken(msg.sender));
            userEnabledCollateral[user][FusePoolToken(msg.sender)] = true;

            // Emit the new asset event.
            emit NewUserCollateral(user, FusePoolToken(msg.sender));
        }

        // Ensure that the oracle is available.
        require(address(priceOracle) != address(0), "PRICE_ORACLE_NOT_SET");
    }

    /// @notice Execute a repayment request.
    /// @param user The address of the repayer.
    /// @param amount The amount being repaid.
    /// @dev Can only be called by a registered fToken.
    function executeRepay(address user, uint256 amount) external {}

    /*///////////////////////////////////////////////////////////////
                   HYPOTHETICAL LIQUIDITY CALCULATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Identify whether a borrow/repayment can occur.
    /// @param user The address of the user.
    /// @param token The address of the fToken representing the asset.
    /// @param borrowAmount The amount being borrowed.
    /// @param repayAmount The amount being repaid.
    /// @return The user's hypothetical liquidity.
    function borrowAllowed(
        address user,
        FusePoolToken token,
        uint256 borrowAmount,
        uint256 repayAmount
    ) internal view returns (bool, uint256) {
        // Store the user's supplied and borrowed assets in memory.
        FusePoolToken[] memory enteredAssets = userCollateral[user];

        // Represents the user's total borrowable balance in ETH.
        // This only takes in the value of the user's collateral.
        uint256 borrowableBalance;

        // Represents the user's already-borrowed balance in ETH.
        uint256 borrowBalance;

        // TODO: Gas optimizations
        // Iterate over the user's supplied assets.
        for (uint256 i = 0; i < enteredAssets.length; i++) {
            // Store the asset in memory.
            FusePoolToken asset = enteredAssets[i];

            //TODO: store underlying price in memory

            // Retrieve user's underlying balance and multiply it by the asset's lend factor
            // to calculate the amount of underlying that can be borrowed against.
            uint256 borrowable = asset.balanceOfUnderlying(user).fmul(assets[asset].lendFactor, 1e18);

            // Convert the borrowable value to ETH and add it to the borrowable balance.
            // This is done by multiplying the borrowable value by the asset's underlying price.
            borrowableBalance += borrowable.fmul(priceOracle.getUnderlyingPrice(asset), asset.BASE_UNIT());

            // Convert the user's borrow balance to ETH and add it to the borrowable balance.
            borrowBalance += asset.borrowBalance(user).fmul(priceOracle.getUnderlyingPrice(asset), asset.BASE_UNIT());

            // Add/subtract the borrow/repay amounts to/from the borrow balance.
            if (asset == token) {
                // Add the borrow amount to the user's borrow balance.
                borrowBalance += borrowAmount.fmul(priceOracle.getUnderlyingPrice(asset), asset.BASE_UNIT());

                // Subtract the repay amount from the user's borrow balance.
                borrowBalance -= repayAmount.fmul(priceOracle.getUnderlyingPrice(asset), asset.BASE_UNIT());
            }
        }
    }
}
