import { Contract } from 'ethers';
import { deploy } from '@balancer-labs/v2-helpers/src/contract';

import { RawCustomPoolDeployment, CustomPoolDeployment } from './types';

import Vault from '../../vault/Vault';
import VaultDeployer from '../../vault/VaultDeployer';
import TypesConverter from '../../types/TypesConverter';
import CustomPool from './CustomPool';

const NAME = 'Balancer Pool Token';
const SYMBOL = 'BPT';

export default {
  async deploy(params: RawCustomPoolDeployment): Promise<CustomPool> {
    const deployment = TypesConverter.toCustomPoolDeployment(params);
    const vaultParams = { ...TypesConverter.toRawVaultDeployment(params), mocked: params.mockedVault ?? false };
    const vault = params?.vault ?? (await VaultDeployer.deploy(vaultParams));
    const pool = await this._deployStandalone(deployment, vault);

    const poolId = await pool.getPoolId();
    const bptIndex = await pool.getBptIndex();
    const { tokens, swapFeePercentage, amplificationParameter1, amplificationParameter2, owner } = deployment;

    return new CustomPool(pool, poolId, vault, tokens, bptIndex, swapFeePercentage, amplificationParameter1, amplificationParameter2, owner);
  },

  async _deployStandalone(params: CustomPoolDeployment, vault: Vault): Promise<Contract> {
    const {
      tokens,
      rateProviders,
      tokenRateCacheDurations,
      exemptFromYieldProtocolFeeFlags,
      swapFeePercentage,
      pauseWindowDuration,
      bufferPeriodDuration,
      amplificationParameter1,
      amplificationParameter2,
      from,
    } = params;

    const owner = TypesConverter.toAddress(params.owner);
    let stableMath: Contract = await deploy('StableMath');
    let customMath: Contract = await deploy('CustomMath', {
      libraries: {
        StableMath: stableMath.address,
      },
    });
    return deploy('v2-pool-custom/MockComposableCustomPool', {
      args: [
        {
          vault: vault.address,
          protocolFeeProvider: vault.getFeesProvider().address,
          name: NAME,
          symbol: SYMBOL,
          tokens: tokens.addresses,
          rateProviders: TypesConverter.toAddresses(rateProviders),
          tokenRateCacheDurations,
          exemptFromYieldProtocolFeeFlags,
          amplificationParameter1,
          amplificationParameter2,
          swapFeePercentage,
          pauseWindowDuration,
          bufferPeriodDuration,
          owner,
        },
      ],
      libraries: {
        StableMath: stableMath.address,
        CustomMath: customMath.address,
      },
      from,
    });
  },
};
