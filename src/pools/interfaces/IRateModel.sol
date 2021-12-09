// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

/// @title Interest Rate Model Interface
/// @author Jet Jadeja <jet@rari.capital>
interface IRateModel {
    /// @notice Calculate the current borrow interest rate per block.
    function getBorrowRate(uint256, uint256, uint256) external view returns (uint256);

    /// @notice Calculate the current supply interest per block. 
    function getSupplyRate(uint256, uint256, uint256) external view returns (uint256);
}