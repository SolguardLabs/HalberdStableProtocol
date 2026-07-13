# pragma version ^0.4.3

event Checkpoint:
    key: indexed(bytes32)
    actor: indexed(address)
    value_a: uint256
    value_b: uint256
    timestamp: uint256

event Finding:
    key: indexed(bytes32)
    severity: uint256
    detail: bytes32
    value: uint256

event WatcherSet:
    watcher: indexed(address)
    enabled: bool

admin: public(address)
watchers: public(HashMap[address, bool])
checkpoint_count: public(HashMap[bytes32, uint256])
finding_count: public(HashMap[bytes32, uint256])
last_value_a: public(HashMap[bytes32, uint256])
last_value_b: public(HashMap[bytes32, uint256])
last_actor: public(HashMap[bytes32, address])
last_checkpoint_at: public(HashMap[bytes32, uint256])
max_observed: public(HashMap[bytes32, uint256])
min_observed: public(HashMap[bytes32, uint256])
severity_total: public(HashMap[bytes32, uint256])

@deploy
def __init__(_admin: address):
    assert _admin != empty(address), "admin"
    self.admin = _admin
    self.watchers[_admin] = True
    log WatcherSet(watcher=_admin, enabled=True)

@internal
@view
def _only_admin():
    assert msg.sender == self.admin, "admin"

@internal
@view
def _only_watcher():
    assert self.watchers[msg.sender] or msg.sender == self.admin, "watcher"

@external
def set_watcher(watcher: address, enabled: bool):
    self._only_admin()
    assert watcher != empty(address), "watcher"
    self.watchers[watcher] = enabled
    log WatcherSet(watcher=watcher, enabled=enabled)

@external
def checkpoint(key: bytes32, actor: address, value_a: uint256, value_b: uint256):
    self._only_watcher()
    assert key != empty(bytes32), "key"
    self.checkpoint_count[key] += 1
    self.last_value_a[key] = value_a
    self.last_value_b[key] = value_b
    self.last_actor[key] = actor
    self.last_checkpoint_at[key] = block.timestamp
    if self.checkpoint_count[key] == 1:
        self.max_observed[key] = value_a
        self.min_observed[key] = value_a
    else:
        if value_a > self.max_observed[key]:
            self.max_observed[key] = value_a
        if value_a < self.min_observed[key]:
            self.min_observed[key] = value_a
    log Checkpoint(key=key, actor=actor, value_a=value_a, value_b=value_b, timestamp=block.timestamp)

@external
def finding(key: bytes32, severity: uint256, detail: bytes32, observed_value: uint256):
    self._only_watcher()
    assert key != empty(bytes32), "key"
    assert severity <= 4, "severity"
    self.finding_count[key] += 1
    self.severity_total[key] += severity
    log Finding(key=key, severity=severity, detail=detail, value=observed_value)

@external
def assert_minimum(key: bytes32, observed: uint256, minimum: uint256, detail: bytes32):
    self._only_watcher()
    if observed < minimum:
        self.finding_count[key] += 1
        self.severity_total[key] += 2
        log Finding(key=key, severity=2, detail=detail, value=observed)

@external
def assert_maximum(key: bytes32, observed: uint256, maximum: uint256, detail: bytes32):
    self._only_watcher()
    if observed > maximum:
        self.finding_count[key] += 1
        self.severity_total[key] += 2
        log Finding(key=key, severity=2, detail=detail, value=observed)

@external
def assert_equal(key: bytes32, observed: uint256, expected: uint256, detail: bytes32):
    self._only_watcher()
    if observed != expected:
        self.finding_count[key] += 1
        self.severity_total[key] += 1
        log Finding(key=key, severity=1, detail=detail, value=observed)

@external
@view
def average_severity(key: bytes32) -> uint256:
    count: uint256 = self.finding_count[key]
    if count == 0:
        return 0
    return self.severity_total[key] // count

@external
@view
def observed_range(key: bytes32) -> (uint256, uint256):
    return (self.min_observed[key], self.max_observed[key])

@external
@view
def hook_state(key: bytes32) -> (uint256, uint256, address, uint256):
    return (
        self.checkpoint_count[key],
        self.finding_count[key],
        self.last_actor[key],
        self.last_checkpoint_at[key],
    )
