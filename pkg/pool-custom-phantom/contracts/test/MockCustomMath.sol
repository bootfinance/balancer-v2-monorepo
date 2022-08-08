// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.7.0;

import "../CustomMath.sol";

contract MockCustomMath {
    function invariant(uint256 amp1, uint256 amp2, uint256[] memory balances) external pure returns (uint256) {
        return CustomMath._calculateInvariant(amp1, amp2, balances);
    }

    function outGivenIn(
        uint256 amp1,
        uint256 amp2,
        uint256[] memory balances,
        uint256 tokenIndexIn,
        uint256 tokenIndexOut,
        uint256 tokenAmountIn
    ) external pure returns (uint256) {
        return
            CustomMath._calcOutGivenIn(
                amp1,
                amp2,
                balances,
                tokenIndexIn,
                tokenIndexOut,
                tokenAmountIn,
                CustomMath._calculateInvariant(amp1, amp2, balances)
            );
    }

    function inGivenOut(
        uint256 amp1,
        uint256 amp2,
        uint256[] memory balances,
        uint256 tokenIndexIn,
        uint256 tokenIndexOut,
        uint256 tokenAmountOut
    ) external pure returns (uint256) {
        return
            CustomMath._calcInGivenOut(
                amp1,
                amp2,
                balances,
                tokenIndexIn,
                tokenIndexOut,
                tokenAmountOut,
                CustomMath._calculateInvariant(amp1, amp2, balances)
            );
    }

    function exactTokensInForBPTOut(
        uint256 amp1,
        uint256 amp2,
        uint256[] memory balances,
        uint256[] memory amountsIn,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFee
    ) external pure returns (uint256) {
        return CustomMath._calcBptOutGivenExactTokensIn(amp1, amp2, balances, amountsIn, bptTotalSupply, currentInvariant, swapFee);
    }

    function tokenInForExactBPTOut(
        uint256 amp1,
        uint256 amp2,
        uint256[] memory balances,
        uint256 tokenIndex,
        uint256 bptAmountOut,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFee
    ) external pure returns (uint256) {
        return
            CustomMath._calcTokenInGivenExactBptOut(amp1, amp2, balances, tokenIndex, bptAmountOut, bptTotalSupply, currentInvariant, swapFee);
    }

    function exactBPTInForTokenOut(
        uint256 amp1,
        uint256 amp2,
        uint256[] memory balances,
        uint256 tokenIndex,
        uint256 bptAmountIn,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFee
    ) external pure returns (uint256) {
        return CustomMath._calcTokenOutGivenExactBptIn(amp1, amp2, balances, tokenIndex, bptAmountIn, bptTotalSupply, currentInvariant, swapFee);
    }

    function bptInForExactTokensOut(
        uint256 amp1,
        uint256 amp2,
        uint256[] memory balances,
        uint256[] memory amountsOut,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFee
    ) external pure returns (uint256) {
        return CustomMath._calcBptInGivenExactTokensOut(amp1, amp2, balances, amountsOut, bptTotalSupply, currentInvariant, swapFee);
    }
}
