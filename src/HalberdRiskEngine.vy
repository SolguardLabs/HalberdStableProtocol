# pragma version ^0.4.3

event MarketConfigured:
    asset: indexed(address)
    min_ratio_bps: uint256
    liquidation_ratio_bps: uint256
    liquidation_bonus_bps: uint256

event FeeConfigured:
    asset: indexed(address)
    issuance_fee_bps: uint256
    redemption_fee_bps: uint256

event CapConfigured:
    asset: indexed(address)
    debt_ceiling: uint256
    min_debt: uint256
    max_vault_debt: uint256

event MarketStatus:
    asset: indexed(address)
    enabled: bool
    minting_paused: bool
    redemption_paused: bool

BPS: constant(uint256) = 10_000
MAX_RATIO: constant(uint256) = 100_000
MAX_FEE_BPS: constant(uint256) = 1_000

admin: public(address)

enabled: public(HashMap[address, bool])
minting_paused: public(HashMap[address, bool])
redemption_paused: public(HashMap[address, bool])
liquidation_paused: public(HashMap[address, bool])

min_collateral_ratio_bps: public(HashMap[address, uint256])
liquidation_ratio_bps: public(HashMap[address, uint256])
liquidation_bonus_bps: public(HashMap[address, uint256])
issuance_fee_bps: public(HashMap[address, uint256])
redemption_fee_bps: public(HashMap[address, uint256])
debt_ceiling: public(HashMap[address, uint256])
min_debt: public(HashMap[address, uint256])
max_vault_debt: public(HashMap[address, uint256])
keeper_incentive_bps: public(HashMap[address, uint256])
shutdown_discount_bps: public(HashMap[address, uint256])

@deploy
def __init__(_admin: address):
    assert _admin != empty(address), "admin"
    self.admin = _admin

@internal
@view
def _only_admin():
    assert msg.sender == self.admin, "admin"

@internal
@view
def _valid_ratios(min_ratio: uint256, liq_ratio: uint256, bonus: uint256):
    assert liq_ratio >= BPS, "liq_low"
    assert min_ratio >= liq_ratio, "min_low"
    assert min_ratio <= MAX_RATIO, "min_high"
    assert bonus <= 2_500, "bonus"

@external
def configure_market(
    asset: address,
    min_ratio: uint256,
    liq_ratio: uint256,
    bonus: uint256,
    debt_cap: uint256,
    min_position_debt: uint256,
    max_position_debt: uint256,
):
    self._only_admin()
    assert asset != empty(address), "asset"
    self._valid_ratios(min_ratio, liq_ratio, bonus)
    assert debt_cap > 0, "debt_cap"
    assert max_position_debt == 0 or max_position_debt <= debt_cap, "max_debt"
    self.enabled[asset] = True
    self.min_collateral_ratio_bps[asset] = min_ratio
    self.liquidation_ratio_bps[asset] = liq_ratio
    self.liquidation_bonus_bps[asset] = bonus
    self.debt_ceiling[asset] = debt_cap
    self.min_debt[asset] = min_position_debt
    self.max_vault_debt[asset] = max_position_debt
    log MarketConfigured(
        asset=asset,
        min_ratio_bps=min_ratio,
        liquidation_ratio_bps=liq_ratio,
        liquidation_bonus_bps=bonus,
    )
    log CapConfigured(
        asset=asset,
        debt_ceiling=debt_cap,
        min_debt=min_position_debt,
        max_vault_debt=max_position_debt,
    )

@external
def set_ratios(asset: address, min_ratio: uint256, liq_ratio: uint256, bonus: uint256):
    self._only_admin()
    assert self.enabled[asset], "enabled"
    self._valid_ratios(min_ratio, liq_ratio, bonus)
    self.min_collateral_ratio_bps[asset] = min_ratio
    self.liquidation_ratio_bps[asset] = liq_ratio
    self.liquidation_bonus_bps[asset] = bonus
    log MarketConfigured(
        asset=asset,
        min_ratio_bps=min_ratio,
        liquidation_ratio_bps=liq_ratio,
        liquidation_bonus_bps=bonus,
    )

@external
def set_fees(asset: address, issuance_fee: uint256, redemption_fee: uint256):
    self._only_admin()
    assert self.enabled[asset], "enabled"
    assert issuance_fee <= MAX_FEE_BPS, "issuance_fee"
    assert redemption_fee <= MAX_FEE_BPS, "redemption_fee"
    self.issuance_fee_bps[asset] = issuance_fee
    self.redemption_fee_bps[asset] = redemption_fee
    log FeeConfigured(asset=asset, issuance_fee_bps=issuance_fee, redemption_fee_bps=redemption_fee)

@external
def set_caps(asset: address, debt_cap: uint256, min_position_debt: uint256, max_position_debt: uint256):
    self._only_admin()
    assert self.enabled[asset], "enabled"
    assert debt_cap > 0, "debt_cap"
    assert max_position_debt == 0 or max_position_debt <= debt_cap, "max_debt"
    self.debt_ceiling[asset] = debt_cap
    self.min_debt[asset] = min_position_debt
    self.max_vault_debt[asset] = max_position_debt
    log CapConfigured(
        asset=asset,
        debt_ceiling=debt_cap,
        min_debt=min_position_debt,
        max_vault_debt=max_position_debt,
    )

@external
def set_market_status(asset: address, market_enabled: bool, pause_minting: bool, pause_redemption: bool):
    self._only_admin()
    self.enabled[asset] = market_enabled
    self.minting_paused[asset] = pause_minting
    self.redemption_paused[asset] = pause_redemption
    log MarketStatus(
        asset=asset,
        enabled=market_enabled,
        minting_paused=pause_minting,
        redemption_paused=pause_redemption,
    )

@external
def set_liquidation_pause(asset: address, paused: bool):
    self._only_admin()
    self.liquidation_paused[asset] = paused

@external
def set_keeper_incentive(asset: address, incentive_bps: uint256):
    self._only_admin()
    assert incentive_bps <= 500, "incentive"
    self.keeper_incentive_bps[asset] = incentive_bps

@external
def set_shutdown_discount(asset: address, discount_bps: uint256):
    self._only_admin()
    assert discount_bps <= 5_000, "discount"
    self.shutdown_discount_bps[asset] = discount_bps

@external
@view
def is_market_enabled(asset: address) -> bool:
    return self.enabled[asset] and not self.minting_paused[asset]

@external
@view
def can_redeem(asset: address) -> bool:
    return self.enabled[asset] and not self.redemption_paused[asset]

@external
@view
def can_liquidate(asset: address) -> bool:
    return self.enabled[asset] and not self.liquidation_paused[asset]

@external
@view
def collateral_ratio_bps(collateral_value: uint256, debt: uint256) -> uint256:
    if debt == 0:
        return MAX_RATIO
    return collateral_value * BPS // debt

@external
@view
def max_mintable_debt(asset: address, collateral_value: uint256) -> uint256:
    ratio: uint256 = self.min_collateral_ratio_bps[asset]
    assert ratio > 0, "ratio"
    return collateral_value * BPS // ratio

@external
@view
def is_healthy(asset: address, collateral_value: uint256, debt: uint256) -> bool:
    if debt == 0:
        return True
    ratio: uint256 = self.min_collateral_ratio_bps[asset]
    assert ratio > 0, "ratio"
    return collateral_value * BPS >= debt * ratio

@external
@view
def is_liquidatable(asset: address, collateral_value: uint256, debt: uint256) -> bool:
    if debt == 0:
        return False
    ratio: uint256 = self.liquidation_ratio_bps[asset]
    assert ratio > 0, "ratio"
    return collateral_value * BPS < debt * ratio

@external
@view
def issuance_fee(asset: address, amount: uint256) -> uint256:
    return amount * self.issuance_fee_bps[asset] // BPS

@external
@view
def redemption_fee(asset: address, amount: uint256) -> uint256:
    return amount * self.redemption_fee_bps[asset] // BPS

@external
@view
def liquidation_seize_value(asset: address, repay_value: uint256) -> uint256:
    return repay_value * (BPS + self.liquidation_bonus_bps[asset]) // BPS

@external
@view
def keeper_reward_value(asset: address, repay_value: uint256) -> uint256:
    return repay_value * self.keeper_incentive_bps[asset] // BPS

@external
@view
def debt_within_caps(asset: address, vault_debt: uint256, total_debt: uint256) -> bool:
    if total_debt > self.debt_ceiling[asset]:
        return False
    max_position: uint256 = self.max_vault_debt[asset]
    if max_position > 0 and vault_debt > max_position:
        return False
    min_position: uint256 = self.min_debt[asset]
    if vault_debt > 0 and vault_debt < min_position:
        return False
    return True

@external
@view
def market_summary(asset: address) -> (bool, uint256, uint256, uint256, uint256, uint256):
    return (
        self.enabled[asset],
        self.min_collateral_ratio_bps[asset],
        self.liquidation_ratio_bps[asset],
        self.liquidation_bonus_bps[asset],
        self.debt_ceiling[asset],
        self.max_vault_debt[asset],
    )

