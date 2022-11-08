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

import "@balancer-labs/v2-solidity-utils/contracts/math/FixedPoint.sol";
import "@balancer-labs/v2-solidity-utils/contracts/math/Math.sol";
import "./StableMath.sol";
import "hardhat/console.sol";

// solhint-disable private-vars-leading-underscore, var-name-mixedcase

library CustomMath {

    using FixedPoint for uint256;

    uint256 internal constant _MIN_AMP = 1;
    uint256 internal constant _MAX_AMP = 5000;
    uint256 internal constant _AMP_PRECISION = 1e3;
    uint256 internal constant _MAX_CUSTOM_TOKENS = 2;

    struct Curve {
        uint256 A1;
        uint256 D1;
        uint256 A2;
        uint256 D2;
    }

    function getRate(
        uint256[] memory B,
        uint256 A1,
        uint256 A2,
        uint256 supply
    ) internal view returns (uint256) {
        // When calculating the current BPT rate, we may not have paid the protocol fees, therefore
        // the invariant should be smaller than its current value. Then, we round down overall.
        uint256 curve = 1;
        uint256 D1 = calculateInvariant(A1, A2, B, curve);
        return D1.divDown(supply);
    }

    function getCurve(
        uint256[] memory B
    ) internal view returns (uint256) {
        if (B[0] < B[1]) {
            return 1;
        } else {
            return 2;
        }
    }

    function _calcZ(
        uint256 A, uint256 D
    ) internal view returns (uint256[] memory ZZ) {
        // Rounds result up overall
        uint256 D2 = Math.mul(D, D);
        uint256 D3 = Math.mul(D, D2);
        uint256 a = A * 2;

        uint256 b = D.sub(
            Math.mul(
                Math.divUp(D, Math.mul(2, a)),
                _AMP_PRECISION
            )
        );

        uint256 c = Math.mul(
            Math.divUp(D3, Math.mul(8, a)),
            _AMP_PRECISION
        );

        uint256 Z = Math.divUp(b.add(Math.divUp(c, D2)), 2);

        uint256 Zp = 0;

        for (uint256 i = 0; i < 255; i++) {

            Zp = Z;

            Z = Math.divUp(b.add(Math.divUp(c, Math.mul(Z, Z))), 2);

            if (Z > Zp) {
                if (Z - Zp <= 1) {
                    ZZ = new uint256[](2);
                    ZZ[0] = Z;
                    ZZ[1] = Z;
                    console.log("sol: calcZ A, D Z i");
                    console.log(i, A, D, Z);
                    return ZZ;
                }
            } else if (Zp - Z <= 1) {
                ZZ = new uint256[](2);
                ZZ[0] = Z;
                ZZ[1] = Z;
                console.log("sol: calcZ i, A, D Z");
                console.log(i, A, D, Z);
                return ZZ;
            }
        }

        _revert(Errors.STABLE_GET_BALANCE_DIDNT_CONVERGE);

        ZZ = new uint256[](2);
        return ZZ;
    }

    // A1, A2 - amplification factors
    // B - token balances
    // Ct - target curve (1 or 2)
    function calculateInvariant(
        uint256 A1, uint256 A2, uint256[] memory B, uint256 Ct
    ) internal view returns (uint256)
    {

        console.log("sol: calculateInvariant");
        console.log("sol: A1=", A1, "A2=", A2);
        console.log("sol: B=", B[0], B[1], B.length);

        uint256 C = getCurve(B);

        if (C == Ct) {
            if (C == 1) {
                return StableMath.__calculateInvariant(A1, B);
            } else {
                return StableMath.__calculateInvariant(A2, B);
            }
        } else {
            if (C == 1) {
                uint256 D1 = StableMath.__calculateInvariant(A1, B);
                uint256[] memory Z = _calcZ(A1, D1);
                uint256 DZ = StableMath.__calculateInvariant(A2, Z);
                // console.log("curve 3 D1", D1, DZ, D1 - DZ);
                return DZ;
            } else {
                uint256 D2 = StableMath.__calculateInvariant(A2, B);
                uint256[] memory Z = _calcZ(A2, D2);
                return StableMath.__calculateInvariant(A1, Z);
            }
        }

    }

    function calculateInvariants(
        uint256 A1, uint256 A2, uint256[] memory B
    ) internal view returns (uint256, uint256)
    {
        uint256 D1;
        uint256 D2;
        if (getCurve(B) == 1) {
            D1 = StableMath.__calculateInvariant(A1, B);
            D2 = StableMath.__calculateInvariant(A2, _calcZ(A1, D1));
        } else {
            D2 = StableMath.__calculateInvariant(A2, B);
            D1 = StableMath.__calculateInvariant(A1, _calcZ(A2, D2));
        }

        return (D1, D2);

    }

    // TRADE
    // Bb - balance before the trade
    function calcOutGivenIn(
        uint256 A1, uint256 A2, uint256[] memory B, uint256 tokenIndexIn, uint256 tokenIndexOut, uint256 tokenAmountIn
    ) internal view returns (uint256, uint256) {

        uint256 curveIn = getCurve(B);
        uint256 curveOut;

        // balance after the trade
        uint256 [] memory Ba = new uint256[](2);
        Ba[tokenIndexIn] = B[tokenIndexIn].add(tokenAmountIn);
        Ba[tokenIndexOut] = B[tokenIndexOut];

        if (curveIn == 1) {
            uint256 D1 = StableMath.__calculateInvariant(A1, B);
            Ba[tokenIndexOut] = StableMath.__getTokenBalanceGivenInvariantAndAllOtherBalances(A1, Ba, D1, tokenIndexOut);

            if (Ba[0] <= Ba[1]) {
                // we are on curve 1 so we are okay
                curveOut = 1;
            } else {
                // we are on curve 2, so we should have used A2/D2
                uint256 [] memory Z = _calcZ(A1, D1);
                uint256 D2 = StableMath.__calculateInvariant(A2, Z);
                Ba[tokenIndexIn] = B[tokenIndexIn].add(tokenAmountIn);
                Ba[tokenIndexOut] = B[tokenIndexOut];
                // ??
                Ba[tokenIndexOut] = StableMath.__getTokenBalanceGivenInvariantAndAllOtherBalances(A2, Ba, D2, tokenIndexOut);
                curveOut = 2;
            }
        } else {
            uint256 D2 = StableMath.__calculateInvariant(A2, B);
            Ba[tokenIndexOut] = StableMath.__getTokenBalanceGivenInvariantAndAllOtherBalances(A2, Ba, D2, tokenIndexOut);

            if (Ba[0] > Ba[1]) {
                // we are on curve 2 so we are okay
                curveOut = 2;
            } else {
                // we are on curve 1, so we should have used A1/D1
                uint256 [] memory Z = _calcZ(A2, D2);
                uint256 D1 = StableMath.__calculateInvariant(A1, Z);
                Ba[tokenIndexIn] = B[tokenIndexIn].add(tokenAmountIn);
                Ba[tokenIndexOut] = B[tokenIndexOut];
                Ba[tokenIndexOut] = StableMath.__getTokenBalanceGivenInvariantAndAllOtherBalances(A1, Ba, D1, tokenIndexOut);
                curveOut = 1;
            }
        }

        return (curveOut, B[tokenIndexOut].sub(Ba[tokenIndexOut]).sub(1));

    }

    function calcInGivenOut(
        uint256 A1, uint256 A2, uint256[] memory B, uint256 tokenIndexIn, uint256 tokenIndexOut, uint256 tokenAmountOut
    ) internal view returns (uint256, uint256) {

        uint256 curveIn = getCurve(B);
        uint256 curveOut;

        uint256 [] memory Ba = new uint256[](2);
        Ba[tokenIndexIn] = B[tokenIndexIn];
        Ba[tokenIndexOut] = B[tokenIndexOut].sub(tokenAmountOut);


        if (curveIn == 1) {
            uint256 D1 = StableMath.__calculateInvariant(A1, B);
            Ba[tokenIndexIn] = StableMath.__getTokenBalanceGivenInvariantAndAllOtherBalances(A1, Ba, D1, tokenIndexIn);

            if (Ba[0] <= Ba[1]) {
                // we are on curve 1 so we are okay
                curveOut = 1;
            } else {
                // we are on curve 2, so we should have used A2/D2
                uint256 [] memory Z = _calcZ(A1, D1);
                uint256 D2 = StableMath.__calculateInvariant(A2, Z);
                Ba[tokenIndexIn] = B[tokenIndexIn];
                Ba[tokenIndexOut] = B[tokenIndexOut].sub(tokenAmountOut);
                // ??
                Ba[tokenIndexIn] = StableMath.__getTokenBalanceGivenInvariantAndAllOtherBalances(A2, Ba, D2, tokenIndexIn);
                curveOut = 2;
            }
        } else {
            uint256 D2 = StableMath.__calculateInvariant(A2, B);
            Ba[tokenIndexOut] = StableMath.__getTokenBalanceGivenInvariantAndAllOtherBalances(A2, Ba, D2, tokenIndexIn);

            if (Ba[0] > Ba[1]) {
                // we are on curve 2 so we are okay
                curveOut = 2;
            } else {
                // we are on curve 1, so we should have used A1/D1
                uint256 [] memory Z = _calcZ(A2, D2);
                uint256 D1 = StableMath.__calculateInvariant(A1, Z);
                Ba[tokenIndexIn] = B[tokenIndexIn];
                Ba[tokenIndexOut] = B[tokenIndexOut].sub(tokenAmountOut);
                Ba[tokenIndexIn] = StableMath.__getTokenBalanceGivenInvariantAndAllOtherBalances(A1, Ba, D1, tokenIndexIn);
                curveOut = 1;
            }
        }

        return (curveOut, B[tokenIndexIn].sub(Ba[tokenIndexIn]).add(1));

    }

    // REBALANCE - ISSUE/MINT

    // A1, A2 - amplification factors
    // Bb - balances before rebalance
    // dBb - exact token balances to add (in)
    // fee - swap fee percentage
    // Qbpt - total quantity of BPT
    function calcBptOutGivenExactTokensIn(
        Curve memory C, uint256[] memory Bb, uint256[] memory dBb, uint256 Qbpt, uint256 fee
    ) internal view returns (uint256) {

        // BPT out, so we round down overall.

        // First loop calculates the sum of all token balances, which will be used to calculate
        // the current weights of each token, relative to this sum
        uint256 sum = 0;
        for (uint256 i = 0; i < Bb.length; i++) {
            sum = sum.add(Bb[i]);
        }

        // Calculate the weighted balance ratio without considering fees
        uint256[] memory R = new uint256[](dBb.length);
        // The weighted sum of token balance ratios without considering fees
        uint256 Rw = 0;
        for (uint256 i = 0; i < Bb.length; i++) {
            // current weight
            uint256 Wc = Bb[i].divDown(sum);
            R[i] = Bb[i].add(dBb[i]).divDown(Bb[i]);
            Rw = Rw.add(R[i].mulDown(Wc));
        }

        // Second loop calculates new quantities in, taking into account the fee on the percentage excess
        // Ba - balances after rebalance
        uint256[] memory Ba = new uint256[](Bb.length);
        for (uint256 i = 0; i < Bb.length; i++) {
            // quantity to add after subtracting fees
            uint256 dBi;
            // Check if the balance ratio is greater than the ideal ratio to charge fees or not
            if (R[i] > Rw) {
                // tax-free portion
                uint256 dBf = Bb[i].mulDown(Rw.sub(FixedPoint.ONE));
                // taxable portion
                uint256 dBt = dBb[i].sub(dBf);
                // No need to use checked arithmetic for the swap fee, it is guaranteed to be lower than 50%
                dBi = dBf.add(dBt.mulDown(FixedPoint.ONE - fee));
            } else {
                dBi = dBb[i];
            }
            Ba[i] = Bb[i].add(dBi);
        }

        // which curve are we on?
        uint256 curve = getCurve(Ba);
        // what is the new invariant for the curve
        uint256 Dc = calculateInvariant(C.A1, C.A2, Ba, curve);

        // how much did the invariant grow?
        // we both invariants before this rebalance - they should correspond to Bb & A1/A2.
        uint256 Rinv;
        if (curve == 1) {
            Rinv = Dc.divDown(C.D1);
        } else {
            Rinv = Dc.divDown(C.D2);
        }
        // If the invariant didn't increase for any reason, we simply don't mint BPT
        if (Rinv > FixedPoint.ONE) {
            return Qbpt.mulDown(Rinv - FixedPoint.ONE);
        } else {
            return 0;
        }
    }

    // A1, A2, D1, D2 - current curves
    // B - token balances
    // Qbpt - total supply of BPT
    // dQbpt - exact quantity of BPT out
    // fee - swap fee percentage

    function calcTokenInGivenExactBptOut(
        Curve memory C, uint256[] memory B, uint256 tokenIndex, uint256 dQbpt, uint256 Qbpt, uint256 fee
    ) internal view returns (uint256) {
        // Token in, so we round up overall.

        uint256 R = Qbpt.add(dQbpt).divUp(Qbpt);
        // both A1/D1 and A2/D2 will give us the same side, in other words we can determine which side of x=y we are on.
        uint256 newD1 = R.mulUp(C.D1);
        // Calculate amount in without fee.
        uint256 newBalanceTokenIndex = StableMath.__getTokenBalanceGivenInvariantAndAllOtherBalances(C.A1, B, newD1, tokenIndex);

        uint256[] memory newB = new uint256[](2);
        newB[tokenIndex] = newBalanceTokenIndex;
        newB[1 - tokenIndex] = B[1 - tokenIndex];
        uint256 curveOut = getCurve(newB);

        if (curveOut != 1) {
            uint256 newD2 = R.mulUp(C.D2);
            newBalanceTokenIndex = StableMath.__getTokenBalanceGivenInvariantAndAllOtherBalances(C.A2, B, newD2, tokenIndex);
        }

        // the curve may have changed, but it's ok, all we need is the new balance.
        uint256 amountInWithoutFee = newBalanceTokenIndex.sub(B[tokenIndex]);

        // First calculate the sum of all token balances, which will be used to calculate
        // the current weight of each token
        uint256 sum = 0;
        for (uint256 i = 0; i < B.length; i++) {
            sum = sum.add(B[i]);
        }

        // We can now compute how much extra balance is being deposited and used in virtual swaps, and charge swap fees
        // accordingly.
        uint256 w = B[tokenIndex].divDown(sum);
        uint256 taxablePercentage = w.complement();
        uint256 taxableAmount = amountInWithoutFee.mulUp(taxablePercentage);
        uint256 nonTaxableAmount = amountInWithoutFee.sub(taxableAmount);

        // No need to use checked arithmetic for the swap fee, it is guaranteed to be lower than 50%
        return nonTaxableAmount.add(taxableAmount.divUp(FixedPoint.ONE - fee));
    }

    // REBALANCE - REDEEM/BURN


    // Flow of calculations:
    // amountsTokenOut -> amountsOutProportional ->
    // amountOutPercentageExcess -> amountOutBeforeFee -> newInvariant -> amountBPTIn
    // A1, A2, D1, D2 - current curves
    // B - token balances
    // dB - exact token balances to subtract (out)
    // Qbpt - total supply of BPT
    // fee - swap fee percentage

    function calcBptInGivenExactTokensOut(
        Curve memory C, uint256[] memory B, uint256[] memory dB, uint256 Qbpt, uint256 fee
    ) internal view returns (uint256) {
        // BPT in, so we round up overall.

        // First loop calculates the sum of all token balances, which will be used to calculate
        // the current weights of each token relative to this sum
        uint256 sum = 0;
        for (uint256 i = 0; i < B.length; i++) {
            sum = sum.add(B[i]);
        }

        // Calculate the weighted balance ratio without considering fees
        uint256[] memory R = new uint256[](dB.length);
        // The weighted sum of token balance ratios without considering fees
        uint256 Rw = 0;
        for (uint256 i = 0; i < B.length; i++) {
            // current weight
            uint256 Wc = B[i].divUp(sum);
            R[i] = B[i].sub(dB[i]).divUp(B[i]);
            Rw = Rw.add(R[i].mulUp(Wc));
        }

        // Second loop calculates new amounts in, taking into account the fee on the percentage excess
        // Ba - balance after the rebalance
        uint256[] memory Ba = new uint256[](B.length);
        for (uint256 i = 0; i < B.length; i++) {
            // Swap fees are typically charged on 'token in', but there is no 'token in' here, so we apply it to
            // 'token out'. This results in slightly larger price impact.
            // amount out with fee
            uint256 dBi;
            if (Rw > R[i]) {
                // tax-free portions
                uint256 dBf = B[i].mulDown(Rw.complement());
                // taxable portion
                uint256 dBt = dB[i].sub(dBf);
                // No need to use checked arithmetic for the swap fee, it is guaranteed to be lower than 50%
                dBi = dBf.add(dBt.divUp(FixedPoint.ONE - fee));
            } else {
                dBi = dB[i];
            }

            Ba[i] = B[i].sub(dBi);
        }

        // which curve are we on?
        uint256 curve = getCurve(Ba);
        // what is the new invariant for the curve
        uint256 Dc = calculateInvariant(C.A1, C.A2, Ba, curve);

        // how much did the invariant grow?
        // we both invariants before this rebalance - they should correspond to Bb & A1/A2.
        uint256 Rinv;
        if (curve == 1) {
            Rinv = Dc.divDown(C.D1);
        } else {
            Rinv = Dc.divDown(C.D2);
        }

        // return amountBPTIn
        return Qbpt.mulUp(Rinv.complement());

    }

    // A1, A2, D1, D2 - current curves
    // B - token balances
    // Qbpt - total supply of BPT
    // dQbpt - exact quantity of BPT in
    // fee - swap fee percentage

    function calcTokenOutGivenExactBptIn(
        Curve memory C, uint256[] memory B, uint256 tokenIndex, uint256 dQbpt, uint256 Qbpt, uint256 fee
    ) internal view returns (uint256) {
        // Token out, so we round down overall.

        // uint256 newInvariant = bptTotalSupply.sub(bptAmountIn).divUp(bptTotalSupply).mulUp(currentInvariant);

        uint256 R = Qbpt.sub(dQbpt).divUp(Qbpt);
        uint256 D1 = R.mulUp(C.D1);

        // Calculate amount out without fee
        uint256 newBalanceTokenIndex = StableMath.__getTokenBalanceGivenInvariantAndAllOtherBalances(C.A1, B, D1, tokenIndex);

        uint256[] memory newB = new uint256[](2);
        newB[tokenIndex] = newBalanceTokenIndex;
        newB[1 - tokenIndex] = B[1 - tokenIndex];
        uint256 curveOut = getCurve(newB);

        if (curveOut != 1) {
            uint256 D2 = R.mulUp(C.D2);
            newBalanceTokenIndex = StableMath.__getTokenBalanceGivenInvariantAndAllOtherBalances(C.A2, B, D2, tokenIndex);
        }

        uint256 amountOutWithoutFee = B[tokenIndex].sub(newBalanceTokenIndex);

        // First calculate the sum of all token balances, which will be used to calculate
        // the current weight of each token
        uint256 sum = 0;
        for (uint256 i = 0; i < B.length; i++) {
            sum = sum.add(B[i]);
        }

        // We can now compute how much excess balance is being withdrawn as a result of the virtual swaps, which result
        // in swap fees.
        // current weight
        uint256 Wc = B[tokenIndex].divDown(sum);
        uint256 taxablePercentage = Wc.complement();

        // Swap fees are typically charged on 'token in', but there is no 'token in' here, so we apply it
        // to 'token out'. This results in slightly larger price impact. Fees are rounded up.
        uint256 taxableAmount = amountOutWithoutFee.mulUp(taxablePercentage);
        uint256 nonTaxableAmount = amountOutWithoutFee.sub(taxableAmount);

        // No need to use checked arithmetic for the swap fee, it is guaranteed to be lower than 50%
        return nonTaxableAmount.add(taxableAmount.mulDown(FixedPoint.ONE - fee));

    }
}
