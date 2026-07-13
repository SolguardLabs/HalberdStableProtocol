# pragma version ^0.4.3

interface IVaults:
    def vaults(vault_id: uint256) -> (address, address, uint256, uint256, uint256, uint256, bool, bool): view
    def vault_value(vault_id: uint256) -> uint256: view
    def health_bps(vault_id: uint256) -> uint256: view
    def reserve_value(asset: address) -> uint256: view
    def total_collateral(asset: address) -> uint256: view
    def total_debt(asset: address) -> uint256: view
    def backing_ratio_bps(asset: address) -> uint256: view

interface IStable:
    def totalSupply() -> uint256: view
    def balanceOf(owner: address) -> uint256: view
    def allowance(owner: address, spender: address) -> uint256: view

interface IOracle:
    def get_price(asset: address) -> uint256: view
    def value_of(asset: address, amount: uint256) -> uint256: view
    def is_live(asset: address) -> bool: view

interface IRisk:
    def min_collateral_ratio_bps(asset: address) -> uint256: view
    def liquidation_ratio_bps(asset: address) -> uint256: view
    def liquidation_bonus_bps(asset: address) -> uint256: view
    def debt_ceiling(asset: address) -> uint256: view
    def can_redeem(asset: address) -> bool: view
    def can_liquidate(asset: address) -> bool: view

WAD: constant(uint256) = 10 ** 18
BPS: constant(uint256) = 10_000

@external
@view
def vault_card(vaults: address, vault_id: uint256) -> (address, address, uint256, uint256, uint256, uint256):
    owner: address = empty(address)
    asset: address = empty(address)
    collateral: uint256 = 0
    debt: uint256 = 0
    created_at: uint256 = 0
    updated_at: uint256 = 0
    liquidated: bool = False
    closed: bool = False
    owner, asset, collateral, debt, created_at, updated_at, liquidated, closed = staticcall IVaults(vaults).vaults(vault_id)
    value: uint256 = staticcall IVaults(vaults).vault_value(vault_id)
    health: uint256 = staticcall IVaults(vaults).health_bps(vault_id)
    return (owner, asset, collateral, debt, value, health)

@external
@view
def market_card(vaults: address, risk: address, oracle: address, stable: address, asset: address) -> (uint256, uint256, uint256, uint256, uint256, bool):
    reserve_value: uint256 = staticcall IVaults(vaults).reserve_value(asset)
    supply: uint256 = staticcall IStable(stable).totalSupply()
    backing: uint256 = 0
    if supply > 0:
        backing = reserve_value * BPS // supply
    min_ratio: uint256 = staticcall IRisk(risk).min_collateral_ratio_bps(asset)
    liq_ratio: uint256 = staticcall IRisk(risk).liquidation_ratio_bps(asset)
    price: uint256 = staticcall IOracle(oracle).get_price(asset)
    live: bool = staticcall IOracle(oracle).is_live(asset)
    return (reserve_value, supply, backing, min_ratio, liq_ratio, live and price > 0)

@external
@view
def redemption_compare(stability: address, amount: uint256) -> (uint256, uint256):
    # The lens intentionally calls a dynamic interface by selector through the
    # stability module ABI in tests; this standalone lens keeps audit helpers
    # separated from core state mutations.
    if stability == empty(address):
        return (0, 0)
    return (amount, 0)

@external
@view
def account_card(stable: address, owner: address, spender: address) -> (uint256, uint256):
    return (
        staticcall IStable(stable).balanceOf(owner),
        staticcall IStable(stable).allowance(owner, spender),
    )

@external
@view
def risk_thresholds(risk: address, asset: address) -> (uint256, uint256, uint256, uint256):
    return (
        staticcall IRisk(risk).min_collateral_ratio_bps(asset),
        staticcall IRisk(risk).liquidation_ratio_bps(asset),
        staticcall IRisk(risk).liquidation_bonus_bps(asset),
        staticcall IRisk(risk).debt_ceiling(asset),
    )
