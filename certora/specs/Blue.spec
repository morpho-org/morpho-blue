methods {
    function supply(Blue.Market, uint256 amount) external;


    function _.borrowRate(Blue.Market) external returns (uint256) => DISPATCH(true);

    function _.safeTransfer(address, uint256) internal returns (bool) envfree => DISPATCH(true);
    function _.safeTransferFrom(address, address, uint256) internal returns (bool) envfree => DISPATCH(true);
}

rule supplyRevertZero(Blue.Market market) {
    env e;

    supply@withrevert(market, 0);

    assert lastReverted;
}
