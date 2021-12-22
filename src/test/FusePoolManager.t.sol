pragma solidity 0.8.10;

import {DSTestPlus} from "lib/solmate/src/test/utils/DSTestPlus.sol";
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";

import {TrustAuthority} from "lib/solmate/src/auth/authorities/TrustAuthority.sol";
import {Authority} from "lib/solmate/src/Auth/Auth.sol";

import {FusePoolToken} from "../pools/FusePoolToken.sol";
import {FusePoolManager} from "../pools/FusePoolManager.sol";
import {IRateModel} from "../pools/interfaces/IRateModel.sol";

contract FusePoolManagerTest is DSTestPlus {
    MockERC20 underlying;
    TrustAuthority authority;

    FusePoolManager poolManager;

    function setUp() public {
        // Deploy Fuse contracts
        underlying = new MockERC20("Mock Token", "MT", 18);
        authority = new TrustAuthority(address(this));
        poolManager = new FusePoolManager(Authority(address(authority)), "Fuse Pool Manager", "FPN");
    }
