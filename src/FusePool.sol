// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {FusePoolFactory} from "./FusePoolFactory.sol";

import {ERC20} from "solmate-next/tokens/ERC20.sol";
import {ERC4626} from "solmate-next/mixins/ERC4626.sol";
import {Auth, Authority} from "solmate-next/auth/Auth.sol";

import {PriceOracle} from "./interface/PriceOracle.sol";
import {InterestRateModel} from "./interface/InterestRateModel.sol";

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
    /// @param asset The address of the underlying token whose IRM was modified.
    /// @param newInterestRateModel The new IRM address.
    event InterestRateModelUpdated(address user, ERC20 asset, InterestRateModel newInterestRateModel);

    /// @notice Sets a new Interest Rate Model for a specfic asset.
    /// @param asset The address of the underlying token.
    /// @param newInterestRateModel The new IRM address.
    function setInterestRateModel(ERC20 asset, InterestRateModel newInterestRateModel) external requiresAuth {
        // Update the asset's Interest Rate Model.
        interestRateModels[asset] = newInterestRateModel;

        // Emit the event.
        emit InterestRateModelUpdated(msg.sender, asset, newInterestRateModel);
    }
}
