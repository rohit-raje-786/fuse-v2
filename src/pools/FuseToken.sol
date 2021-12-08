// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {Auth} from "lib/solmate/src/auth/Auth.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";

import {SafeCastLib} from "lib/solmate/src/utils/SafeCastLib.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "lib/solmate/src/utils/FixedPointMathLib.sol";

import {IRateModel} from "./interfaces/IRateModel.sol";
import {FusePoolController} from "./FusePoolController.sol";

/// @title Fuse Pool Token (fToken)
/// @author Jet Jadeja <jet@rari.capital>
/// @notice ERC20 compatible representation of balances supplied to a Fuse Pool.
contract FuseToken is ERC20, Auth {
    using SafeCastLib for uint256;
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /*///////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The address of the PoolController contract.
    FusePoolController public immutable CONTROLLER;

    /// @notice The underlying token contract address supported by the fToken.
    ERC20 public immutable UNDERLYING;

    /// @notice The base unit of the underlying token.
    /// @dev Equivalent to 10 ** decimals (used for fixed point math).
    uint256 public immutable BASE_UNIT;

    /// @notice Create a new Vault Token.
    /// @param underlying The address of the underlying ERC20 token.
    /// @param controller The address of the contract's assigned Pool controller
    constructor(ERC20 underlying, FusePoolController controller)
        ERC20(
            string(abi.encodePacked(controller.name(), underlying.name())),
            string(abi.encodePacked(controller.symbol(), underlying.symbol())),
            underlying.decimals()
        )
        Auth(Auth(msg.sender).owner(), Auth(msg.sender).authority())
    {
        // Set immutables.
        CONTROLLER = controller;
        UNDERLYING = underlying;
        BASE_UNIT = 10**underlying.decimals();

        // Prevent minting of fTokens by setting supply to 2^256 - 1.
        // If any tokens are minted, an overflow will occur.
        totalSupply = type(uint256).max;
    }

    /*///////////////////////////////////////////////////////////////
                        RATE MODEL CONFIGURATION
    //////////////////////////////////////////////////////////////*/
    /// @notice The address of the Rate Model contract.
    /// @dev The Rate Model is used to calculate supply/borrow rates.
    IRateModel public rateModel;

    /// @notice Emmited when the Rate Model is updated.
    /// @param user The authorized user who triggered the update.
    /// @param newRateModel The address of the new Rate Model.
    event RateModelUpdated(address indexed user, IRateModel indexed newRateModel);

    /// @notice Set a new Rate Model.
    /// @param newRateModel The address of the new Rate Model.
    function setNewRateModel(IRateModel newRateModel) external requiresAuth {
        // Ensure the new Rate Model is valid.
        require(newRateModel.isRateModel(), "MODEL_NOT_VALID");

        // Set the new Rate Model.
        rateModel = newRateModel;

        // Emit the event.
        emit RateModelUpdated(msg.sender, newRateModel);
    }
}
