# pragma version ^0.4.3

event ModuleSet:
    module: indexed(address)
    enabled: bool

event MintRecorded:
    asset: indexed(address)
    account: indexed(address)
    principal: uint256
    fee: uint256

event BurnRecorded:
    asset: indexed(address)
    account: indexed(address)
    amount: uint256

event RedemptionRecorded:
    asset: indexed(address)
    account: indexed(address)
    stable_burned: uint256
    collateral_value: uint256

event LiquidationRecorded:
    asset: indexed(address)
    vault_id: indexed(uint256)
    repay_amount: uint256
    seize_value: uint256
    bad_debt: uint256

event InvariantFlagged:
    asset: indexed(address)
    code: bytes32
    observed: uint256
    expected: uint256

BPS: constant(uint256) = 10_000

admin: public(address)
modules: public(HashMap[address, bool])

minted_principal: public(HashMap[address, uint256])
minted_fees: public(HashMap[address, uint256])
burned_principal: public(HashMap[address, uint256])
redeemed_stable: public(HashMap[address, uint256])
redeemed_collateral_value: public(HashMap[address, uint256])
liquidated_debt: public(HashMap[address, uint256])
liquidated_collateral_value: public(HashMap[address, uint256])
bad_debt: public(HashMap[address, uint256])
surplus_value: public(HashMap[address, uint256])
last_accounting_at: public(HashMap[address, uint256])
invariant_flags: public(HashMap[address, uint256])

@deploy
def __init__(_admin: address):
    assert _admin != empty(address), "admin"
    self.admin = _admin
    self.modules[_admin] = True
    log ModuleSet(module=_admin, enabled=True)

@internal
@view
def _only_admin():
    assert msg.sender == self.admin, "admin"

@internal
@view
def _only_module():
    assert self.modules[msg.sender] or msg.sender == self.admin, "module"

@internal
def _touch(asset: address):
    self.last_accounting_at[asset] = block.timestamp

@external
def set_module(module: address, enabled: bool):
    self._only_admin()
    assert module != empty(address), "module"
    self.modules[module] = enabled
    log ModuleSet(module=module, enabled=enabled)

@external
def record_mint(asset: address, account: address, principal: uint256, fee: uint256):
    self._only_module()
    assert asset != empty(address), "asset"
    assert account != empty(address), "account"
    assert principal > 0, "principal"
    self.minted_principal[asset] += principal
    self.minted_fees[asset] += fee
    self._touch(asset)
    log MintRecorded(asset=asset, account=account, principal=principal, fee=fee)

@external
def record_burn(asset: address, account: address, amount: uint256):
    self._only_module()
    assert asset != empty(address), "asset"
    assert account != empty(address), "account"
    assert amount > 0, "amount"
    self.burned_principal[asset] += amount
    self._touch(asset)
    log BurnRecorded(asset=asset, account=account, amount=amount)

@external
def record_redemption(asset: address, account: address, stable_burned: uint256, collateral_value: uint256):
    self._only_module()
    assert asset != empty(address), "asset"
    assert account != empty(address), "account"
    assert stable_burned > 0, "stable"
    self.redeemed_stable[asset] += stable_burned
    self.redeemed_collateral_value[asset] += collateral_value
    self._touch(asset)
    log RedemptionRecorded(
        asset=asset,
        account=account,
        stable_burned=stable_burned,
        collateral_value=collateral_value,
    )

@external
def record_liquidation(asset: address, vault_id: uint256, repay_amount: uint256, seize_value: uint256, bad_debt_delta: uint256):
    self._only_module()
    assert asset != empty(address), "asset"
    assert repay_amount > 0 or bad_debt_delta > 0, "empty"
    self.liquidated_debt[asset] += repay_amount
    self.liquidated_collateral_value[asset] += seize_value
    self.bad_debt[asset] += bad_debt_delta
    self._touch(asset)
    log LiquidationRecorded(
        asset=asset,
        vault_id=vault_id,
        repay_amount=repay_amount,
        seize_value=seize_value,
        bad_debt=bad_debt_delta,
    )

@external
def record_surplus(asset: address, value_delta: uint256):
    self._only_module()
    assert asset != empty(address), "asset"
    self.surplus_value[asset] += value_delta
    self._touch(asset)

@external
def flag_invariant(asset: address, code: bytes32, observed: uint256, expected: uint256):
    self._only_module()
    self.invariant_flags[asset] += 1
    self._touch(asset)
    log InvariantFlagged(asset=asset, code=code, observed=observed, expected=expected)

@external
@view
def gross_issued(asset: address) -> uint256:
    return self.minted_principal[asset] + self.minted_fees[asset]

@external
@view
def net_issued(asset: address) -> uint256:
    gross: uint256 = self.minted_principal[asset] + self.minted_fees[asset]
    retired: uint256 = self.burned_principal[asset] + self.redeemed_stable[asset] + self.liquidated_debt[asset]
    if retired >= gross:
        return 0
    return gross - retired

@external
@view
def redemption_loss(asset: address) -> uint256:
    burned: uint256 = self.redeemed_stable[asset]
    value_out: uint256 = self.redeemed_collateral_value[asset]
    if value_out >= burned:
        return 0
    return burned - value_out

@external
@view
def liquidation_loss(asset: address) -> uint256:
    debt: uint256 = self.liquidated_debt[asset] + self.bad_debt[asset]
    seized: uint256 = self.liquidated_collateral_value[asset]
    if seized >= debt:
        return 0
    return debt - seized

@external
@view
def accounting_snapshot(asset: address) -> (uint256, uint256, uint256, uint256, uint256, uint256):
    return (
        self.minted_principal[asset],
        self.minted_fees[asset],
        self.burned_principal[asset],
        self.redeemed_stable[asset],
        self.redeemed_collateral_value[asset],
        self.bad_debt[asset],
    )

