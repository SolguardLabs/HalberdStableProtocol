# pragma version ^0.4.3

event ParameterQueued:
    key: indexed(bytes32)
    value: uint256
    executable_at: uint256

event ParameterCommitted:
    key: indexed(bytes32)
    old_value: uint256
    new_value: uint256

event ParameterCanceled:
    key: indexed(bytes32)

event WriterSet:
    writer: indexed(address)
    enabled: bool

struct PendingParameter:
    value: uint256
    executable_at: uint256
    exists: bool

admin: public(address)
delay: public(uint256)
writers: public(HashMap[address, bool])
values: public(HashMap[bytes32, uint256])
minimums: public(HashMap[bytes32, uint256])
maximums: public(HashMap[bytes32, uint256])
pending: public(HashMap[bytes32, PendingParameter])
version: public(HashMap[bytes32, uint256])
last_updated: public(HashMap[bytes32, uint256])

@deploy
def __init__(_admin: address):
    assert _admin != empty(address), "admin"
    self.admin = _admin
    self.delay = 300
    self.writers[_admin] = True
    log WriterSet(writer=_admin, enabled=True)

@internal
@view
def _only_admin():
    assert msg.sender == self.admin, "admin"

@internal
@view
def _only_writer():
    assert self.writers[msg.sender] or msg.sender == self.admin, "writer"

@internal
@view
def _within_bounds(key: bytes32, new_value: uint256) -> bool:
    minimum: uint256 = self.minimums[key]
    maximum: uint256 = self.maximums[key]
    if new_value < minimum:
        return False
    if maximum > 0 and new_value > maximum:
        return False
    return True

@external
def set_writer(writer: address, enabled: bool):
    self._only_admin()
    assert writer != empty(address), "writer"
    self.writers[writer] = enabled
    log WriterSet(writer=writer, enabled=enabled)

@external
def set_delay(new_delay: uint256):
    self._only_admin()
    assert new_delay <= 30 * 86_400, "delay"
    self.delay = new_delay

@external
def set_bounds(key: bytes32, minimum: uint256, maximum: uint256):
    self._only_admin()
    assert key != empty(bytes32), "key"
    assert maximum == 0 or maximum >= minimum, "bounds"
    self.minimums[key] = minimum
    self.maximums[key] = maximum
    assert self._within_bounds(key, self.values[key]), "current"

@external
def queue(key: bytes32, new_value: uint256):
    self._only_writer()
    assert key != empty(bytes32), "key"
    assert self._within_bounds(key, new_value), "bounds"
    eta: uint256 = block.timestamp + self.delay
    self.pending[key] = PendingParameter(value=new_value, executable_at=eta, exists=True)
    log ParameterQueued(key=key, value=new_value, executable_at=eta)

@external
def commit(key: bytes32):
    self._only_writer()
    assert self.pending[key].exists, "pending"
    assert block.timestamp >= self.pending[key].executable_at, "eta"
    value: uint256 = self.pending[key].value
    assert self._within_bounds(key, value), "bounds"
    old: uint256 = self.values[key]
    self.values[key] = value
    self.version[key] += 1
    self.last_updated[key] = block.timestamp
    self.pending[key] = PendingParameter(value=0, executable_at=0, exists=False)
    log ParameterCommitted(key=key, old_value=old, new_value=value)

@external
def cancel(key: bytes32):
    self._only_writer()
    assert self.pending[key].exists, "pending"
    self.pending[key] = PendingParameter(value=0, executable_at=0, exists=False)
    log ParameterCanceled(key=key)

@external
def set_immediate(key: bytes32, new_value: uint256):
    self._only_admin()
    assert key != empty(bytes32), "key"
    assert self._within_bounds(key, new_value), "bounds"
    old: uint256 = self.values[key]
    self.values[key] = new_value
    self.version[key] += 1
    self.last_updated[key] = block.timestamp
    log ParameterCommitted(key=key, old_value=old, new_value=new_value)

@external
@view
def pending_state(key: bytes32) -> (bool, uint256, uint256):
    return (self.pending[key].exists, self.pending[key].value, self.pending[key].executable_at)

@external
@view
def parameter_state(key: bytes32) -> (uint256, uint256, uint256, uint256):
    return (self.values[key], self.minimums[key], self.maximums[key], self.version[key])
