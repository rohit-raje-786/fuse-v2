pragma solidity 0.8.10;

import {WETH} from "lib/solmate/src/tokens/WETH.sol";
import {Authority} from "lib/solmate/src/auth/Auth.sol";
import {DSTestPlus} from "lib/solmate/src/test/utils/DSTestPlus.sol";
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";

import "../pools/FuseToken.sol" as FuseToken;

contract FuseTokenTest is DSTestPlus {
    FuseToken fuseToken;

    function setUp() public {
        fuseToken = new FuseToken("Fuse Test Token", "fTest");
    }
}
