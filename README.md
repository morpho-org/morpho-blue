# Morpho Blue

Morpho Blue is a new lending primitive that offers better rates, high capital efficiency and extended flexibility to lenders & borrowers.

## Whitepaper

A more detailed description of Morpho Blue can be found in the [Morpho Blue's Whitepaper](./whitepaper.pdf).

## Repository Structure

Morpho Blue is a singleton contract at the `src`'s root: [`Morpho.sol`](./src/Morpho.sol). It solely relies on internal libraries in the [`src/libraries`](./src/libraries) directory. No external dependency is used.

Libaries in the [`src/libraries/periphery`](./src/libraries/periphery) directory are not directly used by Morpho Blue. They are useful helpers that integrators can reuse or adapt to their own needs.

The `mocks` directory contains contracts designed exclusively for testing.

You'll find relevant comments in [Morpho's interface](./src/interfaces/IMorpho.sol), notably a list of assumptions about market creation.

## Getting Started

Install dependencies with `yarn`.

Run tests using forge: `yarn test:forge`

Run tests using hardhat (gas cost study): `yarn test:hardhat`

You will find other CLI commands in the [`package.json`](./package.json) file.

## Licensing

The primary license for Morpho Blue is the Business Source License 1.1 (`BUSL-1.1`), see [`LICENSE`](./LICENSE). However, some files are dual licensed under `GPL-2.0-or-later`.

All files in the following folders can also be licensed under `GPL-2.0-or-later` (as indicated in their SPDX headers):
- `src/interfaces`, see [`src/interfaces/LICENSE`](./src/interfaces/LICENSE)
- `src/libraries`, see [`src/libraries/LICENSE`](./src/libraries/LICENSE)
- `src/mocks`, see [`src/mocks/LICENSE`](./src/mocks/LICENSE)
- `test`, see [`test/LICENSE`](./test/LICENSE)
