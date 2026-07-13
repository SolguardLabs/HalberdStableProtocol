from pathlib import Path

import pytest
from eth_tester import EthereumTester, PyEVMBackend
from vyper import compile_code
from web3 import EthereumTesterProvider, Web3


ROOT = Path(__file__).resolve().parents[1]
WAD = 10**18


def compile_contract(name: str):
    source = (ROOT / "src" / f"{name}.vy").read_text()
    return compile_code(source, output_formats=["abi", "bytecode"])


@pytest.fixture(scope="session")
def compiled():
    names = [
        "HalberdUSD",
        "HalberdAccounting",
        "HalberdAuctionHouse",
        "HalberdAuditHooks",
        "HalberdCollateral",
        "HalberdKeeperRegistry",
        "HalberdOracle",
        "HalberdRedemptionQueue",
        "HalberdReserveLedger",
        "HalberdRiskEngine",
        "HalberdVaults",
        "HalberdStabilityModule",
        "HalberdTimelock",
        "HalberdLens",
        "HalberdCircuitBreaker",
        "HalberdMath",
        "HalberdParameterRegistry",
        "HalberdEmergencyShutdown",
    ]
    return {name: compile_contract(name) for name in names}


@pytest.fixture()
def w3():
    backend = PyEVMBackend()
    tester = EthereumTester(backend=backend)
    provider = EthereumTesterProvider(tester)
    web3 = Web3(provider)
    web3.eth.default_account = web3.eth.accounts[0]
    return web3


def deploy(w3, compiled, name, *args, sender=None):
    artifact = compiled[name]
    contract = w3.eth.contract(abi=artifact["abi"], bytecode=artifact["bytecode"])
    tx = contract.constructor(*args).transact({"from": sender or w3.eth.default_account})
    receipt = w3.eth.wait_for_transaction_receipt(tx)
    return w3.eth.contract(address=receipt.contractAddress, abi=artifact["abi"])


@pytest.fixture()
def protocol(w3, compiled):
    admin = w3.eth.accounts[0]
    alice = w3.eth.accounts[1]
    redeemer = w3.eth.accounts[2]
    liquidator = w3.eth.accounts[3]

    stable = deploy(w3, compiled, "HalberdUSD", admin)
    collateral = deploy(w3, compiled, "HalberdCollateral", admin)
    oracle = deploy(w3, compiled, "HalberdOracle", admin)
    risk = deploy(w3, compiled, "HalberdRiskEngine", admin)
    vaults = deploy(w3, compiled, "HalberdVaults", stable.address, oracle.address, risk.address, admin)
    stability = deploy(
        w3,
        compiled,
        "HalberdStabilityModule",
        stable.address,
        vaults.address,
        oracle.address,
        risk.address,
        collateral.address,
        admin,
    )

    stable.functions.set_vault(vaults.address).transact({"from": admin})
    stable.functions.set_stability_module(stability.address).transact({"from": admin})
    vaults.functions.set_stability_module(stability.address).transact({"from": admin})

    oracle.functions.set_feed(collateral.address, 1000 * WAD, 10**9, 10_000).transact({"from": admin})
    risk.functions.configure_market(
        collateral.address,
        15_000,
        12_000,
        1_000,
        50_000 * WAD,
        100 * WAD,
        25_000 * WAD,
    ).transact({"from": admin})
    risk.functions.set_fees(collateral.address, 0, 0).transact({"from": admin})

    for account in [alice, redeemer, liquidator]:
        collateral.functions.transfer(account, 1_000 * WAD).transact({"from": admin})

    return {
        "admin": admin,
        "alice": alice,
        "redeemer": redeemer,
        "liquidator": liquidator,
        "stable": stable,
        "collateral": collateral,
        "oracle": oracle,
        "risk": risk,
        "vaults": vaults,
        "stability": stability,
    }


def open_vault(w3, protocol, owner, collateral_amount, debt_amount):
    collateral = protocol["collateral"]
    vaults = protocol["vaults"]
    stable = protocol["stable"]
    collateral.functions.approve(vaults.address, collateral_amount).transact({"from": owner})
    tx = vaults.functions.open_vault(collateral.address).transact({"from": owner})
    receipt = w3.eth.wait_for_transaction_receipt(tx)
    # next_vault_id starts at 1 and increases once in this tx.
    vault_id = vaults.functions.latest_vault_by_owner(owner).call()
    vaults.functions.deposit(vault_id, collateral_amount).transact({"from": owner})
    vaults.functions.mint(vault_id, debt_amount).transact({"from": owner})
    assert stable.functions.balanceOf(owner).call() >= debt_amount
    return vault_id
