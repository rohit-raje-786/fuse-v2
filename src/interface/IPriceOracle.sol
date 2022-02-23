pragma solidity 0.8.10;

import {ERC20} from "solmate/tokens/ERC20.sol";

/// @title Price Oracle Interface.
/// @author Jet Jadeja <jet@rari.capital>
interface IPriceOracle {
    /// @notice Get the price of an asset.
    /// @param asset The address of the underlying asset.
    /// @dev The underlying asset price is scaled by 1e18.
    function getUnderlyingPrice(ERC20 asset) external view returns (uint256);
}
