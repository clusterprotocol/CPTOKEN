// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title CPToken
 * @author Cluster Protocol
 * @notice ERC-20 token with Chainlink CCIP cross-chain support and EIP-3009 gasless transfers.
 *
 * @dev Architecture:
 *  - Home chain (Base): full supply minted to treasury at construction.
 *  - Remote chains: deployed with zero supply; CCIP BurnMintTokenPool handles mint/burn.
 *  - getCCIPAdmin() exposes the admin for Chainlink TokenAdminRegistry registration.
 *  - MINTER_ROLE / BURNER_ROLE are granted to BurnMintTokenPool on each chain.
 *
 * Gasless capabilities:
 *  - ERC-2612 Permit (gasless approvals)
 *  - EIP-3009 transferWithAuthorization / receiveWithAuthorization / cancelAuthorization
 */
contract CPToken is ERC20, ERC20Permit, AccessControl {

    // --- Roles ---

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    // --- Constants ---

    uint256 public constant MAX_SUPPLY = 5_000_000_000 * 1e18;

    bytes32 public constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );

    bytes32 public constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );

    bytes32 public constant CANCEL_AUTHORIZATION_TYPEHASH = keccak256(
        "CancelAuthorization(address authorizer,bytes32 nonce)"
    );

    // --- State ---

    address private _ccipAdmin;
    mapping(address => mapping(bytes32 => bool)) public authorizationState;

    // --- Errors ---

    error AuthorizationAlreadyUsed(address authorizer, bytes32 nonce);
    error AuthorizationNotYetValid(uint256 validAfter, uint256 currentTime);
    error AuthorizationExpired(uint256 validBefore, uint256 currentTime);
    error InvalidSignature(address authorizer);
    error CallerMustBePayee(address caller, address payee);
    error MaxSupplyExceeded(uint256 supplyAfterMint);

    // --- Events ---

    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);
    event AuthorizationCanceled(address indexed authorizer, bytes32 indexed nonce);
    event CCIPAdminTransferred(address indexed previousAdmin, address indexed newAdmin);

    // --- Constructor ---

    /**
     * @param _treasury Recipient of the initial supply. Pass address(0) on remote chains.
     * @param _admin    Admin who manages roles and CCIP registration.
     * @param _initialSupply Amount to mint (MAX_SUPPLY on home chain, 0 on remote chains).
     */
    constructor(
        address _treasury,
        address _admin,
        uint256 _initialSupply
    ) ERC20("Cluster Protocol", "CP") ERC20Permit("Cluster Protocol") {
        require(_admin != address(0), "admin cannot be zero");
        require(_initialSupply <= MAX_SUPPLY, "exceeds max supply");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _ccipAdmin = _admin;

        if (_initialSupply > 0 && _treasury != address(0)) {
            _mint(_treasury, _initialSupply);
        }
    }

    // --- CCIP CCT Interface ---

    function getCCIPAdmin() external view returns (address) {
        return _ccipAdmin;
    }

    function setCCIPAdmin(address newAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newAdmin != address(0), "ccipAdmin cannot be zero");
        address previous = _ccipAdmin;
        _ccipAdmin = newAdmin;
        emit CCIPAdminTransferred(previous, newAdmin);
    }

    function grantMintAndBurnRoles(address pool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(MINTER_ROLE, pool);
        _grantRole(BURNER_ROLE, pool);
    }

    // --- Mint / Burn (CCIP Pool) ---

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (totalSupply() + amount > MAX_SUPPLY) {
            revert MaxSupplyExceeded(totalSupply() + amount);
        }
        _mint(to, amount);
    }

    function burn(uint256 amount) external onlyRole(BURNER_ROLE) {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) external onlyRole(BURNER_ROLE) {
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }

    // --- EIP-3009: Gasless Transfers ---

    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        _requireValidAuthorization(from, validAfter, validBefore, nonce);

        bytes32 structHash = keccak256(abi.encode(
            TRANSFER_WITH_AUTHORIZATION_TYPEHASH,
            from, to, value, validAfter, validBefore, nonce
        ));

        _validateSignature(from, structHash, v, r, s);
        _markAuthorizationUsed(from, nonce);
        _transfer(from, to, value);
    }

    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (msg.sender != to) revert CallerMustBePayee(msg.sender, to);
        _requireValidAuthorization(from, validAfter, validBefore, nonce);

        bytes32 structHash = keccak256(abi.encode(
            RECEIVE_WITH_AUTHORIZATION_TYPEHASH,
            from, to, value, validAfter, validBefore, nonce
        ));

        _validateSignature(from, structHash, v, r, s);
        _markAuthorizationUsed(from, nonce);
        _transfer(from, to, value);
    }

    function cancelAuthorization(
        address authorizer,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (authorizationState[authorizer][nonce]) {
            revert AuthorizationAlreadyUsed(authorizer, nonce);
        }

        bytes32 structHash = keccak256(abi.encode(
            CANCEL_AUTHORIZATION_TYPEHASH,
            authorizer, nonce
        ));

        _validateSignature(authorizer, structHash, v, r, s);
        authorizationState[authorizer][nonce] = true;
        emit AuthorizationCanceled(authorizer, nonce);
    }

    // --- ERC-165 ---

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // --- Internal ---

    function _requireValidAuthorization(
        address authorizer,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    ) internal view {
        if (block.timestamp <= validAfter) {
            revert AuthorizationNotYetValid(validAfter, block.timestamp);
        }
        if (block.timestamp >= validBefore) {
            revert AuthorizationExpired(validBefore, block.timestamp);
        }
        if (authorizationState[authorizer][nonce]) {
            revert AuthorizationAlreadyUsed(authorizer, nonce);
        }
    }

    function _validateSignature(
        address signer,
        bytes32 structHash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal view {
        bytes32 digest = _hashTypedDataV4(structHash);
        address recovered = ECDSA.recover(digest, v, r, s);
        if (recovered != signer) revert InvalidSignature(signer);
    }

    function _markAuthorizationUsed(address authorizer, bytes32 nonce) internal {
        authorizationState[authorizer][nonce] = true;
        emit AuthorizationUsed(authorizer, nonce);
    }
}
