# pragma version ^0.4.3

WAD: constant(uint256) = 10 ** 18
BPS: constant(uint256) = 10_000

@external
@pure
def wad_mul(a: uint256, b: uint256) -> uint256:
    return a * b // WAD

@external
@pure
def wad_div(a: uint256, b: uint256) -> uint256:
    assert b > 0, "div"
    return a * WAD // b

@external
@pure
def bps_mul(a: uint256, bps: uint256) -> uint256:
    return a * bps // BPS

@external
@pure
def ratio_bps(numerator: uint256, denominator: uint256) -> uint256:
    if denominator == 0:
        return max_value(uint256)
    return numerator * BPS // denominator

@external
@pure
def min(a: uint256, b: uint256) -> uint256:
    if a < b:
        return a
    return b

@external
@pure
def max(a: uint256, b: uint256) -> uint256:
    if a > b:
        return a
    return b

@external
@pure
def ceil_div(a: uint256, b: uint256) -> uint256:
    assert b > 0, "div"
    if a == 0:
        return 0
    return (a - 1) // b + 1

@external
@pure
def pro_rata(amount: uint256, numerator: uint256, denominator: uint256) -> uint256:
    if denominator == 0:
        return 0
    return amount * numerator // denominator

@external
@pure
def bounded_sub(a: uint256, b: uint256) -> uint256:
    if b >= a:
        return 0
    return a - b

@external
@pure
def health_after_delta(collateral_value: uint256, debt: uint256, value_delta: int256, debt_delta: int256) -> uint256:
    adjusted_value: uint256 = collateral_value
    adjusted_debt: uint256 = debt
    if value_delta < 0:
        loss: uint256 = convert(-value_delta, uint256)
        if loss >= adjusted_value:
            adjusted_value = 0
        else:
            adjusted_value -= loss
    else:
        adjusted_value += convert(value_delta, uint256)
    if debt_delta < 0:
        repay: uint256 = convert(-debt_delta, uint256)
        if repay >= adjusted_debt:
            adjusted_debt = 0
        else:
            adjusted_debt -= repay
    else:
        adjusted_debt += convert(debt_delta, uint256)
    if adjusted_debt == 0:
        return max_value(uint256)
    return adjusted_value * BPS // adjusted_debt

