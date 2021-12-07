// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {WETH} from "lib/solmate/src/tokens/WETH.sol";
import {Authority} from "lib/solmate/src/auth/Auth.sol";
import {DSTestPlus} from "lib/solmate/src/test/utils/DSTestPlus.sol";
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";

import {FuseToken} from "../pools/FuseToken.sol";

contract FuseTokenTest is DSTestPlus {
    FuseToken fuseToken;
    MockERC20 mockERC20;

    function setUp() public {
        mockERC20 = new MockERC20("Mock Token", "MT", 18);
        fuseToken = new FuseToken(mockERC20, "Fuse Test Token", "fTest");
    }
}
