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

The contract is deployed at the same address on every supported chain:

`0x001AAd84c21A5CD4d696C56d44866e9703c43F77`

| Chain | Explorer |
|-------|----------|
| Base | [BaseScan](https://basescan.org/address/0x001AAd84c21A5CD4d696C56d44866e9703c43F77) |
| BNB Chain | [BscScan](https://bscscan.com/address/0x001AAd84c21A5CD4d696C56d44866e9703c43F77) |
| Mantle | [MantleScan](https://mantlescan.xyz/address/0x001AAd84c21A5CD4d696C56d44866e9703c43F77) |

## License

MIT
