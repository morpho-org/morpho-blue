// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./HandlersTest.sol";

contract InvariantTest is HandlersTest {
    bytes4[] internal selectors;

    function setUp() public virtual override {
        super.setUp();

        _targetSenders();

        _weightSelector(this.mine.selector, 100);

        targetContract(address(this));
        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));
    }

    function _targetSenders() internal virtual {
        _targetSender(_addrFromHashedString("Sender1"));
        _targetSender(_addrFromHashedString("Sender2"));
        _targetSender(_addrFromHashedString("Sender3"));
        _targetSender(_addrFromHashedString("Sender4"));
        _targetSender(_addrFromHashedString("Sender5"));
        _targetSender(_addrFromHashedString("Sender6"));
        _targetSender(_addrFromHashedString("Sender7"));
        _targetSender(_addrFromHashedString("Sender8"));
    }

    function _targetSender(address sender) internal {
        targetSender(sender);

        vm.startPrank(sender);
        loanToken.approve(address(morpho), type(uint256).max);
        collateralToken.approve(address(morpho), type(uint256).max);
        vm.stopPrank();
    }

    function _weightSelector(bytes4 selector, uint256 weight) internal {
        for (uint256 i; i < weight; ++i) {
            selectors.push(selector);
        }
    }

    /* SELECTED FUNCTIONS */

    function mine(uint256 blocks) external {
        blocks = bound(blocks, 1, 50_400);

        _forward(blocks);
    }
}
