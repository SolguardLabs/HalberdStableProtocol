# pragma version ^0.4.3

interface IStable:
    def transfer(receiver: address, amount: uint256) -> bool: nonpayable
    def transferFrom(owner: address, receiver: address, amount: uint256) -> bool: nonpayable
    def burn(amount: uint256): nonpayable
    def balanceOf(owner: address) -> uint256: view
    def totalSupply() -> uint256: view

interface IVaults:
    def reserve_value(asset: address) -> uint256: view
    def total_collateral(asset: address) -> uint256: view
    def release_reserve(asset: address, receiver: address, collateral_amount: uint256, debt_reduction: uint256): nonpayable

interface IOracle:
    def amount_for_value(asset: address, value_e18: uint256) -> uint256: view
    def value_of(asset: address, amount: uint256) -> uint256: view

interface IRisk:
    def can_redeem(asset: address) -> bool: view
    def redemption_fee(asset: address, amount: uint256) -> uint256: view

event StableDeposited:
    account: indexed(address)
    amount: uint256
    shares: uint256

event StableWithdrawn:
    account: indexed(address)
    amount: uint256
    shares: uint256

event Redemption:
    redeemer: indexed(address)
    asset: indexed(address)
    stable_amount: uint256
    collateral_out: uint256
    payout_value: uint256
    reserve_value_before: uint256
    supply_before: uint256

event LossAbsorbed:
    asset: indexed(address)
    debt_amount: uint256
    collateral_value: uint256

event ModulePaused:
    paused: bool

WAD: constant(uint256) = 10 ** 18
BPS: constant(uint256) = 10_000
MAX_CHUNK_BPS: constant(uint256) = 10_000

admin: public(address)
guardian: public(address)
stable: public(address)
vaults: public(address)
oracle: public(address)
risk: public(address)
asset: public(address)
treasury: public(address)
paused: public(bool)

total_pool_shares: public(uint256)
total_stable_deposits: public(uint256)
deposits: public(HashMap[address, uint256])
shares: public(HashMap[address, uint256])
loss_index: public(uint256)
redemption_count: public(uint256)
redeemed_value: public(uint256)
redeemed_stable: public(uint256)
last_redeem_at: public(HashMap[address, uint256])

@deploy
def __init__(_stable: address, _vaults: address, _oracle: address, _risk: address, _asset: address, _admin: address):
    assert _stable != empty(address), "stable"
    assert _vaults != empty(address), "vaults"
    assert _oracle != empty(address), "oracle"
    assert _risk != empty(address), "risk"
    assert _asset != empty(address), "asset"
    assert _admin != empty(address), "admin"
    self.stable = _stable
    self.vaults = _vaults
    self.oracle = _oracle
    self.risk = _risk
    self.asset = _asset
    self.admin = _admin
    self.guardian = _admin
    self.treasury = _admin

@internal
@view
def _only_admin():
    assert msg.sender == self.admin, "admin"

@internal
@view
def _only_guardian_or_admin():
    assert msg.sender == self.admin or msg.sender == self.guardian, "guardian"

@internal
@view
def _not_paused():
    assert not self.paused, "paused"

@internal
@view
def _pool_to_shares(amount: uint256) -> uint256:
    if self.total_pool_shares == 0 or self.total_stable_deposits == 0:
        return amount
    return amount * self.total_pool_shares // self.total_stable_deposits

@internal
@view
def _shares_to_pool(share_amount: uint256) -> uint256:
    if self.total_pool_shares == 0:
        return 0
    return share_amount * self.total_stable_deposits // self.total_pool_shares

@internal
@view
def _pro_rata_deficit_quote(stable_amount: uint256, supply_before: uint256, reserve_value_before: uint256) -> uint256:
    if supply_before == 0:
        return 0
    if reserve_value_before >= supply_before:
        return stable_amount
    return stable_amount * reserve_value_before // supply_before

@internal
@view
def _deficit_redemption_quote(stable_amount: uint256, supply_before: uint256, reserve_value_before: uint256) -> uint256:
    if supply_before == 0:
        return 0
    if reserve_value_before >= supply_before:
        return stable_amount
    base: uint256 = stable_amount * reserve_value_before // supply_before
    deficit: uint256 = supply_before - reserve_value_before
    remaining_after_burn: uint256 = 0
    if supply_before > stable_amount:
        remaining_after_burn = supply_before - stable_amount
    relief: uint256 = stable_amount * deficit * remaining_after_burn // supply_before // supply_before
    payout: uint256 = base + relief
    if payout > reserve_value_before:
        return reserve_value_before
    return payout

@external
def set_guardian(account: address):
    self._only_admin()
    assert account != empty(address), "guardian"
    self.guardian = account

@external
def set_treasury(account: address):
    self._only_admin()
    assert account != empty(address), "treasury"
    self.treasury = account

@external
def pause():
    self._only_guardian_or_admin()
    self.paused = True
    log ModulePaused(paused=True)

@external
def unpause():
    self._only_admin()
    self.paused = False
    log ModulePaused(paused=False)

@external
def deposit(amount: uint256):
    self._not_paused()
    assert amount > 0, "amount"
    pool_shares: uint256 = self._pool_to_shares(amount)
    assert pool_shares > 0, "shares"
    ok: bool = extcall IStable(self.stable).transferFrom(msg.sender, self, amount)
    assert ok, "transferFrom"
    self.deposits[msg.sender] += amount
    self.shares[msg.sender] += pool_shares
    self.total_stable_deposits += amount
    self.total_pool_shares += pool_shares
    log StableDeposited(account=msg.sender, amount=amount, shares=pool_shares)

@external
def withdraw(share_amount: uint256):
    self._not_paused()
    assert share_amount > 0, "amount"
    assert self.shares[msg.sender] >= share_amount, "shares"
    amount: uint256 = self._shares_to_pool(share_amount)
    assert amount > 0, "amount"
    self.shares[msg.sender] -= share_amount
    self.total_pool_shares -= share_amount
    if amount > self.deposits[msg.sender]:
        self.deposits[msg.sender] = 0
    else:
        self.deposits[msg.sender] -= amount
    self.total_stable_deposits -= amount
    ok: bool = extcall IStable(self.stable).transfer(msg.sender, amount)
    assert ok, "transfer"
    log StableWithdrawn(account=msg.sender, amount=amount, shares=share_amount)

@external
def absorb_loss(debt_amount: uint256, collateral_value: uint256):
    self._only_guardian_or_admin()
    assert debt_amount > 0, "debt"
    burn_amount: uint256 = debt_amount
    if burn_amount > self.total_stable_deposits:
        burn_amount = self.total_stable_deposits
    if burn_amount > 0:
        extcall IStable(self.stable).burn(burn_amount)
        self.total_stable_deposits -= burn_amount
        if self.total_stable_deposits == 0:
            self.total_pool_shares = 0
        self.loss_index += burn_amount
    log LossAbsorbed(asset=self.asset, debt_amount=debt_amount, collateral_value=collateral_value)

@external
def redeem(stable_amount: uint256, min_collateral_out: uint256) -> uint256:
    self._not_paused()
    assert staticcall IRisk(self.risk).can_redeem(self.asset), "redeem"
    assert stable_amount > 0, "amount"
    supply_before: uint256 = staticcall IStable(self.stable).totalSupply()
    assert supply_before >= stable_amount, "supply"
    reserve_value_before: uint256 = staticcall IVaults(self.vaults).reserve_value(self.asset)
    max_chunk: uint256 = supply_before * MAX_CHUNK_BPS // BPS
    assert max_chunk == 0 or stable_amount <= max_chunk or msg.sender == self.admin, "chunk"
    ok: bool = extcall IStable(self.stable).transferFrom(msg.sender, self, stable_amount)
    assert ok, "transferFrom"
    extcall IStable(self.stable).burn(stable_amount)
    payout_value: uint256 = self._deficit_redemption_quote(stable_amount, supply_before, reserve_value_before)
    fee: uint256 = staticcall IRisk(self.risk).redemption_fee(self.asset, payout_value)
    if fee > 0:
        payout_value -= fee
    collateral_out: uint256 = staticcall IOracle(self.oracle).amount_for_value(self.asset, payout_value)
    assert collateral_out >= min_collateral_out, "slippage"
    available: uint256 = staticcall IVaults(self.vaults).total_collateral(self.asset)
    if collateral_out > available:
        collateral_out = available
    extcall IVaults(self.vaults).release_reserve(self.asset, msg.sender, collateral_out, stable_amount)
    self.redemption_count += 1
    self.redeemed_value += payout_value
    self.redeemed_stable += stable_amount
    self.last_redeem_at[msg.sender] = block.timestamp
    log Redemption(
        redeemer=msg.sender,
        asset=self.asset,
        stable_amount=stable_amount,
        collateral_out=collateral_out,
        payout_value=payout_value,
        reserve_value_before=reserve_value_before,
        supply_before=supply_before,
    )
    return collateral_out

@external
@view
def preview_redeem(stable_amount: uint256) -> (uint256, uint256):
    supply_before: uint256 = staticcall IStable(self.stable).totalSupply()
    reserve_value_before: uint256 = staticcall IVaults(self.vaults).reserve_value(self.asset)
    payout_value: uint256 = self._deficit_redemption_quote(stable_amount, supply_before, reserve_value_before)
    collateral_out: uint256 = staticcall IOracle(self.oracle).amount_for_value(self.asset, payout_value)
    return (payout_value, collateral_out)

@external
@view
def preview_redeem_pro_rata(stable_amount: uint256) -> (uint256, uint256):
    supply_before: uint256 = staticcall IStable(self.stable).totalSupply()
    reserve_value_before: uint256 = staticcall IVaults(self.vaults).reserve_value(self.asset)
    payout_value: uint256 = self._pro_rata_deficit_quote(stable_amount, supply_before, reserve_value_before)
    collateral_out: uint256 = staticcall IOracle(self.oracle).amount_for_value(self.asset, payout_value)
    return (payout_value, collateral_out)

@external
@view
def pool_assets(account: address) -> (uint256, uint256):
    return (self.deposits[account], self.shares[account])

@external
@view
def redemption_state() -> (uint256, uint256, uint256, uint256):
    supply: uint256 = staticcall IStable(self.stable).totalSupply()
    reserve_value: uint256 = staticcall IVaults(self.vaults).reserve_value(self.asset)
    return (supply, reserve_value, self.redeemed_stable, self.redeemed_value)

@external
@view
def backing_ratio_bps() -> uint256:
    supply: uint256 = staticcall IStable(self.stable).totalSupply()
    if supply == 0:
        return max_value(uint256)
    reserve_value: uint256 = staticcall IVaults(self.vaults).reserve_value(self.asset)
    return reserve_value * BPS // supply
