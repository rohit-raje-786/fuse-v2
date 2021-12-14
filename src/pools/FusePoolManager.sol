// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {FusePoolToken} from "./FusePoolToken.sol";
import {IRateModel} from "./interfaces/IRateModel.sol";

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {Auth, Authority} from "lib/solmate/src/Auth/Auth.sol";

/// @title Fuse Pool Manager
/// @author Jet Jadeja <jet@rari.capital>
/// @notice This contract serves as the risk management layer for the Fuse Pool
/// and is directly responsible for managing assets, user positions, and liquidations.
contract FusePoolManager is Auth {
    /// @notice The name of the Fuse Pool
    string public name;

    /// @notice The Fuse Pool's Symbol
    string public symbol;

    /// @notice Deploy a new FusePoolManager contract
    constructor(string memory _name, string memory _symbol) Auth(msg.sender, Authority(msg.sender)) {
        name = _name;
        symbol = _symbol;
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
        FusePoolToken fusePoolToken = new FusePoolToken(token);
        fusePoolToken.initialize(lendFactor, borrowFactor, rateModel, reserveRate, feeRate);

        return fusePoolToken;
    }
}
