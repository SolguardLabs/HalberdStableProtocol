# pragma version ^0.4.3

event Transfer:
    sender: indexed(address)
    receiver: indexed(address)
    value: uint256

event Approval:
    owner: indexed(address)
    spender: indexed(address)
    value: uint256

event RoleUpdated:
    account: indexed(address)
    role: bytes32
    enabled: bool

event AdminTransferStarted:
    current_admin: indexed(address)
    pending_admin: indexed(address)

event AdminTransferred:
    previous_admin: indexed(address)
    new_admin: indexed(address)

event PauseUpdated:
    paused: bool
    account: indexed(address)

MINTER_ROLE: constant(bytes32) = keccak256("HALBERD_MINTER")
BURNER_ROLE: constant(bytes32) = keccak256("HALBERD_BURNER")
VAULT_ROLE: constant(bytes32) = keccak256("HALBERD_VAULT")
STABILITY_ROLE: constant(bytes32) = keccak256("HALBERD_STABILITY")
MAX_ALLOWANCE: constant(uint256) = max_value(uint256)

name: public(String[32])
symbol: public(String[12])
decimals: public(uint8)

totalSupply: public(uint256)
balanceOf: public(HashMap[address, uint256])
allowance: public(HashMap[address, HashMap[address, uint256]])

admin: public(address)
pending_admin: public(address)
guardian: public(address)
vault: public(address)
stability_module: public(address)
paused: public(bool)

minters: public(HashMap[address, bool])
burners: public(HashMap[address, bool])
trusted_modules: public(HashMap[address, bool])
minted_by: public(HashMap[address, uint256])
burned_by: public(HashMap[address, uint256])
last_transfer_at: public(HashMap[address, uint256])

@deploy
def __init__(_admin: address):
    assert _admin != empty(address), "admin"
    self.name = "Halberd USD"
    self.symbol = "HUSD"
    self.decimals = 18
    self.admin = _admin
    self.guardian = _admin
    self.minters[_admin] = True
    self.burners[_admin] = True
    log RoleUpdated(account=_admin, role=MINTER_ROLE, enabled=True)
    log RoleUpdated(account=_admin, role=BURNER_ROLE, enabled=True)

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
def _transfer(sender: address, receiver: address, amount: uint256):
    assert receiver != empty(address), "receiver"
    assert self.balanceOf[sender] >= amount, "balance"
    self.balanceOf[sender] -= amount
    self.balanceOf[receiver] += amount
    self.last_transfer_at[sender] = block.timestamp
    self.last_transfer_at[receiver] = block.timestamp
    log Transfer(sender=sender, receiver=receiver, value=amount)

@internal
def _approve(owner: address, spender: address, amount: uint256):
    assert owner != empty(address), "owner"
    assert spender != empty(address), "spender"
    self.allowance[owner][spender] = amount
    log Approval(owner=owner, spender=spender, value=amount)

@internal
def _spend_allowance(owner: address, spender: address, amount: uint256):
    current: uint256 = self.allowance[owner][spender]
    if current != MAX_ALLOWANCE:
        assert current >= amount, "allowance"
        self.allowance[owner][spender] = current - amount
        log Approval(owner=owner, spender=spender, value=current - amount)

@internal
def _mint(receiver: address, amount: uint256):
    assert receiver != empty(address), "receiver"
    assert amount > 0, "amount"
    self.totalSupply += amount
    self.balanceOf[receiver] += amount
    self.minted_by[msg.sender] += amount
    log Transfer(sender=empty(address), receiver=receiver, value=amount)

@internal
def _burn(owner: address, amount: uint256):
    assert owner != empty(address), "owner"
    assert amount > 0, "amount"
    assert self.balanceOf[owner] >= amount, "balance"
    self.balanceOf[owner] -= amount
    self.totalSupply -= amount
    self.burned_by[msg.sender] += amount
    log Transfer(sender=owner, receiver=empty(address), value=amount)

@external
def transfer(receiver: address, amount: uint256) -> bool:
    self._not_paused()
    self._transfer(msg.sender, receiver, amount)
    return True

@external
def approve(spender: address, amount: uint256) -> bool:
    self._not_paused()
    self._approve(msg.sender, spender, amount)
    return True

@external
def increase_allowance(spender: address, added: uint256) -> bool:
    self._not_paused()
    new_allowance: uint256 = self.allowance[msg.sender][spender] + added
    self._approve(msg.sender, spender, new_allowance)
    return True

@external
def decrease_allowance(spender: address, subtracted: uint256) -> bool:
    self._not_paused()
    current: uint256 = self.allowance[msg.sender][spender]
    assert current >= subtracted, "allowance"
    self._approve(msg.sender, spender, current - subtracted)
    return True

@external
def transferFrom(owner: address, receiver: address, amount: uint256) -> bool:
    self._not_paused()
    if msg.sender != owner:
        self._spend_allowance(owner, msg.sender, amount)
    self._transfer(owner, receiver, amount)
    return True

@external
def mint(receiver: address, amount: uint256):
    self._not_paused()
    assert self.minters[msg.sender] or msg.sender == self.vault, "minter"
    self._mint(receiver, amount)

@external
def burn(amount: uint256):
    self._not_paused()
    self._burn(msg.sender, amount)

@external
def burn_from(owner: address, amount: uint256):
    self._not_paused()
    assert self.burners[msg.sender] or msg.sender == owner, "burner"
    if msg.sender != owner:
        self._spend_allowance(owner, msg.sender, amount)
    self._burn(owner, amount)

@external
def set_minter(account: address, enabled: bool):
    self._only_admin()
    self.minters[account] = enabled
    log RoleUpdated(account=account, role=MINTER_ROLE, enabled=enabled)

@external
def set_burner(account: address, enabled: bool):
    self._only_admin()
    self.burners[account] = enabled
    log RoleUpdated(account=account, role=BURNER_ROLE, enabled=enabled)

@external
def set_trusted_module(account: address, enabled: bool):
    self._only_admin()
    self.trusted_modules[account] = enabled
    log RoleUpdated(account=account, role=STABILITY_ROLE, enabled=enabled)

@external
def set_vault(account: address):
    self._only_admin()
    assert account != empty(address), "vault"
    self.vault = account
    self.minters[account] = True
    self.burners[account] = True
    log RoleUpdated(account=account, role=VAULT_ROLE, enabled=True)
    log RoleUpdated(account=account, role=MINTER_ROLE, enabled=True)
    log RoleUpdated(account=account, role=BURNER_ROLE, enabled=True)

@external
def set_stability_module(account: address):
    self._only_admin()
    assert account != empty(address), "stability"
    self.stability_module = account
    self.trusted_modules[account] = True
    log RoleUpdated(account=account, role=STABILITY_ROLE, enabled=True)

@external
def set_guardian(account: address):
    self._only_admin()
    assert account != empty(address), "guardian"
    self.guardian = account

@external
def pause():
    self._only_guardian_or_admin()
    self.paused = True
    log PauseUpdated(paused=True, account=msg.sender)

@external
def unpause():
    self._only_admin()
    self.paused = False
    log PauseUpdated(paused=False, account=msg.sender)

@external
def start_admin_transfer(new_admin: address):
    self._only_admin()
    assert new_admin != empty(address), "new_admin"
    self.pending_admin = new_admin
    log AdminTransferStarted(current_admin=msg.sender, pending_admin=new_admin)

@external
def accept_admin():
    assert msg.sender == self.pending_admin, "pending"
    previous: address = self.admin
    self.admin = msg.sender
    self.pending_admin = empty(address)
    log AdminTransferred(previous_admin=previous, new_admin=msg.sender)

@external
def rescue_token(token: address, receiver: address, amount: uint256):
    self._only_admin()
    assert token != self, "self"
    # This token contract intentionally has no generic ERC-20 interface call.
    # Rescue is reserved for native test harnesses and should not hold assets.
    assert receiver != empty(address), "receiver"
    assert amount == 0, "disabled"

@external
@view
def circulating_supply() -> uint256:
    return self.totalSupply

@external
@view
def module_allowance(owner: address, module: address) -> uint256:
    return self.allowance[owner][module]

@external
@view
def is_operational_module(module: address) -> bool:
    return module == self.vault or module == self.stability_module or self.trusted_modules[module]

@external
@view
def role_bitmap(account: address) -> uint256:
    bitmap: uint256 = 0
    if self.minters[account]:
        bitmap += 1
    if self.burners[account]:
        bitmap += 2
    if self.trusted_modules[account]:
        bitmap += 4
    if account == self.admin:
        bitmap += 8
    if account == self.guardian:
        bitmap += 16
    return bitmap
