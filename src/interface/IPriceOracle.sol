pragma solidity 0.8.10;

import {ERC20} from "solmate/tokens/ERC20.sol";

/// @title Price Oracle Interface.
/// @author Jet Jadeja <jet@rari.capital>
interface IPriceOracle {
    /// @return The price of the given asset in terms of ETH.
    function getUnderlyingPrice(ERC20 asset) external view returns (uint256);
}
