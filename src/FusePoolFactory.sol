// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {Auth, Authority} from "solmate-next/auth/Auth.sol";

import {FusePool} from "./FusePool.sol";

/// @title Fuse Pool Factory
/// @author Jet Jadeja <jet@rari.capital>
/// @notice Factory enabling the deployment of Fuse Pools.
contract FusePoolFactory is Auth {
    /*///////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a Vault factory.
    /// @param _owner The owner of the factory.
    /// @param _authority The Authority of the factory.
    constructor(address _owner, Authority _authority) Auth(_owner, _authority) {}

    /*///////////////////////////////////////////////////////////////
                           POOL DEPLOYMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice A counter indicating how many Fuse Pools have been deployed.
    /// @dev This is used to generate the Fuse Pool ID.
    uint256 public poolNumber;

    /// @dev The FusePool will use this variable to get its name.
    /// In the FusePool constructor, the FusePool will retrieve this value
    /// so that it can have an immutable name, without the need to pass it
    /// in the constructor.
    string public poolDeploymentName;

    /// @notice Emitted when a new Fuse Pool is deployed.
    /// @param pool The newly deployed Fuse Pool.
    /// @param deployer The address of the FusePool deployer.
    event PoolDeployed(FusePool indexed pool, address indexed deployer);

    /// @notice Deploy a new Fuse Pool.
    /// @return pool The address of the newly deployed pool.
    function deployFusePool(string memory name) external returns (FusePool pool, uint256 id) {
        // Calculate pool ID.
        uint256 id = poolNumber + 1;

        // Update state variables.
        poolNumber = id;
        poolDeploymentName = name;

        // Deploy the Fuse Pool using the CREATE2 opcode.
        pool = new FusePool{salt: bytes32(id)}();

        // Emit the event.
        emit PoolDeployed(pool, msg.sender);
    }

    /*///////////////////////////////////////////////////////////////
                           POOL RETRIEVAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the
}
