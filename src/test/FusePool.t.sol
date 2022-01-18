// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {FusePool, FusePoolFactory} from "../FusePoolFactory.sol";

// TODO: I should not have to import ERC20 from here.
import {ERC20} from "solmate-next/utils/SafeTransferLib.sol";

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

    function testAddAsset() public {
        pool.addAsset(ERC20(address(underlying)), vault, FusePool.Asset(0, 0));
    }

    function testDeposit() public {
        testAddAsset();
        mintAndApprove(1e18);

        pool.deposit(underlying, 1e18);

        // note that the default exchange rate is 1:1, so these values should be set to 1e18.
        assertEq(pool.balances(address(this), underlying), 1e18, "Balance not updated");
        assertEq(pool.totalSupplies(underlying), 1e18, "Total supply not updated");
        assertEq(pool.totalUnderlying(underlying), 1e18, "Total underlying not updated");
    }

    // Mint and approve tokens.
    function mintAndApprove(uint256 amount) internal {
        underlying.mint(address(this), amount);
        underlying.approve(address(pool), amount);
    }
}
