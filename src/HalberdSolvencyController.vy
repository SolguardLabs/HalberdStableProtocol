# pragma version ^0.4.3

event PolicyConfigured:
    reserve_haircut_bps: uint256
    liquidation_recovery_bps: uint256
    capital_buffer_bps: uint256
    target_coverage_bps: uint256
    concentration_limit_bps: uint256
    version: uint256

event GuardianUpdated:
    guardian: indexed(address)

struct SolvencyView:
    stressed_reserve: uint256
    recovered_collateral: uint256
    capital_buffer: uint256
    total_resources: uint256
    total_obligations: uint256
    net_liquidity: uint256
    liquidity_gap: uint256
    coverage_bps: uint256
    concentration_bps: uint256
    band: uint256

BPS: constant(uint256) = 10_000
MAX_TARGET_BPS: constant(uint256) = 50_000

admin: public(address)
guardian: public(address)
reserve_haircut_bps: public(uint256)
liquidation_recovery_bps: public(uint256)
capital_buffer_bps: public(uint256)
target_coverage_bps: public(uint256)
concentration_limit_bps: public(uint256)
policy_version: public(uint256)

@deploy
def __init__(_admin: address):
    assert _admin != empty(address), "admin"
    self.admin = _admin
    self.guardian = _admin
    self.reserve_haircut_bps = 1_000
    self.liquidation_recovery_bps = 7_500
    self.capital_buffer_bps = 750
    self.target_coverage_bps = 12_500
    self.concentration_limit_bps = 4_000
    self.policy_version = 1

@internal
@view
def _only_admin():
    assert msg.sender == self.admin, "admin"

@internal
@pure
def _valid_bps(rate: uint256):
    assert rate <= BPS, "bps"

@internal
@view
def _project(
    reserve_value: uint256,
    circulating_supply: uint256,
    queued_redemptions: uint256,
    recoverable_collateral: uint256,
    recognized_bad_debt: uint256,
    largest_bucket_value: uint256,
) -> SolvencyView:
    stressed_reserve: uint256 = reserve_value * (BPS - self.reserve_haircut_bps) // BPS
    recovered_collateral: uint256 = recoverable_collateral * self.liquidation_recovery_bps // BPS
    capital_buffer: uint256 = circulating_supply * self.capital_buffer_bps // BPS
    resources: uint256 = stressed_reserve + recovered_collateral
    obligations: uint256 = circulating_supply + queued_redemptions + recognized_bad_debt + capital_buffer
    net_liquidity: uint256 = 0
    liquidity_gap: uint256 = 0
    if resources >= obligations:
        net_liquidity = resources - obligations
    else:
        liquidity_gap = obligations - resources

    coverage_bps: uint256 = max_value(uint256)
    if obligations > 0:
        coverage_bps = resources * BPS // obligations

    denominator: uint256 = reserve_value + recoverable_collateral
    concentration_bps: uint256 = 0
    if denominator > 0:
        concentration_bps = largest_bucket_value * BPS // denominator
        if concentration_bps > BPS:
            concentration_bps = BPS

    band: uint256 = 3
    if liquidity_gap > 0:
        band = 0
    elif coverage_bps < self.target_coverage_bps:
        band = 1
    elif concentration_bps > self.concentration_limit_bps:
        band = 2

    return SolvencyView(
        stressed_reserve=stressed_reserve,
        recovered_collateral=recovered_collateral,
        capital_buffer=capital_buffer,
        total_resources=resources,
        total_obligations=obligations,
        net_liquidity=net_liquidity,
        liquidity_gap=liquidity_gap,
        coverage_bps=coverage_bps,
        concentration_bps=concentration_bps,
        band=band,
    )

@external
def set_guardian(account: address):
    self._only_admin()
    assert account != empty(address), "guardian"
    self.guardian = account
    log GuardianUpdated(guardian=account)

@external
def configure(
    reserve_haircut: uint256,
    liquidation_recovery: uint256,
    capital_buffer: uint256,
    target_coverage: uint256,
    concentration_limit: uint256,
):
    self._only_admin()
    self._valid_bps(reserve_haircut)
    self._valid_bps(liquidation_recovery)
    self._valid_bps(capital_buffer)
    self._valid_bps(concentration_limit)
    assert target_coverage >= BPS, "target_low"
    assert target_coverage <= MAX_TARGET_BPS, "target_high"
    self.reserve_haircut_bps = reserve_haircut
    self.liquidation_recovery_bps = liquidation_recovery
    self.capital_buffer_bps = capital_buffer
    self.target_coverage_bps = target_coverage
    self.concentration_limit_bps = concentration_limit
    self.policy_version += 1
    log PolicyConfigured(
        reserve_haircut_bps=reserve_haircut,
        liquidation_recovery_bps=liquidation_recovery,
        capital_buffer_bps=capital_buffer,
        target_coverage_bps=target_coverage,
        concentration_limit_bps=concentration_limit,
        version=self.policy_version,
    )

@external
@view
def project(
    reserve_value: uint256,
    circulating_supply: uint256,
    queued_redemptions: uint256,
    recoverable_collateral: uint256,
    recognized_bad_debt: uint256,
    largest_bucket_value: uint256,
) -> SolvencyView:
    return self._project(
        reserve_value,
        circulating_supply,
        queued_redemptions,
        recoverable_collateral,
        recognized_bad_debt,
        largest_bucket_value,
    )

@external
@view
def mint_headroom(
    reserve_value: uint256,
    circulating_supply: uint256,
    recoverable_collateral: uint256,
) -> uint256:
    stressed_reserve: uint256 = reserve_value * (BPS - self.reserve_haircut_bps) // BPS
    recovered_collateral: uint256 = recoverable_collateral * self.liquidation_recovery_bps // BPS
    resources: uint256 = stressed_reserve + recovered_collateral
    supported_supply: uint256 = resources * BPS // self.target_coverage_bps
    if supported_supply <= circulating_supply:
        return 0
    return supported_supply - circulating_supply

@external
@view
def recapitalization_required(
    reserve_value: uint256,
    circulating_supply: uint256,
    queued_redemptions: uint256,
    recoverable_collateral: uint256,
    recognized_bad_debt: uint256,
) -> uint256:
    view: SolvencyView = self._project(
        reserve_value,
        circulating_supply,
        queued_redemptions,
        recoverable_collateral,
        recognized_bad_debt,
        0,
    )
    return view.liquidity_gap
