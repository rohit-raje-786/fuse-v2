pragma solidity 0.8.10;

/// @title Fuse Pool Controller
/// @author Jet Jadeja <jet@rari.capital>
/// @notice This contract is used to manage the Fuse Pool. TODO: change this
contract FusePoolController {
    string public name;
    string public symbol;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }
}
