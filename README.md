# si-pipelines

Designing stuff
---

## Overview

This repository documents my work in VLSI systems, RTL design, and hardware architecture

The goal is to explore how real-world high-performance systems are built:
- deterministic execution
- predictable latency
- efficient data movement
- clean hardware/software boundaries

All projects are implemented with an emphasis on:
- cycle-level reasoning
- timing closure
- modular pipeline design

---

## Projects

### 1. UDP Packet Parser (WIP)
A streaming parser for UDP-based market data.

- Fully pipelined design
- AXI-stream style interfaces
- Backpressure handling
- Cycle-by-cycle latency breakdown

---

### 2. AXI-Stream FIFO (WIP)
Custom FIFO implementation for high-throughput pipelines.

- Configurable depth and width
- Flow control and backpressure
- Timing-aware implementation

---

## Design Philosophy

Most designs here follow a few core principles:

- **Latency is a feature**  
  Every stage is analyzed at cycle granularity.

- **Pipelines over control logic**  
  Favor streaming architectures over complex state machines.

- **Determinism over average-case performance**  
  Predictability matters more than peak throughput.

---

## Blog / Writeups

Detailed writeups and design notes:

Topics include:
- Timing closure strategies
- Pipeline design tradeoffs
- Debugging real RTL issues
- Latency vs throughput analysis

---

## Tooling

- RTL: SystemVerilog / Verilog  
- FPGA: Xilinx 7-series (Zynq / Artix)  
- Tools: Vivado  

---

## About Me

ASIC Design Engineer with experience in large-scale coherent systems.

Interested in:
- hardware/software co-design
- low-latency systems
- high-performance compute architectures

---
