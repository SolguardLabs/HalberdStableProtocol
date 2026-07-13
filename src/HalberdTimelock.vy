# pragma version ^0.4.3

event OperationQueued:
    operation_id: indexed(bytes32)
    target: indexed(address)
    eta: uint256
    data_hash: bytes32

event OperationCanceled:
    operation_id: indexed(bytes32)

event OperationExecuted:
    operation_id: indexed(bytes32)
    executor: indexed(address)

event DelayUpdated:
    old_delay: uint256
    new_delay: uint256

struct Operation:
    target: address
    eta: uint256
    data_hash: bytes32
    predecessor: bytes32
    queued: bool
    executed: bool
    canceled: bool

admin: public(address)
executor: public(address)
min_delay: public(uint256)
grace_period: public(uint256)
operations: public(HashMap[bytes32, Operation])
operation_count: public(uint256)
executed_count: public(uint256)
canceled_count: public(uint256)

@deploy
def __init__(_admin: address, delay: uint256):
    assert _admin != empty(address), "admin"
    assert delay >= 60, "delay"
    self.admin = _admin
    self.executor = _admin
    self.min_delay = delay
    self.grace_period = 7 * 86_400

@internal
@view
def _only_admin():
    assert msg.sender == self.admin, "admin"

@internal
@view
def _only_executor():
    assert msg.sender == self.executor or msg.sender == self.admin, "executor"

@internal
@view
def _is_ready(operation_id: bytes32) -> bool:
    op: Operation = self.operations[operation_id]
    if not op.queued or op.executed or op.canceled:
        return False
    if op.predecessor != empty(bytes32) and not self.operations[op.predecessor].executed:
        return False
    if block.timestamp < op.eta:
        return False
    if block.timestamp > op.eta + self.grace_period:
        return False
    return True

@external
def set_executor(account: address):
    self._only_admin()
    assert account != empty(address), "executor"
    self.executor = account

@external
def set_delay(new_delay: uint256):
    self._only_admin()
    assert new_delay >= 60, "delay"
    old: uint256 = self.min_delay
    self.min_delay = new_delay
    log DelayUpdated(old_delay=old, new_delay=new_delay)

@external
def set_grace_period(period: uint256):
    self._only_admin()
    assert period >= self.min_delay, "period"
    self.grace_period = period

@external
def queue(operation_id: bytes32, target: address, data_hash: bytes32, predecessor: bytes32) -> uint256:
    self._only_admin()
    assert operation_id != empty(bytes32), "id"
    assert target != empty(address), "target"
    assert not self.operations[operation_id].queued, "queued"
    eta: uint256 = block.timestamp + self.min_delay
    self.operations[operation_id] = Operation(
        target=target,
        eta=eta,
        data_hash=data_hash,
        predecessor=predecessor,
        queued=True,
        executed=False,
        canceled=False,
    )
    self.operation_count += 1
    log OperationQueued(operation_id=operation_id, target=target, eta=eta, data_hash=data_hash)
    return eta

@external
def cancel(operation_id: bytes32):
    self._only_admin()
    assert self.operations[operation_id].queued, "operation"
    assert not self.operations[operation_id].executed, "executed"
    assert not self.operations[operation_id].canceled, "canceled"
    self.operations[operation_id].canceled = True
    self.canceled_count += 1
    log OperationCanceled(operation_id=operation_id)

@external
def mark_executed(operation_id: bytes32):
    self._only_executor()
    assert self._is_ready(operation_id), "ready"
    self.operations[operation_id].executed = True
    self.executed_count += 1
    log OperationExecuted(operation_id=operation_id, executor=msg.sender)

@external
@view
def is_ready(operation_id: bytes32) -> bool:
    return self._is_ready(operation_id)

@external
@view
def is_expired(operation_id: bytes32) -> bool:
    op: Operation = self.operations[operation_id]
    if not op.queued or op.executed or op.canceled:
        return False
    return block.timestamp > op.eta + self.grace_period

@external
@view
def operation_state(operation_id: bytes32) -> (address, uint256, bool, bool, bool):
    op: Operation = self.operations[operation_id]
    return (op.target, op.eta, op.queued, op.executed, op.canceled)
