// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {FeeDiscountHook} from "../src/feeDiscount.sol";

// 1. We deploy this mini-factory to guarantee a known 'msg.sender' for the hook
contract HookFactory {
    function deploy(bytes32 salt, bytes memory bytecode) external returns (address addr) {
        assembly {
            // This performs the actual CREATE2 deployment
            addr := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        require(addr != address(0), "Deployment failed");
    }
}

contract DeployHooks is Script {
    // Sepolia PoolManager Address
    address constant POOLMANAGER = 0xE03A1074c86CcED75AB52AC5569c9714D21F8963;

    function run() public {
        vm.startBroadcast();

        // Step 1: Deploy the Factory first
        HookFactory factory = new HookFactory();
        console.log("Factory Deployed at:", address(factory));

        // Step 2: Prepare the Hook's bytecode + constructor arguments
        // This is what we will actually deploy
        bytes memory hookBytecode = abi.encodePacked(
            type(FeeDiscountHook).creationCode,
            abi.encode(IPoolManager(POOLMANAGER))
        );

        // Step 3: Mine the Salt
        // CRITICAL FIX: We tell HookMiner that 'factory' will be the deployer, NOT msg.sender
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);
        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(factory), 
            flags, 
            hookBytecode, 
            "" // Empty args here because we already packed them into hookBytecode above
        );

        console.log("Mined Hook Address:", hookAddress);

        // Step 4: Deploy using the Factory
        address deployedHook = factory.deploy(salt, hookBytecode);
        
        // Step 5: Verification
        require(deployedHook == hookAddress, "Address mismatch: Mined vs Actual differs");
        console.log("SUCCESS: Hook deployed at:", deployedHook);

        vm.stopBroadcast();
    }
}