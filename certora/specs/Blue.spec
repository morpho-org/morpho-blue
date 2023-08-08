methods {
    function supply(Blue.Market, uint256, address, bytes) external;

    function _.borrowRate(Blue.Market) external => DISPATCHER(true);

    // function _.safeTransfer(address, uint256) internal => DISPATCHER(true);
    // function _.safeTransferFrom(address, address, uint256) internal => DISPATCHER(true);
}

rule supplyRevertZero(Blue.Market market) {
    env e;
    bytes b;

    supply@withrevert(e, market, 0, e.msg.sender, b);

    assert lastReverted;
}
