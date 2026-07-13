# pragma version ^0.4.3

interface IERC20:
    def transfer(receiver: address, amount: uint256) -> bool: nonpayable
    def transferFrom(owner: address, receiver: address, amount: uint256) -> bool: nonpayable
    def balanceOf(owner: address) -> uint256: view

interface IStable:
    def mint(receiver: address, amount: uint256): nonpayable
    def burn_from(owner: address, amount: uint256): nonpayable
    def totalSupply() -> uint256: view

interface IOracle:
    def value_of(asset: address, amount: uint256) -> uint256: view
    def amount_for_value(asset: address, value_e18: uint256) -> uint256: view

interface IRisk:
    def is_market_enabled(asset: address) -> bool: view
    def can_liquidate(asset: address) -> bool: view
    def is_healthy(asset: address, collateral_value: uint256, debt: uint256) -> bool: view
    def is_liquidatable(asset: address, collateral_value: uint256, debt: uint256) -> bool: view
    def issuance_fee(asset: address, amount: uint256) -> uint256: view
    def liquidation_seize_value(asset: address, repay_value: uint256) -> uint256: view
    def debt_within_caps(asset: address, vault_debt: uint256, total_debt: uint256) -> bool: view
    def min_debt(asset: address) -> uint256: view
    def debt_ceiling(asset: address) -> uint256: view

event VaultOpened:
    vault_id: indexed(uint256)
    owner: indexed(address)
    asset: indexed(address)

event CollateralDeposited:
    vault_id: indexed(uint256)
    asset: indexed(address)
    owner: indexed(address)
    amount: uint256

event CollateralWithdrawn:
    vault_id: indexed(uint256)
    asset: indexed(address)
    owner: indexed(address)
    amount: uint256

event StableMinted:
    vault_id: indexed(uint256)
    owner: indexed(address)
    amount: uint256
    fee: uint256

event StableRepaid:
    vault_id: indexed(uint256)
    payer: indexed(address)
    amount: uint256

event VaultLiquidated:
    vault_id: indexed(uint256)
    liquidator: indexed(address)
    repay_amount: uint256
    seized_collateral: uint256

event ReserveReleased:
    asset: indexed(address)
    receiver: indexed(address)
    collateral_amount: uint256
    debt_reduction: uint256

event ModuleUpdated:
    stable: address
    oracle: address
    risk: address
    stability: address

struct Vault:
    owner: address
    asset: address
    collateral: uint256
    debt: uint256
    created_at: uint256
    updated_at: uint256
    liquidated: bool
    closed: bool

WAD: constant(uint256) = 10 ** 18
BPS: constant(uint256) = 10_000
MAX_HEALTH: constant(uint256) = max_value(uint256)

admin: public(address)
guardian: public(address)
stable: public(address)
oracle: public(address)
risk: public(address)
treasury: public(address)
stability_module: public(address)
paused: public(bool)

next_vault_id: public(uint256)
vaults: public(HashMap[uint256, Vault])
owner_vault_count: public(HashMap[address, uint256])
latest_vault_by_owner: public(HashMap[address, uint256])
total_collateral: public(HashMap[address, uint256])
total_debt: public(HashMap[address, uint256])
redemption_debt_offset: public(HashMap[address, uint256])
bad_debt: public(HashMap[address, uint256])
liquidation_count: public(HashMap[address, uint256])

@deploy
def __init__(_stable: address, _oracle: address, _risk: address, _admin: address):
    assert _stable != empty(address), "stable"
    assert _oracle != empty(address), "oracle"
    assert _risk != empty(address), "risk"
    assert _admin != empty(address), "admin"
    self.admin = _admin
    self.guardian = _admin
    self.treasury = _admin
    self.stable = _stable
    self.oracle = _oracle
    self.risk = _risk
    self.next_vault_id = 1
    log ModuleUpdated(stable=_stable, oracle=_oracle, risk=_risk, stability=empty(address))

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
def _only_vault_owner(vault_id: uint256):
    assert self.vaults[vault_id].owner == msg.sender, "owner"
    assert not self.vaults[vault_id].closed, "closed"

@internal
@view
def _collateral_value(asset: address, amount: uint256) -> uint256:
    return staticcall IOracle(self.oracle).value_of(asset, amount)

@internal
@view
def _vault_value(vault_id: uint256) -> uint256:
    asset: address = self.vaults[vault_id].asset
    return self._collateral_value(asset, self.vaults[vault_id].collateral)

@internal
@view
def _reserve_value(asset: address) -> uint256:
    return self._collateral_value(asset, self.total_collateral[asset])

@internal
@view
def _is_healthy(asset: address, collateral: uint256, debt: uint256) -> bool:
    value: uint256 = self._collateral_value(asset, collateral)
    return staticcall IRisk(self.risk).is_healthy(asset, value, debt)

@internal
@view
def _check_caps(asset: address, vault_debt: uint256, asset_debt: uint256):
    ok: bool = staticcall IRisk(self.risk).debt_within_caps(asset, vault_debt, asset_debt)
    assert ok, "caps"

@internal
def _receive_collateral(asset: address, from_account: address, amount: uint256):
    if amount > 0:
        ok: bool = extcall IERC20(asset).transferFrom(from_account, self, amount)
        assert ok, "transferFrom"
        self.total_collateral[asset] += amount

@internal
def _send_collateral(asset: address, receiver: address, amount: uint256):
    if amount > 0:
        assert self.total_collateral[asset] >= amount, "reserve"
        self.total_collateral[asset] -= amount
        ok: bool = extcall IERC20(asset).transfer(receiver, amount)
        assert ok, "transfer"

@internal
def _open_vault_for(owner: address, asset: address) -> uint256:
    assert staticcall IRisk(self.risk).is_market_enabled(asset), "market"
    vault_id: uint256 = self.next_vault_id
    self.next_vault_id += 1
    self.vaults[vault_id] = Vault(
        owner=owner,
        asset=asset,
        collateral=0,
        debt=0,
        created_at=block.timestamp,
        updated_at=block.timestamp,
        liquidated=False,
        closed=False,
    )
    self.owner_vault_count[owner] += 1
    self.latest_vault_by_owner[owner] = vault_id
    log VaultOpened(vault_id=vault_id, owner=owner, asset=asset)
    return vault_id

@external
def set_modules(_stable: address, _oracle: address, _risk: address):
    self._only_admin()
    assert _stable != empty(address), "stable"
    assert _oracle != empty(address), "oracle"
    assert _risk != empty(address), "risk"
    self.stable = _stable
    self.oracle = _oracle
    self.risk = _risk
    log ModuleUpdated(stable=_stable, oracle=_oracle, risk=_risk, stability=self.stability_module)

@external
def set_stability_module(module: address):
    self._only_admin()
    assert module != empty(address), "module"
    self.stability_module = module
    log ModuleUpdated(stable=self.stable, oracle=self.oracle, risk=self.risk, stability=module)

@external
def set_treasury(account: address):
    self._only_admin()
    assert account != empty(address), "treasury"
    self.treasury = account

@external
def set_guardian(account: address):
    self._only_admin()
    assert account != empty(address), "guardian"
    self.guardian = account

@external
def pause():
    self._only_guardian_or_admin()
    self.paused = True

@external
def unpause():
    self._only_admin()
    self.paused = False

@external
def open_vault(asset: address) -> uint256:
    self._not_paused()
    return self._open_vault_for(msg.sender, asset)

@external
def open_deposit_and_mint(asset: address, collateral_amount: uint256, mint_amount: uint256) -> uint256:
    self._not_paused()
    vault_id: uint256 = self._open_vault_for(msg.sender, asset)
    if collateral_amount > 0:
        self._receive_collateral(asset, msg.sender, collateral_amount)
        self.vaults[vault_id].collateral += collateral_amount
        log CollateralDeposited(vault_id=vault_id, asset=asset, owner=msg.sender, amount=collateral_amount)
    if mint_amount > 0:
        fee: uint256 = staticcall IRisk(self.risk).issuance_fee(asset, mint_amount)
        debt_delta: uint256 = mint_amount + fee
        new_debt: uint256 = self.vaults[vault_id].debt + debt_delta
        new_asset_debt: uint256 = self.total_debt[asset] + debt_delta
        self._check_caps(asset, new_debt, new_asset_debt)
        assert self._is_healthy(asset, self.vaults[vault_id].collateral, new_debt), "health"
        self.vaults[vault_id].debt = new_debt
        self.total_debt[asset] = new_asset_debt
        extcall IStable(self.stable).mint(msg.sender, mint_amount)
        if fee > 0:
            extcall IStable(self.stable).mint(self.treasury, fee)
        log StableMinted(vault_id=vault_id, owner=msg.sender, amount=mint_amount, fee=fee)
    self.vaults[vault_id].updated_at = block.timestamp
    return vault_id

@external
def deposit(vault_id: uint256, amount: uint256):
    self._not_paused()
    self._only_vault_owner(vault_id)
    assert amount > 0, "amount"
    asset: address = self.vaults[vault_id].asset
    self._receive_collateral(asset, msg.sender, amount)
    self.vaults[vault_id].collateral += amount
    self.vaults[vault_id].updated_at = block.timestamp
    log CollateralDeposited(vault_id=vault_id, asset=asset, owner=msg.sender, amount=amount)

@external
def withdraw(vault_id: uint256, amount: uint256):
    self._not_paused()
    self._only_vault_owner(vault_id)
    assert amount > 0, "amount"
    assert self.vaults[vault_id].collateral >= amount, "collateral"
    asset: address = self.vaults[vault_id].asset
    new_collateral: uint256 = self.vaults[vault_id].collateral - amount
    debt: uint256 = self.vaults[vault_id].debt
    assert self._is_healthy(asset, new_collateral, debt), "health"
    self.vaults[vault_id].collateral = new_collateral
    self.vaults[vault_id].updated_at = block.timestamp
    self._send_collateral(asset, msg.sender, amount)
    log CollateralWithdrawn(vault_id=vault_id, asset=asset, owner=msg.sender, amount=amount)

@external
def mint(vault_id: uint256, amount: uint256):
    self._not_paused()
    self._only_vault_owner(vault_id)
    assert amount > 0, "amount"
    asset: address = self.vaults[vault_id].asset
    assert staticcall IRisk(self.risk).is_market_enabled(asset), "market"
    fee: uint256 = staticcall IRisk(self.risk).issuance_fee(asset, amount)
    debt_delta: uint256 = amount + fee
    new_debt: uint256 = self.vaults[vault_id].debt + debt_delta
    new_asset_debt: uint256 = self.total_debt[asset] + debt_delta
    self._check_caps(asset, new_debt, new_asset_debt)
    assert self._is_healthy(asset, self.vaults[vault_id].collateral, new_debt), "health"
    self.vaults[vault_id].debt = new_debt
    self.vaults[vault_id].updated_at = block.timestamp
    self.total_debt[asset] = new_asset_debt
    extcall IStable(self.stable).mint(msg.sender, amount)
    if fee > 0:
        extcall IStable(self.stable).mint(self.treasury, fee)
    log StableMinted(vault_id=vault_id, owner=msg.sender, amount=amount, fee=fee)

@external
def repay(vault_id: uint256, amount: uint256):
    self._not_paused()
    assert self.vaults[vault_id].owner != empty(address), "vault"
    assert amount > 0, "amount"
    asset: address = self.vaults[vault_id].asset
    repay_amount: uint256 = amount
    if repay_amount > self.vaults[vault_id].debt:
        repay_amount = self.vaults[vault_id].debt
    assert repay_amount > 0, "repaid"
    extcall IStable(self.stable).burn_from(msg.sender, repay_amount)
    self.vaults[vault_id].debt -= repay_amount
    self.vaults[vault_id].updated_at = block.timestamp
    if repay_amount > self.total_debt[asset]:
        self.total_debt[asset] = 0
    else:
        self.total_debt[asset] -= repay_amount
    log StableRepaid(vault_id=vault_id, payer=msg.sender, amount=repay_amount)

@external
def adjust(vault_id: uint256, deposit_amount: uint256, withdraw_amount: uint256, mint_amount: uint256, repay_amount: uint256):
    self._not_paused()
    self._only_vault_owner(vault_id)
    asset: address = self.vaults[vault_id].asset
    if deposit_amount > 0:
        self._receive_collateral(asset, msg.sender, deposit_amount)
        self.vaults[vault_id].collateral += deposit_amount
        log CollateralDeposited(vault_id=vault_id, asset=asset, owner=msg.sender, amount=deposit_amount)
    if repay_amount > 0:
        debt_before: uint256 = self.vaults[vault_id].debt
        actual_repay: uint256 = repay_amount
        if actual_repay > debt_before:
            actual_repay = debt_before
        if actual_repay > 0:
            extcall IStable(self.stable).burn_from(msg.sender, actual_repay)
            self.vaults[vault_id].debt = debt_before - actual_repay
            if actual_repay > self.total_debt[asset]:
                self.total_debt[asset] = 0
            else:
                self.total_debt[asset] -= actual_repay
            log StableRepaid(vault_id=vault_id, payer=msg.sender, amount=actual_repay)
    if mint_amount > 0:
        fee: uint256 = staticcall IRisk(self.risk).issuance_fee(asset, mint_amount)
        debt_delta: uint256 = mint_amount + fee
        self.vaults[vault_id].debt += debt_delta
        self.total_debt[asset] += debt_delta
        extcall IStable(self.stable).mint(msg.sender, mint_amount)
        if fee > 0:
            extcall IStable(self.stable).mint(self.treasury, fee)
        log StableMinted(vault_id=vault_id, owner=msg.sender, amount=mint_amount, fee=fee)
    if withdraw_amount > 0:
        assert self.vaults[vault_id].collateral >= withdraw_amount, "collateral"
        self.vaults[vault_id].collateral -= withdraw_amount
    self._check_caps(asset, self.vaults[vault_id].debt, self.total_debt[asset])
    assert self._is_healthy(asset, self.vaults[vault_id].collateral, self.vaults[vault_id].debt), "health"
    self.vaults[vault_id].updated_at = block.timestamp
    if withdraw_amount > 0:
        self._send_collateral(asset, msg.sender, withdraw_amount)
        log CollateralWithdrawn(vault_id=vault_id, asset=asset, owner=msg.sender, amount=withdraw_amount)

@external
def close(vault_id: uint256):
    self._not_paused()
    self._only_vault_owner(vault_id)
    assert self.vaults[vault_id].debt == 0, "debt"
    asset: address = self.vaults[vault_id].asset
    amount: uint256 = self.vaults[vault_id].collateral
    self.vaults[vault_id].collateral = 0
    self.vaults[vault_id].closed = True
    self.vaults[vault_id].updated_at = block.timestamp
    self._send_collateral(asset, msg.sender, amount)
    log CollateralWithdrawn(vault_id=vault_id, asset=asset, owner=msg.sender, amount=amount)

@external
def liquidate(vault_id: uint256, repay_amount: uint256):
    self._not_paused()
    assert repay_amount > 0, "amount"
    assert self.vaults[vault_id].owner != empty(address), "vault"
    assert not self.vaults[vault_id].closed, "closed"
    asset: address = self.vaults[vault_id].asset
    assert staticcall IRisk(self.risk).can_liquidate(asset), "liq_paused"
    collateral: uint256 = self.vaults[vault_id].collateral
    debt: uint256 = self.vaults[vault_id].debt
    value: uint256 = self._collateral_value(asset, collateral)
    assert staticcall IRisk(self.risk).is_liquidatable(asset, value, debt), "healthy"
    actual_repay: uint256 = repay_amount
    if actual_repay > debt:
        actual_repay = debt
    extcall IStable(self.stable).burn_from(msg.sender, actual_repay)
    seize_value: uint256 = staticcall IRisk(self.risk).liquidation_seize_value(asset, actual_repay)
    seize_amount: uint256 = staticcall IOracle(self.oracle).amount_for_value(asset, seize_value)
    if seize_amount > collateral:
        seize_amount = collateral
    self.vaults[vault_id].debt = debt - actual_repay
    self.vaults[vault_id].collateral = collateral - seize_amount
    self.vaults[vault_id].updated_at = block.timestamp
    if self.vaults[vault_id].collateral == 0 and self.vaults[vault_id].debt > 0:
        self.bad_debt[asset] += self.vaults[vault_id].debt
        self.vaults[vault_id].debt = 0
        self.vaults[vault_id].liquidated = True
    if actual_repay > self.total_debt[asset]:
        self.total_debt[asset] = 0
    else:
        self.total_debt[asset] -= actual_repay
    self.liquidation_count[asset] += 1
    self._send_collateral(asset, msg.sender, seize_amount)
    log VaultLiquidated(
        vault_id=vault_id,
        liquidator=msg.sender,
        repay_amount=actual_repay,
        seized_collateral=seize_amount,
    )

@external
def release_reserve(asset: address, receiver: address, collateral_amount: uint256, debt_reduction: uint256):
    assert msg.sender == self.stability_module, "stability"
    assert receiver != empty(address), "receiver"
    self._send_collateral(asset, receiver, collateral_amount)
    if debt_reduction > self.total_debt[asset]:
        self.redemption_debt_offset[asset] += self.total_debt[asset]
        self.total_debt[asset] = 0
    else:
        self.total_debt[asset] -= debt_reduction
        self.redemption_debt_offset[asset] += debt_reduction
    log ReserveReleased(
        asset=asset,
        receiver=receiver,
        collateral_amount=collateral_amount,
        debt_reduction=debt_reduction,
    )

@external
@view
def vault_value(vault_id: uint256) -> uint256:
    return self._vault_value(vault_id)

@external
@view
def health_bps(vault_id: uint256) -> uint256:
    debt: uint256 = self.vaults[vault_id].debt
    if debt == 0:
        return MAX_HEALTH
    value: uint256 = self._vault_value(vault_id)
    return value * BPS // debt

@external
@view
def max_withdrawable(vault_id: uint256) -> uint256:
    asset: address = self.vaults[vault_id].asset
    collateral: uint256 = self.vaults[vault_id].collateral
    debt: uint256 = self.vaults[vault_id].debt
    if debt == 0:
        return collateral
    price_value: uint256 = self._collateral_value(asset, collateral)
    min_ratio: uint256 = 0
    # Risk exposes the ratio as a public getter; keeping this view conservative
    # avoids importing every risk field into the vault manager ABI.
    if price_value == 0:
        return 0
    value_per_unit: uint256 = self._collateral_value(asset, WAD)
    if value_per_unit == 0:
        return 0
    required_value: uint256 = debt * 15_000 // BPS
    if price_value <= required_value:
        return 0
    surplus_value: uint256 = price_value - required_value
    withdrawable: uint256 = surplus_value * WAD // value_per_unit
    if withdrawable > collateral:
        return collateral
    return withdrawable

@external
@view
def reserve_value(asset: address) -> uint256:
    return self._reserve_value(asset)

@external
@view
def backing_ratio_bps(asset: address) -> uint256:
    supply: uint256 = staticcall IStable(self.stable).totalSupply()
    if supply == 0:
        return MAX_HEALTH
    value: uint256 = self._reserve_value(asset)
    return value * BPS // supply

@external
@view
def system_snapshot(asset: address) -> (uint256, uint256, uint256, uint256):
    value: uint256 = self._reserve_value(asset)
    supply: uint256 = staticcall IStable(self.stable).totalSupply()
    return (self.total_collateral[asset], value, self.total_debt[asset], supply)
