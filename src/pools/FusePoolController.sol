// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {FuseToken, IRateModel} from "./FuseToken.sol";

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {Auth, Authority} from "lib/solmate/src/Auth/Auth.sol";

/// @title Fuse Pool Controller
/// @author Jet Jadeja <jet@rari.capital>
/// @notice This contract is used to manage the Fuse Pool. TODO: change this
contract FusePoolController is Auth {
    string public name;
    string public symbol;

    constructor(string memory _name, string memory _symbol) Auth(msg.sender, Authority(msg.sender)) {
        name = _name;
        symbol = _symbol;
    }

    function deployFuseToken(
        ERC20 token,
        uint256 lendFactor,
        uint256 borrowFactor,
        IRateModel rateModel,
        uint256 reserveRate,
        uint256 feeRate
    ) external returns (FuseToken) {
        FuseToken fuseToken = new FuseToken(token, this);
        fuseToken.initialize(lendFactor, borrowFactor, rateModel, reserveRate, feeRate);

        return fuseToken;
    }
}
