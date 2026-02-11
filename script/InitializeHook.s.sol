// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract InitializePool is Script {
    // Sepolia PoolManager
    address constant POOLMANAGER = 0xE03A1074c86CcED75AB52AC5569c9714D21F8963;
    
    // YOUR DEPLOYED HOOK ADDRESS
    address constant HOOK_ADDR = 0x57Ebed0e5f12C267D5E222e687FF97D90D44C080;

    function run() public {
        vm.startBroadcast();

        // 1. Deploy two Mock Tokens so we can test easily
        MockERC20 tokenA = new MockERC20("Token A", "TKNA", 18);
        MockERC20 tokenB = new MockERC20("Token B", "TKNB", 18);
        
        console.log("Token A deployed at:", address(tokenA));
        console.log("Token B deployed at:", address(tokenB));

        // 2. Sort tokens (Uniswap requires token0 < token1)
        (Currency currency0, Currency currency1) = address(tokenA) < address(tokenB)
            ? (Currency.wrap(address(tokenA)), Currency.wrap(address(tokenB)))
            : (Currency.wrap(address(tokenB)), Currency.wrap(address(tokenA)));

        // 3. Define the PoolKey with your Hook
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000, // 0.3% base fee (hook will override)
            tickSpacing: 60,
            hooks: IHooks(HOOK_ADDR)
        });

        // 4. Initialize the pool at 1:1 price
        // sqrtPriceX96 = 2^96 (approx 79228162514264337593543950336)
        IPoolManager(POOLMANAGER).initialize(key, 79228162514264337593543950336, "");

        console.log("Pool Initialized successfully!");
        
        // 5. Mint some tokens to yourself for later testing
        MockERC20(Currency.unwrap(currency0)).mint(msg.sender, 1000 ether);
        MockERC20(Currency.unwrap(currency1)).mint(msg.sender, 1000 ether);
        
        vm.stopBroadcast();
    }
}