# Light Account

[![gh_ci_badge]][gh_ci_link]\
[![discord_badge]][discord_link]

[gh_ci_badge]: https://github.com/alchemyplatform/light-account/actions/workflows/test.yml/badge.svg
[gh_ci_link]: https://github.com/alchemyplatform/light-account/actions/workflows/test.yml
[discord_badge]: https://dcbadge.vercel.app/api/server/alchemyplatform
[discord_link]: https://discord.gg/alchemyplatform

![](./img/light-account.jpg)

A simple ERC-4337 compatible smart contract account with a designated owner. [Account Kit](https://accountkit.alchemy.com) is the easiest way to integrate Light Account.

## Features

Like [eth-infinitism](https://github.com/eth-infinitism/account-abstraction)'s [`SimpleAccount`](https://github.com/eth-infinitism/account-abstraction/blob/develop/contracts/samples/SimpleAccount.sol), but with the following changes:

1. Instead of the default storage slots, uses namespaced storage to avoid clashes when switching implementations.

2. Ownership can be transferred via `transferOwnership`, similar to the behavior of an `Ownable` contract. This is a simple single-step operation, so care must be taken to ensure that the ownership is being transferred to the correct address.

3. Supports [ERC-1271](https://eips.ethereum.org/EIPS/eip-1271) signature validation for both validating the signature on user operations and in exposing its own `isValidSignature` method. This only works when the owner of `LightAccount` also support ERC-1271.

   _ERC-4337's bundler validation rules limit the types of contracts that can be used as owners to validate user operation signatures. For example, the contract's `isValidSignature` function may not use any forbidden opcodes such as `TIMESTAMP` or `NUMBER`, and the contract may not be an ERC-1967 proxy as it accesses a constant implementation slot not associated with the account, violating storage access rules. This also means that the owner of a `LightAccount` may not be another `LightAccount` if you want to send user operations through a bundler._

4. Event `SimpleAccountInitialized` renamed to `LightAccountInitialized`.

5. Uses custom errors.

## Deployments

See the current deployments in [Deployments.md](./Deployments.md).

## Build

```bash
forge build
```

## Test

```bash
forge test -vvv
```

## Deploy

The deploy script supports any [wallet options](https://book.getfoundry.sh/reference/forge/forge-script#wallet-options---raw) provided by Foundry, including local private keys, mneumonics, hardware wallets, and remote signers. Append the chosen signing method's option to the field marked `[WALLET_OPTION]` in the following script command, and set the sender address in the field `[SENDER_ADDRESS]`.

```bash
forge script script/Deploy_LightAccountFactory.s.sol:Deploy_LightAccountFactory [WALLET_OPTION] --sender [SENDER_ADDRESS]--rpc-url [RPC_URL] -vvvv --broadcast --verify
```

Make sure the provided `RPC_URL` is set to an RPC for the chain you wish to deploy on.

## Generate Inspections

```bash
bash utils/inspect.sh
```

## Static Analysis

```bash
slither .
```

## Dependencies

Light Account uses dependencies via git submodules, pinned to release branches. Dependencies that cannot be reliably pinned (or those that needed to be modified) have been copied directly into the repository. These are listed below:

| File                                                                    | Description                                                                                    | Source                                                                                                                                                                      |
| ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [CustomSlotInitializable.sol](./src/common/CustomSlotInitializable.sol) | A fork of OpenZeppelin's `Initializable` contract that allows custom storage slots to be used. | [Initializable.sol (932fddf)](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/932fddf69a699a9a80fd2396fd1a2ab91cdda123/contracts/proxy/utils/Initializable.sol) |
| [EIP712.sol](./src/external/solady/EIP712.sol)                          | Copied from Solady.                                                                            | [EIP712.sol (eac17da)](https://github.com/Vectorized/solady/blob/eac17da6d57d864f179a6d81e02127cabe3b77d9/src/utils/EIP712.sol)                                             |
| [LibClone.sol](./src/external/solady/LibClone.sol)                      | Copied from Solady.                                                                            | [LibClone.sol (7a1f591)](https://github.com/Vectorized/solady/blob/7a1f591fe53487bd6952c4df23d3bed26a4b678d/src/utils/LibClone.sol)                                         |
| [UUPSUpgradeable.sol](./src/external/solady/UUPSUpgradeable.sol)        | Copied from Solady.                                                                            | [UUPSUpgradeable.sol (a061f38)](https://github.com/Vectorized/solady/blob/a061f38f27cd7ae330a86d42d3f15b4e7237f064/src/utils/UUPSUpgradeable.sol)                           |
