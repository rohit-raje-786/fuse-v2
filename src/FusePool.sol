// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {Auth, Authority} from "solmate/auth/Auth.sol";

import {FusePoolFactory} from "./FusePoolFactory.sol";

/// @title Fuse Pool
/// @author Jet Jadeja <jet@rari.capital>
/// @notice Minimal, gas optimized lending market
contract FusePool is Auth {
    /*///////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The name of the Fuse Pool
    string public name;

    /// @notice Creates a new FusePool.
    /// @dev Retrieves the pool name from the state of the FusePoolFactory.
    constructor() Auth(Auth(msg.sender).owner(), Auth(msg.sender).authority()) {
        // Retrieve the name from the FusePoolFactory
        // and set it as the name of the FusePool.
        name = FusePoolFactory(msg.sender).poolDeploymentName();
    }
}
