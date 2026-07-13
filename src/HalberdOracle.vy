# pragma version ^0.4.3

event FeedSet:
    asset: indexed(address)
    price: uint256
    heartbeat: uint256
    max_deviation_bps: uint256

event PricePushed:
    asset: indexed(address)
    old_price: uint256
    new_price: uint256
    version: uint256

event PriceProposed:
    asset: indexed(address)
    price: uint256
    executable_at: uint256

event FeedPaused:
    asset: indexed(address)
    paused: bool

event GuardianUpdated:
    guardian: indexed(address)

WAD: constant(uint256) = 10 ** 18
BPS: constant(uint256) = 10_000
MIN_DELAY: constant(uint256) = 60
MAX_PRICE: constant(uint256) = 1_000_000_000 * 10 ** 18

admin: public(address)
guardian: public(address)

price_e18: public(HashMap[address, uint256])
last_updated: public(HashMap[address, uint256])
heartbeat: public(HashMap[address, uint256])
max_deviation_bps: public(HashMap[address, uint256])
version: public(HashMap[address, uint256])
enabled: public(HashMap[address, bool])
stale: public(HashMap[address, bool])

pending_price: public(HashMap[address, uint256])
pending_eta: public(HashMap[address, uint256])
manual_override: public(HashMap[address, bool])

@deploy
def __init__(_admin: address):
    assert _admin != empty(address), "admin"
    self.admin = _admin
    self.guardian = _admin

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
def _validate_price(price: uint256):
    assert price > 0, "price"
    assert price <= MAX_PRICE, "price_max"

@internal
@view
def _within_deviation(asset: address, new_price: uint256) -> bool:
    old_price: uint256 = self.price_e18[asset]
    if old_price == 0:
        return True
    max_bps: uint256 = self.max_deviation_bps[asset]
    if max_bps == 0:
        return True
    delta: uint256 = 0
    if new_price > old_price:
        delta = new_price - old_price
    else:
        delta = old_price - new_price
    return delta * BPS <= old_price * max_bps

@internal
@view
def _get_price(asset: address) -> uint256:
    assert self.enabled[asset], "enabled"
    assert not self.stale[asset], "stale"
    hb: uint256 = self.heartbeat[asset]
    if hb > 0:
        assert block.timestamp <= self.last_updated[asset] + hb, "heartbeat"
    return self.price_e18[asset]

@external
def set_feed(asset: address, price: uint256, heartbeat_seconds: uint256, max_deviation: uint256):
    self._only_admin()
    assert asset != empty(address), "asset"
    self._validate_price(price)
    assert max_deviation <= BPS, "deviation"
    self.price_e18[asset] = price
    self.last_updated[asset] = block.timestamp
    self.heartbeat[asset] = heartbeat_seconds
    self.max_deviation_bps[asset] = max_deviation
    self.enabled[asset] = True
    self.stale[asset] = False
    self.version[asset] += 1
    log FeedSet(asset=asset, price=price, heartbeat=heartbeat_seconds, max_deviation_bps=max_deviation)

@external
def push_price(asset: address, new_price: uint256):
    self._only_guardian_or_admin()
    assert self.enabled[asset], "enabled"
    self._validate_price(new_price)
    assert self._within_deviation(asset, new_price) or msg.sender == self.admin, "deviation"
    old: uint256 = self.price_e18[asset]
    self.price_e18[asset] = new_price
    self.last_updated[asset] = block.timestamp
    self.stale[asset] = False
    self.version[asset] += 1
    log PricePushed(asset=asset, old_price=old, new_price=new_price, version=self.version[asset])

@external
def propose_price(asset: address, new_price: uint256):
    self._only_guardian_or_admin()
    assert self.enabled[asset], "enabled"
    self._validate_price(new_price)
    self.pending_price[asset] = new_price
    self.pending_eta[asset] = block.timestamp + MIN_DELAY
    log PriceProposed(asset=asset, price=new_price, executable_at=self.pending_eta[asset])

@external
def commit_price(asset: address):
    self._only_admin()
    price: uint256 = self.pending_price[asset]
    assert price > 0, "pending"
    assert block.timestamp >= self.pending_eta[asset], "eta"
    old: uint256 = self.price_e18[asset]
    self.price_e18[asset] = price
    self.last_updated[asset] = block.timestamp
    self.stale[asset] = False
    self.pending_price[asset] = 0
    self.pending_eta[asset] = 0
    self.version[asset] += 1
    log PricePushed(asset=asset, old_price=old, new_price=price, version=self.version[asset])

@external
def cancel_price(asset: address):
    self._only_guardian_or_admin()
    self.pending_price[asset] = 0
    self.pending_eta[asset] = 0

@external
def pause_feed(asset: address):
    self._only_guardian_or_admin()
    self.stale[asset] = True
    log FeedPaused(asset=asset, paused=True)

@external
def unpause_feed(asset: address):
    self._only_admin()
    assert self.enabled[asset], "enabled"
    self.stale[asset] = False
    self.last_updated[asset] = block.timestamp
    log FeedPaused(asset=asset, paused=False)

@external
def disable_feed(asset: address):
    self._only_admin()
    self.enabled[asset] = False
    self.stale[asset] = True
    log FeedPaused(asset=asset, paused=True)

@external
def set_guardian(account: address):
    self._only_admin()
    assert account != empty(address), "guardian"
    self.guardian = account
    log GuardianUpdated(guardian=account)

@external
def set_manual_override(asset: address, enabled_override: bool):
    self._only_admin()
    self.manual_override[asset] = enabled_override

@external
@view
def get_price(asset: address) -> uint256:
    return self._get_price(asset)

@external
@view
def value_of(asset: address, amount: uint256) -> uint256:
    price: uint256 = self._get_price(asset)
    return amount * price // WAD

@external
@view
def amount_for_value(asset: address, value_e18: uint256) -> uint256:
    price: uint256 = self._get_price(asset)
    assert price > 0, "price"
    return value_e18 * WAD // price

@external
@view
def is_live(asset: address) -> bool:
    if not self.enabled[asset]:
        return False
    if self.stale[asset]:
        return False
    hb: uint256 = self.heartbeat[asset]
    if hb > 0 and block.timestamp > self.last_updated[asset] + hb:
        return False
    return True

@external
@view
def deviation_from_last(asset: address, proposed: uint256) -> uint256:
    old_price: uint256 = self.price_e18[asset]
    if old_price == 0:
        return 0
    if proposed >= old_price:
        return (proposed - old_price) * BPS // old_price
    return (old_price - proposed) * BPS // old_price

@external
@view
def feed_status(asset: address) -> (bool, bool, uint256, uint256, uint256):
    return (
        self.enabled[asset],
        self.stale[asset],
        self.price_e18[asset],
        self.last_updated[asset],
        self.version[asset],
    )
