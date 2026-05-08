# Uniswap V3 Protocol (Foundry)

This workspace contains a Foundry-based deployment flow for Uniswap V3 core and periphery contracts.

## Prerequisites

- Foundry installed
- Local chain for testing (Anvil)

## Build

```sh
forge build
```

## Test

```sh
forge test
```

## Local Deployment (DeployV3)

Start Anvil in one terminal:

```sh
anvil
```

Run deployment in another terminal:

```sh
PRIVATE_KEY="<private_key>" \
WETH9_ADDRESS="<weth9_address>" \
NATIVE_CURRENCY_LABEL="ETH" \
V2_CORE_FACTORY_ADDRESS="<v2_factory_address>" \
OWNER_ADDRESS="<owner_address>" \
forge script script/DeployV3.s.sol --broadcast --rpc-url http://127.0.0.1:8545 --skip-simulation
```

## Environment Variables

- `PRIVATE_KEY`: EOA private key used for broadcasting transactions.
- `WETH9_ADDRESS`: WETH9 contract address used by periphery contracts.
- `NATIVE_CURRENCY_LABEL`: Native currency label as a string (for example `ETH`).
- `V2_CORE_FACTORY_ADDRESS`: V2 factory address used for metadata/logging context.
- `OWNER_ADDRESS`: Final owner for UniswapV3Factory and ProxyAdmin ownership transfers.

Notes:

- `NATIVE_CURRENCY_LABEL` is converted to `bytes32` inside `script/DeployV3.s.sol`.
- Label must be between 1 and 32 bytes.

## Deployment Outputs

After a successful broadcast, Foundry writes output files to:

- `broadcast/DeployV3.s.sol/<chain_id>/run-latest.json`
- `cache/DeployV3.s.sol/<chain_id>/run-latest.json`

## Foundry Docs

- https://book.getfoundry.sh/
