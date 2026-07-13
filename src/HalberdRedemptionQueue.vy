# pragma version ^0.4.3

event RequestQueued:
    request_id: indexed(uint256)
    owner: indexed(address)
    amount: uint256
    min_collateral_out: uint256
    executable_at: uint256

event RequestCanceled:
    request_id: indexed(uint256)
    owner: indexed(address)

event RequestClaimed:
    request_id: indexed(uint256)
    owner: indexed(address)
    collateral_out: uint256

event QueueConfig:
    delay: uint256
    expiry: uint256
    module: address

struct Request:
    owner: address
    amount: uint256
    min_collateral_out: uint256
    created_at: uint256
    executable_at: uint256
    expires_at: uint256
    claimed: bool
    canceled: bool

admin: public(address)
module: public(address)
delay_seconds: public(uint256)
expiry_seconds: public(uint256)
next_request_id: public(uint256)
queued_amount: public(uint256)
claimed_amount: public(uint256)
canceled_amount: public(uint256)
requests: public(HashMap[uint256, Request])
latest_request: public(HashMap[address, uint256])
request_count: public(HashMap[address, uint256])

@deploy
def __init__(_admin: address):
    assert _admin != empty(address), "admin"
    self.admin = _admin
    self.module = _admin
    self.delay_seconds = 300
    self.expiry_seconds = 86_400
    self.next_request_id = 1
    log QueueConfig(delay=self.delay_seconds, expiry=self.expiry_seconds, module=self.module)

@internal
@view
def _only_admin():
    assert msg.sender == self.admin, "admin"

@internal
@view
def _only_module():
    assert msg.sender == self.module or msg.sender == self.admin, "module"

@internal
@view
def _is_open(request_id: uint256) -> bool:
    req: Request = self.requests[request_id]
    if req.owner == empty(address):
        return False
    if req.claimed or req.canceled:
        return False
    if block.timestamp > req.expires_at:
        return False
    return True

@external
def configure(delay: uint256, expiry: uint256, new_module: address):
    self._only_admin()
    assert expiry > delay, "expiry"
    assert new_module != empty(address), "module"
    self.delay_seconds = delay
    self.expiry_seconds = expiry
    self.module = new_module
    log QueueConfig(delay=delay, expiry=expiry, module=new_module)

@external
def queue(amount: uint256, min_collateral_out: uint256) -> uint256:
    assert amount > 0, "amount"
    request_id: uint256 = self.next_request_id
    self.next_request_id += 1
    executable_at: uint256 = block.timestamp + self.delay_seconds
    expires_at: uint256 = block.timestamp + self.expiry_seconds
    self.requests[request_id] = Request(
        owner=msg.sender,
        amount=amount,
        min_collateral_out=min_collateral_out,
        created_at=block.timestamp,
        executable_at=executable_at,
        expires_at=expires_at,
        claimed=False,
        canceled=False,
    )
    self.latest_request[msg.sender] = request_id
    self.request_count[msg.sender] += 1
    self.queued_amount += amount
    log RequestQueued(
        request_id=request_id,
        owner=msg.sender,
        amount=amount,
        min_collateral_out=min_collateral_out,
        executable_at=executable_at,
    )
    return request_id

@external
def cancel(request_id: uint256):
    req: Request = self.requests[request_id]
    assert req.owner == msg.sender or msg.sender == self.admin, "owner"
    assert self._is_open(request_id), "open"
    self.requests[request_id].canceled = True
    self.canceled_amount += req.amount
    log RequestCanceled(request_id=request_id, owner=req.owner)

@external
def mark_claimed(request_id: uint256, collateral_out: uint256):
    self._only_module()
    assert self._is_open(request_id), "open"
    self.requests[request_id].claimed = True
    self.claimed_amount += self.requests[request_id].amount
    log RequestClaimed(
        request_id=request_id,
        owner=self.requests[request_id].owner,
        collateral_out=collateral_out,
    )

@external
def expire(request_id: uint256):
    req: Request = self.requests[request_id]
    assert req.owner != empty(address), "request"
    assert not req.claimed and not req.canceled, "closed"
    assert block.timestamp > req.expires_at, "expiry"
    self.requests[request_id].canceled = True
    self.canceled_amount += req.amount
    log RequestCanceled(request_id=request_id, owner=req.owner)

@external
@view
def is_ready(request_id: uint256) -> bool:
    if not self._is_open(request_id):
        return False
    return block.timestamp >= self.requests[request_id].executable_at

@external
@view
def request_window(request_id: uint256) -> (uint256, uint256, bool):
    req: Request = self.requests[request_id]
    ready: bool = False
    if self._is_open(request_id) and block.timestamp >= req.executable_at:
        ready = True
    return (req.executable_at, req.expires_at, ready)

@external
@view
def queue_totals() -> (uint256, uint256, uint256):
    return (self.queued_amount, self.claimed_amount, self.canceled_amount)

