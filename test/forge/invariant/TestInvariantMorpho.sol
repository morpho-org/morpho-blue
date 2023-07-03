// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/helpers/LocalInvariantTest.sol";

contract TestInvariantMorpho is LocalInvariantTest {
    using Math for uint256;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeTransferLib for ERC20;

    function setUp() public virtual override {
        super.setUp();

        _targetDefaultSenders();

        _weightSelector(this.deposit.selector, 1);

        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));

        address[] memory senders = targetSenders();
        for (uint256 i; i < senders.length; ++i) {
            address sender = senders[i];

            weth.setBalance(sender, type(uint256).max);
            usdc.setBalance(sender, type(uint256).max);
        }
    }

    /* FUNCTIONS */

    function deposit(uint256 amount, address onBehalf) external {
        onBehalf = _randomSender(onBehalf);

        vm.prank(msg.sender); // Cannot startPrank because `morpho.deposit` may revert and not call stopPrank.
        ERC20(usdc).safeApprove(address(morpho), amount);

        vm.prank(msg.sender);
        morpho.deposit(marketKey, TrancheId.wrap(0), amount, onBehalf);
    }

    // /* INVARIANTS */

    function invariantBalanceOf() public {
        assertEq(morpho.liquidity(marketKey, TrancheId.wrap(0)), ERC20(usdc).balanceOf(address(morpho)));
    }
}
