// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager, SwapParams} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";

contract FeeDiscountHook is BaseHook {
    mapping(address => bool) public whitelist;
    address public owner;
    uint24 public constant DISCOUNTED_FEE = 1000; // 0.1% fee override for whitelisted users (adjust as needed)

    error NotOwner();

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        owner = msg.sender;
    }

    // LINT FIX: Wrap logic in internal function to save bytecode size
    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    function _onlyOwner() internal view {
        if (msg.sender != owner) revert NotOwner();
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function setWhitelist(address user, bool allowed) external onlyOwner {
        whitelist[user] = allowed;
    }

    // WARNINGS FIXED: 
    // 1. Commented out unused parameters 
    // 2. Added 'view' keyword
    function _beforeSwap(
        address, /* sender */
        PoolKey calldata, /* key */
        SwapParams calldata, /* params */
        bytes calldata /* hookData */
    ) internal view override returns (bytes4, BeforeSwapDelta, uint24) {
        
        // Logic: If whitelisted (via tx.origin), apply fee discount override; else, no override (full pool fee)
        uint24 feeOverride = whitelist[tx.origin] ? DISCOUNTED_FEE : 0;

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, feeOverride);
    }
}