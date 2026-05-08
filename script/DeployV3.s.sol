// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";
import {UniswapV3Factory} from "src/v3-core/UniswapV3Factory.sol";
import {UniswapInterfaceMulticall} from "src/v3-periphery/lens/UniswapInterfaceMulticall.sol";
import {TickLens} from "src/v3-periphery/lens/TickLens.sol";
import {NonfungiblePositionManager} from "src/v3-periphery/NonfungiblePositionManager.sol";
import {NonfungibleTokenPositionDescriptor} from "src/v3-periphery/NonfungibleTokenPositionDescriptor.sol";
import {V3Migrator} from "src/v3-periphery/V3Migrator.sol";
import {QuoterV2} from "src/v3-periphery/lens/QuoterV2.sol";
import {SwapRouter} from "src/v3-periphery/SwapRouter.sol";

/// @notice Foundry reimplementation of the uniswap-deploy-v3 TypeScript migration process.
contract DeployV3 is Script {
    uint24 internal constant ONE_BP_FEE = 100;
    int24 internal constant ONE_BP_TICK_SPACING = 1;

    event DeploymentAddress(string key, address value);
    event DeploymentBytes32(string key, bytes32 value);

    struct DeploymentState {
        address v3CoreFactoryAddress;
        address multicall2Address;
        address proxyAdminAddress;
        address tickLensAddress;
        address descriptorImplementationAddress;
        address descriptorProxyAddress;
        address nonfungibleTokenPositionManagerAddress;
        address v3MigratorAddress;
        address quoterV2Address;
        address swapRouterAddress;
    }

    function run() external returns (DeploymentState memory state) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address weth9Address = vm.envAddress("WETH9_ADDRESS");
        bytes32 nativeCurrencyLabelBytes = _stringToBytes32(vm.envString("NATIVE_CURRENCY_LABEL"));
        address v2CoreFactoryAddress = vm.envAddress("V2_CORE_FACTORY_ADDRESS");
        address ownerAddress = vm.envAddress("OWNER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // 1) DEPLOY_V3_CORE_FACTORY
        UniswapV3Factory factory = new UniswapV3Factory();
        state.v3CoreFactoryAddress = address(factory);
        console.log("Deployed UniswapV3Factory at", state.v3CoreFactoryAddress);

        // 2) ADD_1BP_FEE_TIER
        _addOneBpFeeTier(factory, deployer);
        console.log("Added 1 BP fee tier");

        // 3) DEPLOY_MULTICALL2 (UniswapInterfaceMulticall)
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        state.proxyAdminAddress = address(proxyAdmin);
        console.log("Deployed ProxyAdmin at", state.proxyAdminAddress);

        state = _deployPeriphery(state, weth9Address, nativeCurrencyLabelBytes);

        // 10) TRANSFER_V3_CORE_FACTORY_OWNER
        _transferFactoryOwnership(factory, deployer, ownerAddress);
        console.log("Transferred UniswapV3Factory ownership to", ownerAddress);

        // 14) TRANSFER_PROXY_ADMIN
        _transferProxyAdminOwnership(proxyAdmin, deployer, ownerAddress);
        console.log("Transferred ProxyAdmin ownership to", ownerAddress);

        vm.stopBroadcast();

        _logDeployment(state, nativeCurrencyLabelBytes, ownerAddress, v2CoreFactoryAddress);
        return state;
    }

    function _deployPeriphery(DeploymentState memory state, address weth9Address, bytes32 nativeCurrencyLabelBytes)
        internal
        returns (DeploymentState memory)
    {
        // 3) DEPLOY_MULTICALL2 (UniswapInterfaceMulticall)
        state.multicall2Address = address(new UniswapInterfaceMulticall());
        console.log("Deployed UniswapInterfaceMulticall at", state.multicall2Address);

        // 5) DEPLOY_TICK_LENS
        state.tickLensAddress = address(new TickLens());
        console.log("Deployed TickLens at", state.tickLensAddress);

        // 6a) DEPLOY_NFT_DESCRIPTOR_LIBRARY
        // NFTDescriptor library is deployed implicitly via NonfungibleTokenPositionDescriptor
        console.log("NFTDescriptor library deployment handled via NonfungibleTokenPositionDescriptor");

        // 6b) DEPLOY_NFT_POSITION_DESCRIPTOR
        state.descriptorImplementationAddress =
            address(new NonfungibleTokenPositionDescriptor(weth9Address, nativeCurrencyLabelBytes));
        console.log("Deployed NonfungibleTokenPositionDescriptor at", state.descriptorImplementationAddress);

        // 7) DEPLOY_TRANSPARENT_PROXY_DESCRIPTOR
        state.descriptorProxyAddress = address(
            new TransparentUpgradeableProxy(state.descriptorImplementationAddress, state.proxyAdminAddress, bytes(""))
        );
        console.log("Deployed TransparentUpgradeableProxy for descriptor at", state.descriptorProxyAddress);

        // 8) DEPLOY_NONFUNGIBLE_POSITION_MANAGER
        state.nonfungibleTokenPositionManagerAddress = address(
            new NonfungiblePositionManager(state.v3CoreFactoryAddress, weth9Address, state.descriptorProxyAddress)
        );
        console.log("Deployed NonfungiblePositionManager at", state.nonfungibleTokenPositionManagerAddress);

        // 9) DEPLOY_V3_MIGRATOR
        state.v3MigratorAddress = address(
            new V3Migrator(state.v3CoreFactoryAddress, weth9Address, state.nonfungibleTokenPositionManagerAddress)
        );
        console.log("Deployed V3Migrator at", state.v3MigratorAddress);

        // 12) DEPLOY_QUOTER_V2
        state.quoterV2Address = address(new QuoterV2(state.v3CoreFactoryAddress, weth9Address));
        console.log("Deployed QuoterV2 at", state.quoterV2Address);

        // 13) DEPLOY_V3_SWAP_ROUTER_02 (not present in this repo)
        // Deploy SwapRouter from v3-periphery as the local equivalent.
        state.swapRouterAddress = address(new SwapRouter(state.v3CoreFactoryAddress, weth9Address));
        console.log("Deployed SwapRouter at", state.swapRouterAddress);

        return state;
    }

    function _addOneBpFeeTier(UniswapV3Factory factory, address deployer) internal {
        int24 currentSpacing = factory.feeAmountTickSpacing(ONE_BP_FEE);
        if (currentSpacing == ONE_BP_TICK_SPACING) return;

        require(factory.owner() == deployer, "UniswapV3Factory.owner is not deployer");
        factory.enableFeeAmount(ONE_BP_FEE, ONE_BP_TICK_SPACING);
    }

    function _transferFactoryOwnership(UniswapV3Factory factory, address deployer, address ownerAddress) internal {
        address currentOwner = factory.owner();
        if (currentOwner == ownerAddress) return;

        require(currentOwner == deployer, "UniswapV3Factory.owner is not deployer");
        factory.setOwner(ownerAddress);
    }

    function _transferProxyAdminOwnership(ProxyAdmin proxyAdmin, address deployer, address ownerAddress) internal {
        address currentOwner = proxyAdmin.owner();
        if (currentOwner == ownerAddress) return;

        require(currentOwner == deployer, "ProxyAdmin.owner is not deployer");
        proxyAdmin.transferOwnership(ownerAddress);
    }

    function _stringToBytes32(string memory value) internal pure returns (bytes32 result) {
        bytes memory raw = bytes(value);
        require(raw.length > 0, "NATIVE_CURRENCY_LABEL is empty");
        require(raw.length <= 32, "NATIVE_CURRENCY_LABEL exceeds 32 bytes");

        assembly {
            result := mload(add(value, 32))
        }
    }

    function _logDeployment(
        DeploymentState memory state,
        bytes32 nativeCurrencyLabelBytes,
        address ownerAddress,
        address v2CoreFactoryAddress
    ) internal pure {
        console.log("\n=== DeployV3 Summary ===");
        console.log("v3CoreFactory:              ", state.v3CoreFactoryAddress);
        console.log("multicall2:                 ", state.multicall2Address);
        console.log("proxyAdmin:                 ", state.proxyAdminAddress);
        console.log("tickLens:                   ", state.tickLensAddress);
        console.log("descriptorImplementation:   ", state.descriptorImplementationAddress);
        console.log("descriptorProxy:            ", state.descriptorProxyAddress);
        console.log("nonfungiblePositionManager: ", state.nonfungibleTokenPositionManagerAddress);
        console.log("v3Migrator:                 ", state.v3MigratorAddress);
        console.log("quoterV2:                   ", state.quoterV2Address);
        console.log("swapRouter:                 ", state.swapRouterAddress);
        console.log("owner:                      ", ownerAddress);
        console.log("v2CoreFactor:              ", v2CoreFactoryAddress);
        console.logBytes32(nativeCurrencyLabelBytes);
        console.log("========================\n");
    }
}
