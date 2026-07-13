# pragma version ^0.4.3

event Transfer:
    sender: indexed(address)
    receiver: indexed(address)
    value: uint256

event Approval:
    owner: indexed(address)
    spender: indexed(address)
    value: uint256

event FaucetMint:
    receiver: indexed(address)
    amount: uint256

event AdminUpdated:
    previous_admin: indexed(address)
    new_admin: indexed(address)

MAX_ALLOWANCE: constant(uint256) = max_value(uint256)
FAUCET_AMOUNT: constant(uint256) = 1_000 * 10 ** 18
MAX_SUPPLY: constant(uint256) = 10_000_000 * 10 ** 18

name: public(String[32])
symbol: public(String[12])
decimals: public(uint8)
totalSupply: public(uint256)

balanceOf: public(HashMap[address, uint256])
allowance: public(HashMap[address, HashMap[address, uint256]])

admin: public(address)
minters: public(HashMap[address, bool])
faucet_used: public(HashMap[address, bool])
transfers_out: public(HashMap[address, uint256])
transfers_in: public(HashMap[address, uint256])

@deploy
def __init__(_admin: address):
    assert _admin != empty(address), "admin"
    self.name = "Halberd Wrapped Ether"
    self.symbol = "hWETH"
    self.decimals = 18
    self.admin = _admin
    self.minters[_admin] = True
    self._mint(_admin, 25_000 * 10 ** 18)

@internal
@view
def _only_admin():
    assert msg.sender == self.admin, "admin"

@internal
def _mint(receiver: address, amount: uint256):
    assert receiver != empty(address), "receiver"
    assert amount > 0, "amount"
    assert self.totalSupply + amount <= MAX_SUPPLY, "cap"
    self.totalSupply += amount
    self.balanceOf[receiver] += amount
    log Transfer(sender=empty(address), receiver=receiver, value=amount)

@internal
def _transfer(sender: address, receiver: address, amount: uint256):
    assert receiver != empty(address), "receiver"
    assert self.balanceOf[sender] >= amount, "balance"
    self.balanceOf[sender] -= amount
    self.balanceOf[receiver] += amount
    self.transfers_out[sender] += amount
    self.transfers_in[receiver] += amount
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

@external
def transfer(receiver: address, amount: uint256) -> bool:
    self._transfer(msg.sender, receiver, amount)
    return True

@external
def approve(spender: address, amount: uint256) -> bool:
    self._approve(msg.sender, spender, amount)
    return True

@external
def transferFrom(owner: address, receiver: address, amount: uint256) -> bool:
    if msg.sender != owner:
        self._spend_allowance(owner, msg.sender, amount)
    self._transfer(owner, receiver, amount)
    return True

@external
def mint(receiver: address, amount: uint256):
    assert self.minters[msg.sender], "minter"
    self._mint(receiver, amount)
    log FaucetMint(receiver=receiver, amount=amount)

@external
def faucet():
    assert not self.faucet_used[msg.sender], "used"
    self.faucet_used[msg.sender] = True
    self._mint(msg.sender, FAUCET_AMOUNT)
    log FaucetMint(receiver=msg.sender, amount=FAUCET_AMOUNT)

@external
def burn(amount: uint256):
    assert self.balanceOf[msg.sender] >= amount, "balance"
    self.balanceOf[msg.sender] -= amount
    self.totalSupply -= amount
    log Transfer(sender=msg.sender, receiver=empty(address), value=amount)

@external
def set_minter(account: address, enabled: bool):
    self._only_admin()
    self.minters[account] = enabled

@external
def transfer_admin(new_admin: address):
    self._only_admin()
    assert new_admin != empty(address), "new_admin"
    previous: address = self.admin
    self.admin = new_admin
    self.minters[new_admin] = True
    log AdminUpdated(previous_admin=previous, new_admin=new_admin)

@external
@view
def available_faucet(account: address) -> uint256:
    if self.faucet_used[account]:
        return 0
    return FAUCET_AMOUNT

@external
@view
def net_flow(account: address) -> int256:
    incoming: uint256 = self.transfers_in[account]
    outgoing: uint256 = self.transfers_out[account]
    if incoming >= outgoing:
        return convert(incoming - outgoing, int256)
    return -convert(outgoing - incoming, int256)
