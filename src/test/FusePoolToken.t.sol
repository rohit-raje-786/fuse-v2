// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {DSTestPlus} from "lib/solmate/src/test/utils/DSTestPlus.sol";
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";

import {TrustAuthority} from "lib/solmate/src/auth/authorities/TrustAuthority.sol";
import {Authority} from "lib/solmate/src/Auth/Auth.sol";

import {FusePoolToken} from "../pools/FusePoolToken.sol";
import {FusePoolManager} from "../pools/FusePoolManager.sol";
import {IRateModel} from "../pools/interfaces/IRateModel.sol";

contract FusePoolTokenTest is DSTestPlus {
    MockERC20 underlying;
    TrustAuthority authority;

    FusePoolManager poolManager;
    FusePoolToken fuseToken;

    function setUp() public {
        // Deploy Fuse contracts
        underlying = new MockERC20("Mock Token", "MT", 18);
        authority = new TrustAuthority(address(this));
        poolManager = new FusePoolManager(Authority(address(authority)), "Fuse Pool Manager", "FPN");
        fuseToken = poolManager.deployFusePoolToken(underlying, 0, 0, IRateModel(address(0)), 0, 0);
    }

    /*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

    function testAtomicDeposit() public {
        // Mint and approve underlying tokens to FusePoolToken
        uint256 amount = 1e18;
        underlying.mint(address(this), amount);
        underlying.approve(address(fuseToken), amount);

        // Deposit tokens
        fuseToken.deposit(amount);

        // Ensure values are correct.
        assertEq(amount, fuseToken.balanceOf(address(this)));
        assertEq(amount, fuseToken.totalSupply());
        assertEq(amount, fuseToken.exchangeRate());
    }

    function testAtomicWithdrawal() public {
        // Mint and deposit underlying tokens.
        uint256 amount = 1e18;
        testAtomicDeposit();

        // Withdraw tokens.
        fuseToken.withdraw(amount);

        assertEq(amount, underlying.balanceOf(address(this)));
        assertEq(amount, fuseToken.exchangeRate());
        assertEq(0, fuseToken.totalSupply());
    }

    function testAtomicRedeem() public {
        uint256 amount = 1e18;
        testAtomicDeposit();
        fuseToken.redeem(amount);
    }

    function testAtomicBorrow() public {
        uint256 amount = 1e18;
        testAtomicDeposit();
        fuseToken.borrow(amount);
    }

    function testAtomicRepay() public {
        uint256 amount = 1e18;
        testAtomicBorrow();
        fuseToken.repay(amount);
    }
}
