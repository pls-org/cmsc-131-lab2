<!--no-pdf-->
# CMSC 131 Lab 2 Starter

[![lab2-checks](https://github.com/WhiteLicorice/cmsc-131-lab2-starter/actions/workflows/test.yml/badge.svg)](https://github.com/WhiteLicorice/cmsc-131-lab2-starter/actions/workflows/test.yml)

A C-callable library of sort, search, and utility routines in assembly. The manual is the assignment. This file is the repository's own notes.

## Layout

```text
Makefile       platform preamble and build rules
bench.c        provided: file I/O, timing, the C-side comparison, the hostile caller
cdecl.h        provided: the calling-convention macros
LICENSE        provided
sort.asm       yours
search.asm     yours
util.asm       yours
run_tests.sh   provided: the correctness gate
tests/         provided: the test corpus
```

## What to Run

On Windows, run these commands in Git Bash, the shell from Block 1. In that
shell, `make` is your alias for `mingw32-make`. On Linux, use your terminal.

```bash
make
make check
```

`make` builds `bench`. `make check` builds, then runs `./run_tests.sh`,
which reports each check and exits nonzero when any of them fail. Each run
is captured first. Its exit status is read before its text is examined,
so a program that prints the right line and then crashes still fails.

## Reading a First Run

The assembly files ship as stubs that assemble and link as-is, so the build
works before you write any code. Right now they do nothing useful, and 19
of the 36 checks fail. The seventeen that pass prove little. Four are files
that arrive empty, single-element, or already sorted. `gcd(0, 0)` expects 0.
The hostile caller cannot be upset by a stub that touches no register. The
rest are argument and file refusals that the harness performs before any
assembly runs. That red run is the correct starting state for a starter. The
badge stays red until you implement the routines.

The provided files are fixtures. The grader compares your fork against the
starter. An edit to `bench.c`, `Makefile`, `run_tests.sh`, or a `tests/`
file appears as a diff in the open.

## Documentation

The three sections at the end of this file are yours. Complete Design Notes
and Subsystem Ownership before the Week 1 progress report. Complete Quirks
and Issues before the Week 3 progress report. Each section says what it
needs. Leave the rest of this file as it is.

---

## Design Notes

Complete this section before the Week 1 progress report and finish it by
Week 3. The syllabus asks for problem analysis, a solution architecture,
and an estimated timeline. The manual's Deliverables section lists what
this activity adds. Keep each part short. Update it when the plan changes.

### Problem analysis

The four routines `bench.c` expects and what each one returns. Which
registers you preserve and why.

- `qsort_asm(int *arr, int n)` (`sort.asm`)  
  Sorts `n` 32-bit signed integers in ascending order using recursive quicksort with Lomuto partitioning. The last element is used as the pivot. Returns nothing.

- `bsearch_asm(int *arr, int n, int key)` (`search.asm`)  
  Recursively searches the sorted array for `key` and uses `lo + (hi - lo) / 2` to safely compute the midpoint. Returns the index if found, or `-1` otherwise.

- `gcd_asm(int a, int b)` (`util.asm`)  
  Recursively computes the GCD using Euclid's algorithm. The result is returned in `eax`, while the maximum recursion depth is stored in `gcd_depth`.

- `sum_range_asm(int lo, int hi)` (`util.asm`)  
  Recursively computes the sum from `lo` to `hi`. It returns `0` when `lo > hi` and calls `bench_callback()` once per C-level call.

### Calling Convention and Register Preservation

The routines follow the `cdecl` calling convention. Arguments are pushed right to left, and the caller cleans up the stack after the function returns.

Caller-saved:
- `cdecl`
- `eax`
- `ecx`
- `edx`

Callee-saved: 
- `ebx`
- `esi`
- `edi`
- `ebp`

To preserve `ebp`, we use `enter`/`leave` and save `ebx`, `esi`, and `edi` with `push`/`pop`.

This is necessary to keep the C program's register values intact and to prevent recursive calls from overwriting the parent call's data.

### Design

Sorting and searching are implemented recursively, with each call keeping its own state through its stack frame. The routines are separated into `sort.asm`, `search.asm`, and `util.asm` to keep the implementation modular and easier to compile and link.

### Solution architecture

A stack frame diagram for one recursive call of `qsort_asm`, showing where
the arguments, the return address, saved `ebp`, and the saved registers
sit. Why `sum_range_asm` is reentrant.

Each C-facing routine ( _qsort_asm, _bsearch_asm, _gcd_asm, _sum_range_asm) works as a cdelc entry wrapper. It handles the initial setup or base checks, then call its internal recursive helper (qsort_inner, bsearch_inner, gcd_inner, sum_range_inner). The helper also follows the cdecl stack rules. 

**Stack frame for one recursive call of `qsort_inner(int *arr, int lo, int hi)`:**

```text
High Memory
            ┌────────────┬──────────────────────┐
  [ebp + 16]│ hi         │ 3rd arg (int)        │ ┐
            ├────────────┼──────────────────────┤ │ Caller-pushed
  [ebp + 12]│ lo         │ 2nd arg (int)        │ ├ arguments
            ├────────────┼──────────────────────┤ │ (cdecl right-to-left)
  [ebp + 8] │ arr        │ 1st arg (int *)      │ ┘
            ├────────────┼──────────────────────┤
  [ebp + 4] │ ret addr   │ Pushed by call       │
            ├────────────┼──────────────────────┤
  [ebp + 0] │ saved ebp  │ Pushed by enter 0,0  │ ◄── ebp (frame pointer)
            ├────────────┼──────────────────────┤
  [ebp - 4] │ saved ebx  │ Callee-saved (lo/p)  │ ┐
            ├────────────┼──────────────────────┤ │
  [ebp - 8] │ saved esi  │ Callee-saved (arr)   │ ├ Preserved registers
            ├────────────┼──────────────────────┤ │
  [ebp - 12]│ saved edi  │ Callee-saved (hi)    │ ┘ ◄── esp (stack pointer)
            └────────────┴──────────────────────┘
Low Memory (stack grows downward ▼)
```

**Why `sum_range_asm` is reentrant:**
sum_range_asm is reentrant because it does not use any mutable static or global storage (.data or .bss) while running. The outer _sum_range_asm calls bench_callback() once, then calls the recursive helper sum_range_inner(lo, hi). Each call keeps its own lo, hi, and intermediate values in registers and its own stack frame. So, if bench_callback() starts another sum_range_asm(1, 100) while sum_range_asm(1, 1000) is still running, the new call gets its own stack frames and does not overwrite the outer call's data. A non-reentrant version that stored the running total in a .bss variable could have that shared value overwritten by the nested call.

### Measurements

The ratio `bench` reports on `random1000.txt`, `sorted1000.txt`,
`reverse1000.txt`, `duplicates.txt`, and `identical.txt`. Your worst case
and its cause. One improvement and its estimated effect.

| File | Ratio |
|---|---|
| `random1000.txt` | |
| `sorted1000.txt` | |
| `reverse1000.txt` | |
| `duplicates.txt` | |
| `identical.txt` | |

### Timeline

One line per week. Name the subsystem each week finishes and the member
who owns it.

| Week | Goal | Owner |
| --- | --- | --- |
| 1 | Finish the Subsystem Ownership, start the Design Notes, understand the C interface and cdecl convention, and have the baseline prototype building and running | Percie Louise Y. Samaniego |
| 2 | Get the recursive `qsort_asm` and `bsearch_asm` working, including partitioning, midpoint calculation, edge cases, and register preservation | Samantha F. Mok & Justin B. Lauricio |
| 3 | Complete all routines, get `make check` passing, test reentrancy and the hostile caller, finish the Design Notes, add tests, and document the quirks and issues | Percie Louise Y. Samaniego |
| 4 | Final defense and explanation of the assigned and other subsystems | All members |

## Subsystem Ownership

Complete this section before the Week 1 progress report. The manual lists
the three subsystems. Each member owns one. In a group of four, two members
share one. The commit history must agree with this table.

| Subsystem | Owner |
|---|---|
| Sorting (`qsort_asm` and its partition) | Samantha F. Mok |
| Searching (`bsearch_asm`, `gcd_asm`) | Justin B. Lauricio |
| Convention and measurement (`sum_range_asm`, the benchmarks) | Percie Louise Y. Samaniego |

## Quirks and Issues

Complete this section before the Week 3 progress report. The syllabus asks
for documentation of quirks and issues with the complete implementation.
One entry per item. State what happens, what causes it, and what the group
did about it.

### Known issues

- 

### Quirks

- 
