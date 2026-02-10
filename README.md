# Morpho Market V1 (Morpho Blue)

Morpho Blue is a noncustodial lending protocol implemented for the Ethereum Virtual Machine.
Morpho Blue offers a new trustless primitive with increased efficiency and flexibility compared to existing lending platforms.
It provides permissionless risk management and permissionless market creation with oracle agnostic pricing.
It also enables higher collateralization factors, improved interest rates, and lower gas consumption.
The protocol is designed to be a simple, immutable, and governance-minimized base layer that allows for a wide variety of other layers to be built on top.
Morpho Blue also offers a convenient developer experience with a singleton implementation, callbacks, free flash loans, and account management features.

## Whitepaper

The protocol is described in detail in the [Morpho Blue Whitepaper](./morpho-blue-whitepaper.pdf).

## Repository Structure

[`Morpho.sol`](./src/Morpho.sol) contains most of the source code of the core contract of Morpho Blue.
It solely relies on internal libraries in the [`src/libraries`](./src/libraries) subdirectory.

Libraries in the [`src/libraries/periphery`](./src/libraries/periphery) directory are not used by Morpho Blue.
They are useful helpers that integrators can reuse or adapt to their own needs.

The [`src/mocks`](./src/mocks) directory contains contracts designed exclusively for testing.

You'll find relevant comments in [`IMorpho.sol`](./src/interfaces/IMorpho.sol), notably a list of requirements about market dependencies.

## Developers

Compilation, testing and formatting with [forge](https://book.getfoundry.sh/getting-started/installation).

## Audits

All audits are stored in the [audits](./audits/) folder.

## License

Files in this repository are publicly available under license `GPL-2.0-or-later`, see [`LICENSE`](./LICENSE).
The previous license (BUSL-1.1) can be found [here](https://github.com/morpho-org/morpho-blue/blob/1bcfbfdfa284597ae526d082dd34bcd182d15d27/LICENSE) for reference.
