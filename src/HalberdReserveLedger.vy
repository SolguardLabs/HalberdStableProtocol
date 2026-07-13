# pragma version ^0.4.3

event ReserveIncreased:
    asset: indexed(address)
    account: indexed(address)
    amount: uint256
    value: uint256

event ReserveDecreased:
    asset: indexed(address)
    account: indexed(address)
    amount: uint256
    value: uint256

event LiabilityChanged:
    asset: indexed(address)
    delta: int256
    new_liability: uint256

event HaircutRecorded:
    asset: indexed(address)
    stable_amount: uint256
    value_shortfall: uint256

BPS: constant(uint256) = 10_000

admin: public(address)
modules: public(HashMap[address, bool])

reserve_amount: public(HashMap[address, uint256])
reserve_value: public(HashMap[address, uint256])
liability_value: public(HashMap[address, uint256])
haircut_value: public(HashMap[address, uint256])
released_value: public(HashMap[address, uint256])
last_snapshot_at: public(HashMap[address, uint256])
snapshot_reserve_value: public(HashMap[address, uint256])
snapshot_liability_value: public(HashMap[address, uint256])

@deploy
def __init__(_admin: address):
    assert _admin != empty(address), "admin"
    self.admin = _admin
    self.modules[_admin] = True

@internal
@view
def _only_admin():
    assert msg.sender == self.admin, "admin"

@internal
@view
def _only_module():
    assert self.modules[msg.sender] or msg.sender == self.admin, "module"

@external
def set_module(module: address, enabled: bool):
    self._only_admin()
    assert module != empty(address), "module"
    self.modules[module] = enabled

@external
def increase_reserve(asset: address, account: address, amount: uint256, value_delta: uint256):
    self._only_module()
    assert asset != empty(address), "asset"
    self.reserve_amount[asset] += amount
    self.reserve_value[asset] += value_delta
    log ReserveIncreased(asset=asset, account=account, amount=amount, value=value_delta)

@external
def decrease_reserve(asset: address, account: address, amount: uint256, value_delta: uint256):
    self._only_module()
    assert asset != empty(address), "asset"
    if amount >= self.reserve_amount[asset]:
        self.reserve_amount[asset] = 0
    else:
        self.reserve_amount[asset] -= amount
    if value_delta >= self.reserve_value[asset]:
        self.reserve_value[asset] = 0
    else:
        self.reserve_value[asset] -= value_delta
    self.released_value[asset] += value_delta
    log ReserveDecreased(asset=asset, account=account, amount=amount, value=value_delta)

@external
def increase_liability(asset: address, value_delta: uint256):
    self._only_module()
    assert asset != empty(address), "asset"
    self.liability_value[asset] += value_delta
    log LiabilityChanged(asset=asset, delta=convert(value_delta, int256), new_liability=self.liability_value[asset])

@external
def decrease_liability(asset: address, value_delta: uint256):
    self._only_module()
    assert asset != empty(address), "asset"
    if value_delta >= self.liability_value[asset]:
        self.liability_value[asset] = 0
    else:
        self.liability_value[asset] -= value_delta
    log LiabilityChanged(asset=asset, delta=-convert(value_delta, int256), new_liability=self.liability_value[asset])

@external
def record_haircut(asset: address, stable_amount: uint256, value_shortfall: uint256):
    self._only_module()
    assert asset != empty(address), "asset"
    self.haircut_value[asset] += value_shortfall
    log HaircutRecorded(asset=asset, stable_amount=stable_amount, value_shortfall=value_shortfall)

@external
def snapshot(asset: address):
    self._only_module()
    self.last_snapshot_at[asset] = block.timestamp
    self.snapshot_reserve_value[asset] = self.reserve_value[asset]
    self.snapshot_liability_value[asset] = self.liability_value[asset]

@external
@view
def backing_ratio_bps(asset: address) -> uint256:
    liability: uint256 = self.liability_value[asset]
    if liability == 0:
        return max_value(uint256)
    return self.reserve_value[asset] * BPS // liability

@external
@view
def reserve_shortfall(asset: address) -> uint256:
    if self.reserve_value[asset] >= self.liability_value[asset]:
        return 0
    return self.liability_value[asset] - self.reserve_value[asset]

@external
@view
def snapshot_delta(asset: address) -> (int256, int256):
    reserve_now: uint256 = self.reserve_value[asset]
    liability_now: uint256 = self.liability_value[asset]
    reserve_then: uint256 = self.snapshot_reserve_value[asset]
    liability_then: uint256 = self.snapshot_liability_value[asset]
    reserve_delta: int256 = 0
    liability_delta: int256 = 0
    if reserve_now >= reserve_then:
        reserve_delta = convert(reserve_now - reserve_then, int256)
    else:
        reserve_delta = -convert(reserve_then - reserve_now, int256)
    if liability_now >= liability_then:
        liability_delta = convert(liability_now - liability_then, int256)
    else:
        liability_delta = -convert(liability_then - liability_now, int256)
    return (reserve_delta, liability_delta)

@external
@view
def ledger_snapshot(asset: address) -> (uint256, uint256, uint256, uint256, uint256):
    return (
        self.reserve_amount[asset],
        self.reserve_value[asset],
        self.liability_value[asset],
        self.haircut_value[asset],
        self.released_value[asset],
    )
