# pragma version ^0.4.3

event BreakerConfigured:
    asset: indexed(address)
    drawdown_bps: uint256
    volume_limit: uint256
    window_seconds: uint256

event BreakerTripped:
    asset: indexed(address)
    reason: bytes32
    until: uint256

event VolumeRecorded:
    asset: indexed(address)
    account: indexed(address)
    amount: uint256
    window_volume: uint256

BPS: constant(uint256) = 10_000

admin: public(address)
guardian: public(address)

drawdown_limit_bps: public(HashMap[address, uint256])
volume_limit: public(HashMap[address, uint256])
window_seconds: public(HashMap[address, uint256])
last_price: public(HashMap[address, uint256])
window_start: public(HashMap[address, uint256])
window_volume: public(HashMap[address, uint256])
tripped_until: public(HashMap[address, uint256])
tripped_reason: public(HashMap[address, bytes32])
reporters: public(HashMap[address, bool])

@deploy
def __init__(_admin: address):
    assert _admin != empty(address), "admin"
    self.admin = _admin
    self.guardian = _admin
    self.reporters[_admin] = True

@internal
@view
def _only_admin():
    assert msg.sender == self.admin, "admin"

@internal
@view
def _only_reporter():
    assert self.reporters[msg.sender] or msg.sender == self.guardian or msg.sender == self.admin, "reporter"

@external
def set_reporter(account: address, enabled: bool):
    self._only_admin()
    self.reporters[account] = enabled

@external
def configure(asset: address, drawdown_bps: uint256, max_volume: uint256, window: uint256):
    self._only_admin()
    assert asset != empty(address), "asset"
    assert drawdown_bps <= BPS, "drawdown"
    assert window > 0, "window"
    self.drawdown_limit_bps[asset] = drawdown_bps
    self.volume_limit[asset] = max_volume
    self.window_seconds[asset] = window
    log BreakerConfigured(asset=asset, drawdown_bps=drawdown_bps, volume_limit=max_volume, window_seconds=window)

@external
def record_price(asset: address, price: uint256):
    self._only_reporter()
    assert price > 0, "price"
    old: uint256 = self.last_price[asset]
    limit: uint256 = self.drawdown_limit_bps[asset]
    if old > 0 and limit > 0 and price < old:
        drawdown: uint256 = (old - price) * BPS // old
        if drawdown > limit:
            self.tripped_until[asset] = block.timestamp + self.window_seconds[asset]
            self.tripped_reason[asset] = keccak256("PRICE_DRAWDOWN")
            log BreakerTripped(asset=asset, reason=self.tripped_reason[asset], until=self.tripped_until[asset])
    self.last_price[asset] = price

@external
def record_volume(asset: address, account: address, amount: uint256):
    self._only_reporter()
    window: uint256 = self.window_seconds[asset]
    if window == 0:
        return
    if block.timestamp > self.window_start[asset] + window:
        self.window_start[asset] = block.timestamp
        self.window_volume[asset] = 0
    self.window_volume[asset] += amount
    if self.volume_limit[asset] > 0 and self.window_volume[asset] > self.volume_limit[asset]:
        self.tripped_until[asset] = block.timestamp + window
        self.tripped_reason[asset] = keccak256("VOLUME_LIMIT")
        log BreakerTripped(asset=asset, reason=self.tripped_reason[asset], until=self.tripped_until[asset])
    log VolumeRecorded(asset=asset, account=account, amount=amount, window_volume=self.window_volume[asset])

@external
def clear(asset: address):
    self._only_admin()
    self.tripped_until[asset] = 0
    self.tripped_reason[asset] = empty(bytes32)

@external
@view
def is_tripped(asset: address) -> bool:
    return self.tripped_until[asset] > block.timestamp

@external
@view
def breaker_state(asset: address) -> (bool, uint256, bytes32, uint256):
    return (
        self.tripped_until[asset] > block.timestamp,
        self.tripped_until[asset],
        self.tripped_reason[asset],
        self.window_volume[asset],
    )

