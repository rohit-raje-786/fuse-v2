// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

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
}
