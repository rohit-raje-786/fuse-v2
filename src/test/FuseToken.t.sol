// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {WETH} from "lib/solmate/src/tokens/WETH.sol";
import {Authority} from "lib/solmate/src/auth/Auth.sol";
import {DSTestPlus} from "lib/solmate/src/test/utils/DSTestPlus.sol";
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";

import {FuseToken} from "../pools/FuseToken.sol";
import {FusePoolController} from "../pools/FusePoolController.sol";
import {IRateModel} from "../pools/interfaces/IRateModel.sol";

contract FuseTokenTest is DSTestPlus {
    FuseToken fuseToken;
    FusePoolController poolController;
    MockERC20 underlying;

    function setUp() public {
        underlying = new MockERC20("Mock Token", "MT", 18);
        poolController = new FusePoolController("Fuse Pool Controller", "FPC");

        fuseToken = new FuseToken(underlying, poolController);
        fuseToken.initialize(0, 0, IRateModel(address(0)), 0, 0);
    }

    /*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

    function testAtomicDeposit() public {
        uint256 amount = 1e18;

        underlying.mint(address(this), amount);
        underlying.approve(address(fuseToken), amount);

        fuseToken.deposit(amount);
    }
}
