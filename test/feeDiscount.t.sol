// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager, SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

import {FeeDiscountHook} from "../src/feeDiscount.sol";

contract FeeDiscountHookTest is Test, Deployers {
    using CurrencyLibrary for Currency;

    FeeDiscountHook hook;
    address userWhitelisted = address(0x123);
    address userNotWhitelisted = address(0x456);
    address admin = address(0x999);

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);
        (address hookAddress, bytes32 salt) = HookMiner.find(
            admin, 
            flags,
            type(FeeDiscountHook).creationCode,
            abi.encode(manager)
        );

        vm.prank(admin);
        hook = new FeeDiscountHook{salt: salt}(manager);
        require(address(hook) == hookAddress, "Hook address mismatch");

        (key, ) = initPool(
            currency0,
            currency1,
            hook,
            3000, 
            SQRT_PRICE_1_1
        );

        MockERC20(Currency.unwrap(currency0)).approve(address(modifyLiquidityRouter), type(uint256).max);
        MockERC20(Currency.unwrap(currency1)).approve(address(modifyLiquidityRouter), type(uint256).max);

        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: -6000,  // 100 tick spacings wide — keeps slippage negligible for 0.1 ether swaps
                tickUpper: 6000,
                liquidityDelta: 1000 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    function setupUser(address _user) internal {
        MockERC20(Currency.unwrap(currency0)).transfer(_user, 100 ether);
        MockERC20(Currency.unwrap(currency1)).transfer(_user, 100 ether);

        vm.startPrank(_user);
        MockERC20(Currency.unwrap(currency0)).approve(address(swapRouter), type(uint256).max);
        MockERC20(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();
    }

    /// @dev Execute a swap as `_user` (sets both msg.sender AND tx.origin)
    function _doSwap(address _user, SwapParams memory params) internal returns (BalanceDelta) {
        PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
        vm.prank(_user, _user);
        return swapRouter.swap(key, params, settings, ZERO_BYTES);
    }

    /// @dev zeroForOne exact-output SwapParams
    function _zeroForOneParams(uint256 amount) internal pure returns (SwapParams memory) {
        return SwapParams({
            zeroForOne: true,
            amountSpecified: int256(amount),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
    }

    /// @dev oneForZero exact-output SwapParams
    function _oneForZeroParams(uint256 amount) internal pure returns (SwapParams memory) {
        return SwapParams({
            zeroForOne: false,
            amountSpecified: int256(amount),
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
        });
    }

    function test_OnlyOwner_CanSetWhitelist() public {
        // Non-owner should revert
        vm.expectRevert(FeeDiscountHook.NotOwner.selector);
        vm.prank(userWhitelisted);
        hook.setWhitelist(userWhitelisted, true);

        // Owner can set
        vm.prank(admin);
        hook.setWhitelist(userWhitelisted, true);
        assertTrue(hook.whitelist(userWhitelisted));
    }

    function test_Swap_WhitelistedPaysLess_ZeroForOne() public {
        SwapParams memory params = _zeroForOneParams(0.1 ether);

        // --- whitelisted swap first (0.1 % fee, best available price) ---
        setupUser(userWhitelisted);
        vm.prank(admin);
        hook.setWhitelist(userWhitelisted, true);

        BalanceDelta deltaWL = _doSwap(userWhitelisted, params);
        uint256 paidWhitelisted = uint256(-int256(deltaWL.amount0()));
        assertEq(int256(deltaWL.amount1()), 0.1 ether);

        // --- non-whitelisted swap second (full 0.3 % fee, price already moved slightly against this direction) ---
        setupUser(userNotWhitelisted);
        BalanceDelta deltaNon = _doSwap(userNotWhitelisted, params);
        uint256 paidNonWhitelisted = uint256(-int256(deltaNon.amount0()));
        assertEq(int256(deltaNon.amount1()), 0.1 ether);

        // whitelisted paid strictly less: lower fee AND better price
        assertLt(paidWhitelisted, paidNonWhitelisted);

        console2.log("Whitelisted   input paid (token0):", paidWhitelisted);
        console2.log("Non-whitelisted input paid (token0):", paidNonWhitelisted);
        console2.log("Saving (wei)                      :", paidNonWhitelisted - paidWhitelisted);
    }


    function test_Swap_WhitelistedPaysLess_OneForZero() public {
        SwapParams memory params = _oneForZeroParams(0.1 ether);

        // --- whitelisted first ---
        setupUser(userWhitelisted);
        vm.prank(admin);
        hook.setWhitelist(userWhitelisted, true);

        BalanceDelta deltaWL = _doSwap(userWhitelisted, params);
        uint256 paidWhitelisted = uint256(-int256(deltaWL.amount1()));
        assertEq(int256(deltaWL.amount0()), 0.1 ether);

        // --- non-whitelisted second ---
        setupUser(userNotWhitelisted);
        BalanceDelta deltaNon = _doSwap(userNotWhitelisted, params);
        uint256 paidNonWhitelisted = uint256(-int256(deltaNon.amount1()));
        assertEq(int256(deltaNon.amount0()), 0.1 ether);

        assertLt(paidWhitelisted, paidNonWhitelisted);

        console2.log("Opposite-dir whitelisted   input paid (token1):", paidWhitelisted);
        console2.log("Opposite-dir non-whitelisted input paid (token1):", paidNonWhitelisted);
    }


    function test_Swap_RevokedWhitelistPaysFullFee() public {
        SwapParams memory params = _zeroForOneParams(0.1 ether);

        // --- whitelisted swap first (cheap) ---
        setupUser(userWhitelisted);
        vm.prank(admin);
        hook.setWhitelist(userWhitelisted, true);

        BalanceDelta deltaWL = _doSwap(userWhitelisted, params);
        uint256 paidWhitelisted = uint256(-int256(deltaWL.amount0()));

        // --- non-whitelisted baseline (full fee) ---
        setupUser(userNotWhitelisted);
        BalanceDelta deltaNon = _doSwap(userNotWhitelisted, params);
        uint256 paidBaseline = uint256(-int256(deltaNon.amount0()));

        assertLt(paidWhitelisted, paidBaseline); // sanity: discount was active

        // --- revoke whitelist ---
        vm.prank(admin);
        hook.setWhitelist(userWhitelisted, false);
        assertFalse(hook.whitelist(userWhitelisted));

        // Top up balance for the third swap (approval is still max)
        MockERC20(Currency.unwrap(currency0)).transfer(userWhitelisted, 100 ether);

        BalanceDelta deltaRevoked = _doSwap(userWhitelisted, params);
        uint256 paidRevoked = uint256(-int256(deltaRevoked.amount0()));

        assertApproxEqAbs(paidRevoked, paidBaseline, 1e14);

        console2.log("Whitelisted       paid:", paidWhitelisted);
        console2.log("Baseline (non-WL) paid:", paidBaseline);
        console2.log("After-revoke      paid:", paidRevoked);
    }


    function test_Swap_ZeroAmount_Reverts() public {
        setupUser(userWhitelisted);
        vm.prank(admin);
        hook.setWhitelist(userWhitelisted, true);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 0,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        vm.expectRevert(IPoolManager.SwapAmountCannotBeZero.selector);
        _doSwap(userWhitelisted, params);
    }
}