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

    FusePoolManager manager;

    function setUp() public {
        // Deploy Fuse contracts
        underlying = new MockERC20("Mock Token", "MT", 18);
        authority = new TrustAuthority(address(this));
        manager = new FusePoolManager(Authority(address(authority)), "Fuse Pool Manager", "FPN");
    }

    function testFusePoolTokenDeployment() public {
        // Deploy Fuse Pool Token.
        FusePoolToken token = manager.deployFusePoolToken(underlying, 1e17, 1e18, IRateModel(address(0)), 1e18, 1e18);

        // Retrieve values.
        (uint256 lendFactor, uint256 borrowFactor) = manager.assets(token);
        IRateModel rateModel = token.rateModel();
        uint256 reserveRate = token.reserveRate();
        uint256 feeRate = token.feeRate();

        // Ensure that token variables are valid.
        assertEq(lendFactor, 1e17);
        assertEq(borrowFactor, 1e18);
        assertEq(address(rateModel), address(0));
        assertEq(reserveRate, 1e18);
        assertEq(feeRate, 1e18);
    }
}
