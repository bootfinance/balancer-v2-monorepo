import { expect } from 'chai';
import { ethers } from 'hardhat';
import { BigNumber, Contract } from 'ethers';

import { sharedBeforeEach } from '@balancer-labs/v2-common/sharedBeforeEach';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { bn } from '@balancer-labs/v2-helpers/src/numbers';
import { advanceTime, currentTimestamp, DAY, setNextBlockTimestamp } from '@balancer-labs/v2-helpers/src/time';
import * as expectEvent from '@balancer-labs/v2-helpers/src/test/expectEvent';
import { deploy } from '@balancer-labs/v2-helpers/src/contract';
import TypesConverter from '@balancer-labs/v2-helpers/src/models/types/TypesConverter';
import Vault from '@balancer-labs/v2-helpers/src/models/vault/Vault';
import { Account } from '@balancer-labs/v2-helpers/src/models/types/types';
import { actionId } from '@balancer-labs/v2-helpers/src/models/misc/actions';

describe('CustomPoolAmplification', () => {
  let owner: SignerWithAddress, admin: SignerWithAddress, other: SignerWithAddress;
  let vault: Vault;

  const MIN_AMP = bn(1);
  const MAX_AMP = bn(5000);
  const AMP_PRECISION = 1e3;
  const INITIAL_AMPLIFICATION_PARAMETER1 = bn(200);
  const INITIAL_AMPLIFICATION_PARAMETER2 = bn(200);
  const DELEGATE_OWNER = '0xBA1BA1ba1BA1bA1bA1Ba1BA1ba1BA1bA1ba1ba1B';

  sharedBeforeEach('setup signers', async () => {
    [, admin, owner, other] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault', async () => {
    vault = await Vault.create({ admin });
  });

  const deployPool = (owner: Account, amp1 = INITIAL_AMPLIFICATION_PARAMETER1, amp2 = INITIAL_AMPLIFICATION_PARAMETER2): Promise<Contract> =>
    deploy('MockCustomPoolAmplification', {
      args: [vault.address, TypesConverter.toAddress(owner), amp1, amp2],
    });

  describe('constructor', () => {
    context('when passing a valid initial amplification parameter value', () => {
      let pool: Contract;
      sharedBeforeEach('deploy pool', async () => {
        pool = await deployPool(owner);
      });

      it('sets the expected amplification parameter1', async () => {
        const { value1, isUpdating1, precision1 } = await pool.getAmplificationParameter1();
        expect(value1).to.be.equal(INITIAL_AMPLIFICATION_PARAMETER1.mul(AMP_PRECISION));
        expect(isUpdating1).to.be.false;
        expect(precision1).to.be.equal(AMP_PRECISION);
      });
      it('sets the expected amplification parameter2', async () => {
        const { value2, isUpdating2, precision2 } = await pool.getAmplificationParameter2();
        // TODO: Fix me. -JP
        expect(value2).to.be.equal(INITIAL_AMPLIFICATION_PARAMETER2.mul(AMP_PRECISION));
        expect(isUpdating2).to.be.false;
        expect(precision2).to.be.equal(AMP_PRECISION);
      });
    });

    context('when passing an initial amplification parameter less than MIN_AMP', () => {
      it('reverts', async () => {
        // JP TODO: test both
        await expect(deployPool(owner, MIN_AMP.sub(1), MIN_AMP.sub(1))).to.be.revertedWith('MIN_AMP');
      });
    });

    context('when passing an initial amplification parameter greater than MAX_AMP', () => {
      it('reverts', async () => {
        // JP TODO: test both
        await expect(deployPool(owner, MAX_AMP.add(1), MAX_AMP.add(1))).to.be.revertedWith('MAX_AMP');
      });
    });
  });

  describe('startAmplificationParameter1Update', () => {
    let pool: Contract;
    let caller: SignerWithAddress;

    function itStartsAnAmpUpdateCorrectly() {
      context('when requesting a reasonable change duration', () => {
        const duration = DAY * 2;
        let endTime: BigNumber;

        sharedBeforeEach('set end time', async () => {
          const startTime = (await currentTimestamp()).add(100);
          await setNextBlockTimestamp(startTime);
          endTime = startTime.add(duration);
        });

        context('when requesting a valid amp', () => {

          const itUpdatesAmpCorrectly = (newAmp: BigNumber) => {
            const increasing = INITIAL_AMPLIFICATION_PARAMETER1.lt(newAmp);

            context('when there is no ongoing update', () => {
              it('starts changing the amp', async () => {
                // TODO: fix me. -JP
                await pool.connect(caller).startAmplificationParameter1Update(newAmp, endTime);

                await advanceTime(duration / 3);

                const { value1, isUpdating1 } = await pool.getAmplificationParameter1();
                expect(isUpdating1).to.be.true;

                if (increasing) {
                  const diff = newAmp.sub(INITIAL_AMPLIFICATION_PARAMETER1).mul(AMP_PRECISION);
                  expect(value1).to.be.equalWithError(
                    INITIAL_AMPLIFICATION_PARAMETER1.mul(AMP_PRECISION).add(diff.div(3)),
                    0.00001
                  );
                } else {
                  const diff = INITIAL_AMPLIFICATION_PARAMETER1.sub(newAmp).mul(AMP_PRECISION);
                  expect(value1).to.be.equalWithError(
                    INITIAL_AMPLIFICATION_PARAMETER1.mul(AMP_PRECISION).sub(diff.div(3)),
                    0.00001
                  );
                }
              });

              it('stops updating after duration', async () => {
                // TODO: Fix me. -JP
                await pool.connect(caller).startAmplificationParameter1Update(newAmp, endTime);

                await advanceTime(duration + 1);

                const { value1, isUpdating1 } = await pool.getAmplificationParameter1();
                expect(value1).to.be.equal(newAmp.mul(AMP_PRECISION));
                expect(isUpdating1).to.be.false;
              });

              it('emits an AmpUpdateStarted event', async () => {
                const receipt = await pool.connect(caller).startAmplificationParameter1Update(newAmp, endTime);

                expectEvent.inReceipt(await receipt.wait(), 'Amp1UpdateStarted', {
                  startValue: INITIAL_AMPLIFICATION_PARAMETER1.mul(AMP_PRECISION),
                  endValue: newAmp.mul(AMP_PRECISION),
                  endTime,
                });
              });

              it('does not emit an AmpUpdateStopped event', async () => {
                const receipt = await pool.connect(caller).startAmplificationParameter1Update(newAmp, endTime);
                expectEvent.notEmitted(await receipt.wait(), 'AmpUpdateStopped');
              });
            });
            
            context('when there is an ongoing update', () => {
                sharedBeforeEach('start change', async () => {
                  await pool.connect(caller).startAmplificationParameter1Update(newAmp, endTime);

                  await advanceTime(duration / 3);
                  const beforeStop = await pool.getAmplificationParameter1();
                  expect(beforeStop.isUpdating1).to.be.true;
                 });

                it('trying to start another update reverts', async () => {
                  await expect(
                      pool.connect(caller).startAmplificationParameter1Update(newAmp, endTime)
                  ).to.be.revertedWith('AMP_ONGOING_UPDATE');
                });

                context('after the ongoing update is stopped', () => {
                  let ampValueAfterStop: BigNumber;

                  sharedBeforeEach('stop change', async () => {
                    await pool.connect(caller).stopAmplificationParameter1Update();
                    const ampState = await pool.getAmplificationParameter1();
                    ampValueAfterStop = ampState.value1;
                  });

                  it('the new update can be started', async () => {
                    const newEndTime = (await currentTimestamp()).add(DAY * 2);
                    const startReceipt = await pool.connect(caller).startAmplificationParameter1Update(newAmp, newEndTime);
                    const now = await currentTimestamp();
                    expectEvent.inReceipt(await startReceipt.wait(), 'Amp1UpdateStarted', {
                      endValue: newAmp.mul(AMP_PRECISION),
                      startTime: now,
                      endTime: newEndTime,
                    });

                    await advanceTime(duration / 3);

                    const afterStart = await pool.getAmplificationParameter1();
                    expect(afterStart.isUpdating1).to.be.true;
                    expect(afterStart.value1).to.be[increasing ? 'gt' : 'lt'](ampValueAfterStop);
                  });
                });
              });
            
          };

          context('when increasing the amp', () => {
            context('when increasing the amp by 2x', () => {
              const newAmp = INITIAL_AMPLIFICATION_PARAMETER1.mul(2);

              itUpdatesAmpCorrectly(newAmp);
            });
          });

          context('when decreasing the amp', () => {
            context('when decreasing the amp by 2x', () => {
              const newAmp = INITIAL_AMPLIFICATION_PARAMETER1.div(2);
              itUpdatesAmpCorrectly(newAmp);
            });
          });
        });

        context('when requesting an invalid amp', () => {
            it('reverts when requesting below the min', async () => {
              const lowAmp = bn(0);
              await expect(pool.connect(caller).startAmplificationParameter1Update(lowAmp, endTime)).to.be.revertedWith(
                  'MIN_AMP'
              );
            });

            it('reverts when requesting above the max', async () => {
              const highAmp = bn(5001);
              await expect(pool.connect(caller).startAmplificationParameter1Update(highAmp, endTime)).to.be.revertedWith(
                  'MAX_AMP'
              );
            });

            describe('rate limits', () => {
              let startTime: BigNumber;

              beforeEach('set start time', async () => {
                startTime = (await currentTimestamp()).add(100);
                await setNextBlockTimestamp(startTime);
              });

              it('reverts when increasing the amp by more than 2x in a single day', async () => {
                const newAmp = INITIAL_AMPLIFICATION_PARAMETER1.mul(2).add(1);
                const endTime = startTime.add(DAY);

                await expect(pool.connect(caller).startAmplificationParameter1Update(newAmp, endTime)).to.be.revertedWith(
                    'AMP_RATE_TOO_HIGH'
                );
              });

              it('reverts when increasing the amp by more than 2x daily over multiple days', async () => {
                const newAmp = INITIAL_AMPLIFICATION_PARAMETER1.mul(5).add(1);
                const endTime = startTime.add(DAY * 2);

                await expect(pool.connect(caller).startAmplificationParameter1Update(newAmp, endTime)).to.be.revertedWith(
                    'AMP_RATE_TOO_HIGH'
                );
              });

              it('reverts when decreasing the amp by more than 2x in a single day', async () => {
                const newAmp = INITIAL_AMPLIFICATION_PARAMETER1.div(2).sub(1);
                const endTime = startTime.add(DAY);

                await expect(pool.connect(caller).startAmplificationParameter1Update(newAmp, endTime)).to.be.revertedWith(
                    'AMP_RATE_TOO_HIGH'
                );
              });

              it('reverts when decreasing the amp by more than 2x daily over multiple days', async () => {
                const newAmp = INITIAL_AMPLIFICATION_PARAMETER1.div(5).sub(1);
                const endTime = startTime.add(DAY * 2);

                await expect(pool.connect(caller).startAmplificationParameter1Update(newAmp, endTime)).to.be.revertedWith(
                    'AMP_RATE_TOO_HIGH'
                );
              });
            });
          });
      });

      context('when requesting a short duration change', () => {
          let endTime;

          it('reverts', async () => {
            endTime = (await currentTimestamp()).add(DAY).sub(1);
            await expect(
                pool.connect(caller).startAmplificationParameter1Update(INITIAL_AMPLIFICATION_PARAMETER1, endTime)
            ).to.be.revertedWith('AMP_END_TIME_TOO_CLOSE');
          });
        });
    }

    function itReverts() {
      it('reverts', async () => {
        await expect(
          pool.connect(other).startAmplificationParameter1Update(INITIAL_AMPLIFICATION_PARAMETER1, DAY)
        ).to.be.revertedWith('SENDER_NOT_ALLOWED');
      });
    }

    context('with an owner', () => {
      sharedBeforeEach('deploy pool', async () => {
        pool = await deployPool(owner);
        caller = owner;
      });

      context('when the sender is allowed', () => {
        itStartsAnAmpUpdateCorrectly();
      });

      context('when the sender is not allowed', () => {
        itReverts();
      });
    });

    context('with a delegated owner', () => {
        sharedBeforeEach('deploy pool', async () => {
          pool = await deployPool(DELEGATE_OWNER);
          caller = other;
        });

        context('when the sender is allowed', () => {
          sharedBeforeEach('grant permissions', async () => {
            const startAmpChangePermission = await actionId(pool, 'startAmplificationParameter1Update');
            const stopAmpChangePermission = await actionId(pool, 'stopAmplificationParameter1Update');
            await vault.grantPermissionsGlobally([startAmpChangePermission, stopAmpChangePermission], other);
          });

          itStartsAnAmpUpdateCorrectly();
        });

        context('when the sender is not allowed', () => {
          itReverts();
        });
      });

  });

   describe('stopAmplificationParameter1Update', () => {
      let pool: Contract;
      let caller: SignerWithAddress;

      function itStopsAnAmpUpdateCorrectly() {
        context('when there is an ongoing update', () => {
          sharedBeforeEach('start change', async () => {
            const newAmp = INITIAL_AMPLIFICATION_PARAMETER1.mul(2);
            const duration = DAY * 2;

            const startTime = (await currentTimestamp()).add(100);
            await setNextBlockTimestamp(startTime);
            const endTime = startTime.add(duration);

            await pool.connect(caller).startAmplificationParameter1Update(newAmp, endTime);

            await advanceTime(duration / 3);
            const beforeStop = await pool.getAmplificationParameter1();
            expect(beforeStop.isUpdating1).to.be.true;
          });

          it('stops the amp factor from updating', async () => {
            const beforeStop = await pool.getAmplificationParameter1();

            await pool.connect(caller).stopAmplificationParameter1Update();

            const afterStop = await pool.getAmplificationParameter1();
            expect(afterStop.value1).to.be.equalWithError(beforeStop.value1, 0.001);
            expect(afterStop.isUpdating1).to.be.false;

            await advanceTime(30 * DAY);

            const muchLaterAfterStop = await pool.getAmplificationParameter1();
            expect(muchLaterAfterStop.value1).to.be.equal(afterStop.value1);
            expect(muchLaterAfterStop.isUpdating1).to.be.false;
          });

          it('emits an AmpUpdateStopped event', async () => {
            const receipt = await pool.connect(caller).stopAmplificationParameter1Update();
            expectEvent.inReceipt(await receipt.wait(), 'Amp1UpdateStopped');
          });

          it('does not emit an AmpUpdateStarted event', async () => {
            const receipt = await pool.connect(caller).stopAmplificationParameter1Update();
            expectEvent.notEmitted(await receipt.wait(), 'Amp1UpdateStarted');
          });
        });

        context('when there is no ongoing update', () => {
          it('reverts', async () => {
            await expect(pool.connect(caller).stopAmplificationParameter1Update()).to.be.revertedWith(
                'AMP_NO_ONGOING_UPDATE'
            );
          });
        });
      }

      function itReverts() {
        it('reverts', async () => {
          await expect(pool.connect(other).stopAmplificationParameter1Update()).to.be.revertedWith('SENDER_NOT_ALLOWED');
        });
      }

      context('with an owner', () => {
        sharedBeforeEach('deploy pool', async () => {
          pool = await deployPool(owner);
          caller = owner;
        });

        context('when the sender is allowed', () => {
          itStopsAnAmpUpdateCorrectly();
        });

        context('when the sender is not allowed', () => {
          itReverts();
        });
      });

      context('with a delegated owner', () => {
        sharedBeforeEach('deploy pool', async () => {
          pool = await deployPool(DELEGATE_OWNER);
          caller = other;
        });

        context('when the sender is allowed', () => {
          sharedBeforeEach('grant permissions', async () => {
            const startAmpChangePermission = await actionId(pool, 'startAmplificationParameter1Update');
            const stopAmpChangePermission = await actionId(pool, 'stopAmplificationParameter1Update');
            await vault.grantPermissionsGlobally([startAmpChangePermission, stopAmpChangePermission], other);
          });

          itStopsAnAmpUpdateCorrectly();
        });

        context('when the sender is not allowed', () => {
          itReverts();
        });
      });
    });

});
