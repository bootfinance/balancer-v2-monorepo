# <img src="../../logo.svg" alt="Balancer" height="128px">

# Balancer V2 Custom Pools

[![NPM Package](https://img.shields.io/npm/v/@balancer-labs/v2-pool-custom.svg)](https://www.npmjs.org/package/@balancer-labs/v2-pool-custom)

---

This package contains the source code of Balancer V2 Custom Pools, that is, Pools for tokens that all have values very close to each other (typically customcoins).

The only flavor currently in existence is [`ComposableCustomPool`](./contracts/ComposableCustomPool.sol) (basic five token version).

Another useful contract is [`CustomMath`](../pool-custom/contracts/CustomMath.sol), which implements the low level calculations required for swaps, joins and exits.
