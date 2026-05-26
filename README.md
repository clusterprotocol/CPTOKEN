# CP Token

ERC-20 token contract for [Cluster Protocol](https://clusterprotocol.ai).

## Contract

`src/CPToken.sol` — Solidity 0.8.24

## Features

- Fixed max supply: 5,000,000,000 CP
- Chainlink CCIP CCT-compatible (BurnMintTokenPool)
- EIP-2612 Permit (gasless approvals)
- EIP-3009 transferWithAuthorization / receiveWithAuthorization (gasless transfers)
- Role-based access control for cross-chain mint/burn

## Compile

```bash
forge build
```

## Deployments

| Chain | Address |
|-------|---------|
| Base | `0x8a5bEd7aB6B7F6b280Fa4551e5b2D75B5acBC611` |
| BNB Chain | `0x8a5bEd7aB6B7F6b280Fa4551e5b2D75B5acBC611` |
| Mantle | `0x8a5bEd7aB6B7F6b280Fa4551e5b2D75B5acBC611` |

## License

MIT
