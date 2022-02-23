// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {FusePool, FusePoolFactory} from "../FusePoolFactory.sol";

// TODO: I should not have to import ERC20 from here.
import {ERC20} from "solmate-next/utils/SafeTransferLib.sol";

import {Authority} from "solmate-next/auth/Auth.sol";
import {DSTest} from "ds-test/test.sol";

import {IFlashBorrower} from "../interface/IFlashBorrower.sol";

import {IPriceOracle} from "../interface/IPriceOracle.sol";
import {MockPriceOracle} from "./mocks/MockPriceOracle.sol";

import {MockERC4626} from "./mocks/MockERC4626.sol";
import {MockFlashBorrower} from "./mocks/MockFlashBorrower.sol";
import {MockERC20} from "solmate-next/test/utils/mocks/MockERC20.sol";

/// @title Fuse Pool Factory Test Contract
contract FusePoolTest is DSTest {
    // Used variables.
    FusePoolFactory factory;
    FusePool pool;
    IPriceOracle oracle;

    MockERC20 underlying;
    MockERC4626 vault;

    function setUp() public {
        // Deploy contracts.
        factory = new FusePoolFactory(address(this), Authority(address(0)));
        oracle = IPriceOracle(address(new MockPriceOracle()));
        (pool, ) = factory.deployFusePool("Test Pool", oracle);

        underlying = new MockERC20("Test Underlying", "TST", 18);
        vault = new MockERC4626(underlying, "Test Vault", "TST");

        pool.addAsset(ERC20(address(underlying)), vault, FusePool.Asset(0, 0));
    }

    function testAddAsset() public {
        assertEq(address(pool.vaults(underlying)), address(vault));
        assertEq(pool.baseUnits(underlying), 1e18);
    }

    /*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

    function testDeposit(uint256 amount) public {
        if (amount < 1e9 || amount > 1e36) return;

        // Add the asset to the pool and mint tokens.
        testAddAsset();
        mintAndApprove(amount);

        // Deposit tokens to the Fuse Pool.
        pool.deposit(underlying, amount);

        // Do checks.
        // note that the default exchange rate is 1:1, so these values should be set to the input amount.
        assertEq(pool.totalUnderlying(underlying), amount, "Total underlying not updated");
        assertEq(pool.balanceOfUnderlying(underlying, address(this)), amount, "Balance not updated");
    }

    function testWithdrawal(uint256 amount) public {
        if (amount < 1e9 || amount > 1e36) return;

        // Deposit tokens to the FusePool.
        testDeposit(amount);

        // Withdraw tokens from the FusePool.
        pool.withdraw(underlying, amount);

        // Do checks.
        assertEq(pool.totalUnderlying(underlying), 0, "Total underlying not updated");
        assertEq(underlying.balanceOf(address(this)), amount, "Tokens not transferred back");
        assertEq(pool.balanceOfUnderlying(underlying, address(this)), 0, "Balance not updated");
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/WITHDRAWAL SANITY TESTS
    //////////////////////////////////////////////////////////////*/

    function testFailWithdrawWithNotEnoughBalance(uint256 amount) public {
        if (amount < 100 || amount > 1e36) revert();

        // Deposit tokens to the FusePool.
        testDeposit(amount / 2);

        // Withdraw tokens from the FusePool.
        testWithdrawal(amount);
    }

    /*///////////////////////////////////////////////////////////////
                            FLASHLOAN TESTS
    //////////////////////////////////////////////////////////////*/

    function testFlashLoan() public {
        // Deposit funds.
        testDeposit(1e18);

        // Deploy a mock flash borrower example.
        MockFlashBorrower borrower = new MockFlashBorrower();
        bytes memory data = abi.encode(address(underlying));

        // Call a flash loan.
        pool.flashLoan(IFlashBorrower(address(borrower)), data, underlying, 1e18);
    }

    // Mint and approve tokens.
    function mintAndApprove(uint256 amount) internal {
        underlying.mint(address(this), amount);
        underlying.approve(address(pool), amount);
    }
}
