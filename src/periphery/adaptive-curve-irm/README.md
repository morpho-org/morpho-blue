# AdaptiveCurveIRM

These contracts were migrated from the [morpho-blue-irm](https://github.com/morpho-org/morpho-blue-irm) repository, which holds their history and PRs.

## Overview

[`AdaptiveCurveIrm`](./AdaptiveCurveIrm.sol) is an interest rate model for Morpho Blue.
See its [documentation](https://docs.morpho.org/concepts/morpho-blue/core-concepts/irm#the-adaptivecurveirm) and [announcement article](https://morpho.mirror.xyz/aaUjIF85aIi5RT6-pLhVWBzuiCpOb4BV03OYNts2BHQ).

[`AdaptiveCurveIrmLib`](./libraries/periphery/AdaptiveCurveIrmLib.sol) computes the borrow rate and the expected market balances of markets using the `AdaptiveCurveIrm` without calling it.

## Developers

> [!IMPORTANT]
> The `AdaptiveCurveIrm` was deployed [on Ethereum](https://etherscan.io/address/0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC) without the `via_ir` solc compilation option.
> To check the bytecode on Ethereum, use the `no_via_ir` profile (`FOUNDRY_PROFILE=no_via_ir`).
> Other deployments use `via_ir`.

## Audits

All audits are stored in the [`audits`](../../../audits) folder.
