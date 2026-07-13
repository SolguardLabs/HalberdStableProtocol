# pragma version ^0.4.3

event ShutdownArmed:
    asset: indexed(address)
    eta: uint256
    reason: bytes32

event ShutdownActivated:
    asset: indexed(address)
    activated_at: uint256

event ShutdownCanceled:
    asset: indexed(address)

event ClaimRecorded:
    asset: indexed(address)
    account: indexed(address)
    debt_amount: uint256
    collateral_amount: uint256

event GuardianSet:
    guardian: indexed(address)
    enabled: bool

struct ShutdownState:
    armed: bool
    active: bool
    eta: uint256
    activated_at: uint256
    reason: bytes32

admin: public(address)
delay: public(uint256)
guardians: public(HashMap[address, bool])
shutdowns: public(HashMap[address, ShutdownState])
claims: public(HashMap[address, HashMap[address, uint256]])
collateral_claimed: public(HashMap[address, uint256])
debt_canceled: public(HashMap[address, uint256])
claim_count: public(HashMap[address, uint256])

@deploy
def __init__(_admin: address):
    assert _admin != empty(address), "admin"
    self.admin = _admin
    self.delay = 600
    self.guardians[_admin] = True
    log GuardianSet(guardian=_admin, enabled=True)

@internal
@view
def _only_admin():
    assert msg.sender == self.admin, "admin"

@internal
@view
def _only_guardian():
    assert self.guardians[msg.sender] or msg.sender == self.admin, "guardian"

@external
def set_guardian(guardian: address, enabled: bool):
    self._only_admin()
    assert guardian != empty(address), "guardian"
    self.guardians[guardian] = enabled
    log GuardianSet(guardian=guardian, enabled=enabled)

@external
def set_delay(new_delay: uint256):
    self._only_admin()
    assert new_delay <= 7 * 86_400, "delay"
    self.delay = new_delay

@external
def arm(asset: address, reason: bytes32):
    self._only_guardian()
    assert asset != empty(address), "asset"
    assert not self.shutdowns[asset].active, "active"
    eta: uint256 = block.timestamp + self.delay
    self.shutdowns[asset] = ShutdownState(
        armed=True,
        active=False,
        eta=eta,
        activated_at=0,
        reason=reason,
    )
    log ShutdownArmed(asset=asset, eta=eta, reason=reason)

@external
def activate(asset: address):
    self._only_guardian()
    assert self.shutdowns[asset].armed, "armed"
    assert not self.shutdowns[asset].active, "active"
    assert block.timestamp >= self.shutdowns[asset].eta, "eta"
    self.shutdowns[asset].active = True
    self.shutdowns[asset].activated_at = block.timestamp
    log ShutdownActivated(asset=asset, activated_at=block.timestamp)

@external
def cancel(asset: address):
    self._only_admin()
    assert self.shutdowns[asset].armed, "armed"
    assert not self.shutdowns[asset].active, "active"
    self.shutdowns[asset] = ShutdownState(
        armed=False,
        active=False,
        eta=0,
        activated_at=0,
        reason=empty(bytes32),
    )
    log ShutdownCanceled(asset=asset)

@external
def record_claim(asset: address, account: address, debt_amount: uint256, collateral_amount: uint256):
    self._only_guardian()
    assert self.shutdowns[asset].active, "shutdown"
    assert account != empty(address), "account"
    assert debt_amount > 0 or collateral_amount > 0, "claim"
    self.claims[asset][account] += collateral_amount
    self.collateral_claimed[asset] += collateral_amount
    self.debt_canceled[asset] += debt_amount
    self.claim_count[asset] += 1
    log ClaimRecorded(
        asset=asset,
        account=account,
        debt_amount=debt_amount,
        collateral_amount=collateral_amount,
    )

@external
@view
def can_activate(asset: address) -> bool:
    if not self.shutdowns[asset].armed or self.shutdowns[asset].active:
        return False
    return block.timestamp >= self.shutdowns[asset].eta

@external
@view
def is_shutdown(asset: address) -> bool:
    return self.shutdowns[asset].active

@external
@view
def shutdown_state(asset: address) -> (bool, bool, uint256, uint256, bytes32):
    state: ShutdownState = self.shutdowns[asset]
    return (state.armed, state.active, state.eta, state.activated_at, state.reason)

