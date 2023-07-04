// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {EIP712_NAME, EIP712_APPROVAL_TYPEHASH} from "./libraries/Constants.sol";
import {SignedApproval} from "./libraries/Types.sol";
import {Events} from "./libraries/Events.sol";
import {InsufficientAllowance} from "./libraries/Errors.sol";

import {ERC712} from "@morpho-utils/ERC712.sol";

abstract contract AllowanceBase is ERC712 {
    mapping(address => mapping(address => uint256)) private _allowances;

    constructor() ERC712(EIP712_NAME) {}

    /* EXTERNAL */

    function approve(address manager, uint256 newAllowance) external {
        _approve(msg.sender, manager, newAllowance);
    }

    function approveWithSig(SignedApproval calldata approval, Signature calldata signature) external {
        bytes32 dataHash = keccak256(
            abi.encode(
                EIP712_APPROVAL_TYPEHASH,
                approval.delegator,
                approval.manager,
                approval.allowance,
                approval.nonce,
                approval.deadline
            )
        );
        _verify(signature, dataHash, approval.nonce, approval.deadline, approval.delegator);

        _approve(approval.delegator, approval.manager, approval.allowance);
    }

    /* PUBLIC */

    function allowance(address delegator, address manager) public view returns (uint256) {
        return _allowances[delegator][manager];
    }

    /* INTERNAL */

    // TODO: douple-spend ERC20-like vulnerability: increase/decreaseAllowance instead?
    function _approve(address delegator, address manager, uint256 newAllowance) internal {
        _allowances[delegator][manager] = newAllowance;

        emit Events.Approval(delegator, manager, newAllowance);
    }

    function _spendAllowance(address delegator, address manager, uint256 assets) internal {
        if (delegator == manager) return;

        uint256 currentAllowance = allowance(delegator, manager);

        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < assets) revert InsufficientAllowance(currentAllowance);

            unchecked {
                // Cannot underflow: currentAllowance >= assets checked above.
                _approve(delegator, manager, currentAllowance - assets);
            }
        }
    }
}
