// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {FusePool, FusePoolFactory} from "../FusePoolFactory.sol";

import {Authority} from "solmate-next/auth/Auth.sol";
import {DSTestPlus} from "solmate-next/test/utils/DSTestPlus.sol";

import {MockERC4626} from "./mocks/MockERC4626.sol";
import {MockERC20} from "solmate-next/test/utils/mocks/MockERC20.sol";

/// @title Fuse Pool Factory Test Contract
contract FusePoolTest is DSTestPlus {
    // Used variables.
    FusePoolFactory factory;
    FusePool pool;

    MockERC20 underlying;
    MockERC4626 vault;

    function setUp() public {
        // Deploy contracts.
        factory = new FusePoolFactory(address(this), Authority(address(0)));
        (pool, ) = factory.deployFusePool("Test Pool");

        underlying = new MockERC20("Test Underlying", "TST", 18);
        vault = new MockERC4626(underlying, "Test Vault", "TST");
    }
}
