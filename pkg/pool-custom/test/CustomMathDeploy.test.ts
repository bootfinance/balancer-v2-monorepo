import { Contract } from 'ethers';
import { random } from 'lodash';
import { deploy } from '@balancer-labs/v2-helpers/src/contract';
import { bn, fp, BigNumber } from '@balancer-labs/v2-helpers/src/numbers';
import { expectEqualWithError } from '@balancer-labs/v2-helpers/src/test/relativeError';
import { calculateInvariants } from '@balancer-labs/v2-helpers/src/models/pools/custom/math';
import '@nomiclabs/hardhat-ethers';
import { Libraries } from '@nomiclabs/hardhat-ethers/types';

describe('CustomMath', function() {
  const AMP_PRECISION = 1e3;
  const MAX_RELATIVE_ERROR = 0.0001; // Max relative error

  let mock: Contract;

  before(async function() {
    let stableMath: Contract = await deploy('StableMath');
    let customMath: Contract = await deploy('CustomMath', {
      libraries: {
        StableMath: stableMath.address,
      },
    });
    mock = await deploy('MockCustomMath', {
      libraries: {
        StableMath: stableMath.address,
        CustomMath: customMath.address,
      },
    });
  });

  context('test stub', () => {

      async function checkInvariant(balances: BigNumber[], amp1: number, amp2: number): Promise<void> {
        const A1 = bn(amp1).mul(AMP_PRECISION);
        const A2 = bn(amp2).mul(AMP_PRECISION);

        // actual
        const D1a = await mock.invariant(A1, A2, balances, 1);
        // expected
        const D1e = calculateInvariants(balances, amp1, amp2, 1);
        expectEqualWithError(D1a, D1e, MAX_RELATIVE_ERROR);

        console.log('ts: C1', D1a.toString(), D1e.toString());

        // actual
        const D2a = await mock.invariant(A1, A2, balances, 2);
        // expected
        const D2e = calculateInvariants(balances, amp1, amp2, 2);

        console.log('ts: C2', D2a.toString(), D2e.toString());

        expectEqualWithError(D2a, D2e, MAX_RELATIVE_ERROR);
      }


      context('check over a range of inputs', () => {
        for (let numTokens = 2; numTokens <= 2; numTokens++) {
          const balances = Array.from({ length: numTokens }, () => random(250, 350)).map(fp);
          it(`computes the invariant for ${numTokens} tokens`, async () => {
            for (let amp = 100; amp <= 5000; amp += 100) {
              await checkInvariant(balances, amp, amp);
            }
          });
        }
      });


    },
  );

});
