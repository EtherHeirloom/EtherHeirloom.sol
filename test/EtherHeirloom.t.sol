pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../contracts/EtherHeirloom.sol";

contract EtherHeirloomTest is Test {
    EtherHeirloom public etherHeirloom;

    function setUp() public {
        etherHeirloom = new EtherHeirloom();
    }

    function test_deployment() public view {
        assertNotEq(address(etherHeirloom), address(0));
    }

    // TODO: Add more tests here
}
