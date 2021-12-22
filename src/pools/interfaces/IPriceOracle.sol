//SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {FusePoolToken} from "../FusePoolToken.sol";

/// @title Price Oracle Interface
/// @author Jet Jadeja <jet@rari.capital>
/// @notice Oracle that enables us to retrieve the price of any asset.
interface IPriceOracle {
    /// @notice Get the price of an asset.
    /// @param fToken The fToken to get the underlying price of.
    /// @dev The underlying asset price is scaled by 1e18. 
    /// A value of zero means the price is not available.
    function getUnderlyingPrice(FusePoolToken fToken) external view returns (uint256);
}