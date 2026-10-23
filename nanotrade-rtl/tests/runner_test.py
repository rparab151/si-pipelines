"""pytest launches Verilator and runs cocotb 2.x tests for both RTL designs."""
from pathlib import Path
import pytest
from cocotb_tools.runner import get_runner

ROOT = Path(__file__).resolve().parents[1]


@pytest.mark.parametrize("top,test_module", [
    ("nanotrade", "cocotb_core"),
    ("nanotrade_v2", "cocotb_v2"),
])
def test_cocotb(top, test_module):
    runner = get_runner("verilator")
    build_dir = ROOT / "build" / top
    runner.build(
        sources=[ROOT / "rtl" / (top + ".sv")],
        hdl_toplevel=top,
        build_dir=build_dir,
        always=True,
        timescale=("1ns", "1ps"),
    )
    runner.test(
        hdl_toplevel=top,
        test_module=test_module,
        test_dir=ROOT / "tests",
        build_dir=build_dir,
    )
