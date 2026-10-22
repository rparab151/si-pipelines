# Verification plan

## Directed tests
The self-checking SV bench exercises buy/sell threshold decisions, adjacent accepted quotes, stall stability, neutral/crossed/zero-quantity quotes, sequence gaps, explicit resynchronization, intent quota and sequence wrap.

## Differential testing
`scripts/random_diff.py` generates seeded stimuli, maintains a Python behavioral model, runs a SystemVerilog trace testbench with Icarus, and compares ready/valid decisions plus observable post-edge state cycle by cycle.

```bash
make test
make random
python3 scripts/random_diff.py --cycles 3000 --seed 20261021
```

## Assertions
The RTL has optional `ENABLE_SVA` assertions checking output stability during stalls and quote exclusion on control events. The default CI flow runs the directed and randomized tests rather than relying on a formal SVA tool.

## Limitations
Passing functional simulation would not imply formal completeness, CDC safety, physical timing/area, compliance with market protocols, or production trading safety.
