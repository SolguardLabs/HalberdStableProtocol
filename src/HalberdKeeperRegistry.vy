# pragma version ^0.4.3

event KeeperSet:
    keeper: indexed(address)
    enabled: bool

event JobCreated:
    job_id: indexed(uint256)
    target: indexed(address)
    selector_hash: bytes32
    interval: uint256

event JobExecuted:
    job_id: indexed(uint256)
    keeper: indexed(address)
    executed_at: uint256

event KeeperHeartbeat:
    keeper: indexed(address)
    timestamp: uint256

struct Job:
    target: address
    selector_hash: bytes32
    interval: uint256
    last_execution: uint256
    bounty: uint256
    active: bool

admin: public(address)
next_job_id: public(uint256)
keepers: public(HashMap[address, bool])
keeper_heartbeat: public(HashMap[address, uint256])
keeper_executions: public(HashMap[address, uint256])
jobs: public(HashMap[uint256, Job])
job_failures: public(HashMap[uint256, uint256])
job_successes: public(HashMap[uint256, uint256])

@deploy
def __init__(_admin: address):
    assert _admin != empty(address), "admin"
    self.admin = _admin
    self.next_job_id = 1
    self.keepers[_admin] = True
    log KeeperSet(keeper=_admin, enabled=True)

@internal
@view
def _only_admin():
    assert msg.sender == self.admin, "admin"

@internal
@view
def _only_keeper():
    assert self.keepers[msg.sender] or msg.sender == self.admin, "keeper"

@external
def set_keeper(keeper: address, enabled: bool):
    self._only_admin()
    assert keeper != empty(address), "keeper"
    self.keepers[keeper] = enabled
    log KeeperSet(keeper=keeper, enabled=enabled)

@external
def create_job(target: address, selector_hash: bytes32, interval: uint256, bounty: uint256) -> uint256:
    self._only_admin()
    assert target != empty(address), "target"
    assert interval > 0, "interval"
    job_id: uint256 = self.next_job_id
    self.next_job_id += 1
    self.jobs[job_id] = Job(
        target=target,
        selector_hash=selector_hash,
        interval=interval,
        last_execution=0,
        bounty=bounty,
        active=True,
    )
    log JobCreated(job_id=job_id, target=target, selector_hash=selector_hash, interval=interval)
    return job_id

@external
def set_job_active(job_id: uint256, active: bool):
    self._only_admin()
    assert self.jobs[job_id].target != empty(address), "job"
    self.jobs[job_id].active = active

@external
def set_job_interval(job_id: uint256, interval: uint256):
    self._only_admin()
    assert self.jobs[job_id].target != empty(address), "job"
    assert interval > 0, "interval"
    self.jobs[job_id].interval = interval

@external
def heartbeat():
    self._only_keeper()
    self.keeper_heartbeat[msg.sender] = block.timestamp
    log KeeperHeartbeat(keeper=msg.sender, timestamp=block.timestamp)

@external
def mark_executed(job_id: uint256):
    self._only_keeper()
    assert self.jobs[job_id].target != empty(address), "job"
    assert self.jobs[job_id].active, "inactive"
    assert block.timestamp >= self.jobs[job_id].last_execution + self.jobs[job_id].interval, "early"
    self.jobs[job_id].last_execution = block.timestamp
    self.job_successes[job_id] += 1
    self.keeper_executions[msg.sender] += 1
    self.keeper_heartbeat[msg.sender] = block.timestamp
    log JobExecuted(job_id=job_id, keeper=msg.sender, executed_at=block.timestamp)

@external
def mark_failed(job_id: uint256):
    self._only_keeper()
    assert self.jobs[job_id].target != empty(address), "job"
    self.job_failures[job_id] += 1
    self.keeper_heartbeat[msg.sender] = block.timestamp

@external
@view
def can_execute(job_id: uint256) -> bool:
    if self.jobs[job_id].target == empty(address):
        return False
    if not self.jobs[job_id].active:
        return False
    return block.timestamp >= self.jobs[job_id].last_execution + self.jobs[job_id].interval

@external
@view
def keeper_score(keeper: address) -> uint256:
    if not self.keepers[keeper]:
        return 0
    age: uint256 = 0
    if block.timestamp > self.keeper_heartbeat[keeper]:
        age = block.timestamp - self.keeper_heartbeat[keeper]
    executions: uint256 = self.keeper_executions[keeper]
    if age > 86_400:
        return executions
    return executions + 1_000

@external
@view
def job_status(job_id: uint256) -> (address, bool, uint256, uint256, uint256):
    return (
        self.jobs[job_id].target,
        self.jobs[job_id].active,
        self.jobs[job_id].last_execution,
        self.job_successes[job_id],
        self.job_failures[job_id],
    )

