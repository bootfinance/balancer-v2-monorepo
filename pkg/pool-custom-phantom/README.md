# <img src="../../logo.svg" alt="Balancer" height="128px">

# Balancer V2 Custom Phantom Pools

[![NPM Package](https://img.shields.io/npm/v/@balancer-labs/v2-pool-custom-phantom.svg)](https://www.npmjs.org/package/@balancer-labs/v2-pool-custom-phantom)

---

This package contains the source code of Balancer V2 Custom Phantom Pools, that is, Pools for tokens that all have values very close to each other (typically customcoins).

The only flavor currently in existence is [`CustomPhantomPool`](./contracts/CustomPhantomPool.sol) (basic five token version).

Another useful contract is [`CustomMath`](../pool-custom-phantom/contracts/CustomMath.sol), which implements the low level calculations required for swaps, joins and exits.
