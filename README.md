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

Each C-facing routine (`_qsort_asm`, `_bsearch_asm`, `_gcd_asm`, and `_sum_range_asm`) first sets things up and checks the basic conditions before calling its recursive helper. `bsearch_inner`, `gcd_inner`, and `sum_range_inner` use normal `cdecl` stack frames, while `.qsort_recursive` uses registers to keep track of the array (`edi`), lower bound (`ecx`), and upper bound (`edx`). For each recursive call, the current `lo`, `hi`, and pivot index values are saved on the stack so they can be restored after the call.

**Stack frame for `_qsort_asm` and one active recursive call of `.qsort_recursive`:**

```text
High Memory
            ┌────────────┬──────────────────────────┐
  [ebp + 12]│ n          │ 2nd arg (int)            │ ┐ Caller-pushed args
            ├────────────┼──────────────────────────┤ ├ to _qsort_asm
  [ebp + 8] │ arr        │ 1st arg (int *)          │ ┘ (cdecl right-to-left)
            ├────────────┼──────────────────────────┤
  [ebp + 4] │ ret addr   │ Return address to C      │
            ├────────────┼──────────────────────────┤
  [ebp + 0] │ saved ebp  │ Pushed by enter 0,0      │ ◄── ebp (_qsort_asm)
            ├────────────┼──────────────────────────┤
  [ebp - 4] │ saved ebx  │ Callee-saved register    │ ┐
            ├────────────┼──────────────────────────┤ │ Preserved once in
  [ebp - 8] │ saved esi  │ Callee-saved register    │ ├ _qsort_asm wrapper
            ├────────────┼──────────────────────────┤ │
  [ebp - 12]│ saved edi  │ Callee-saved register    │ ┘
            ╞════════════╪══════════════════════════╡
  [esp + 12]│ ret addr   │ Pushed by call           │ ┐
            ├────────────┼──────────────────────────┤ │ One recursive frame
  [esp + 8] │ saved lo   │ Pushed ecx (original lo) │ │ of .qsort_recursive
            ├────────────┼──────────────────────────┤ ├ (cleaned before ret
  [esp + 4] │ saved hi   │ Pushed edx (original hi) │ │  via pop esi and
            ├────────────┼──────────────────────────┤ │  add esp, 8)
  [esp + 0] │ saved p    │ Pushed esi (pivot index) │ ┘ ◄── esp
            └────────────┴──────────────────────────┘
Low Memory (stack grows downward ▼)
```

**Why `sum_range_asm` is reentrant:**
`sum_range_asm` is reentrant because it does not use shared or changeable data in `.data` or `.bss` while running. The outer `_sum_range_asm` saves `ebx` and `esi`, calls `bench_callback()` once, and then calls `sum_range_inner(lo, hi)`. Each call has its own `lo`, `hi`, and temporary values stored in its registers and stack frame. So, if `bench_callback()` starts another `sum_range_asm(1, 100)` while `sum_range_asm(1, 1000)` is still running, the nested call gets its own stack frame and does not overwrite the data of the first call. If we used a shared `.bss` variable for the running total instead, the nested call could overwrite the same value and cause the outer call to get the wrong result.

### Measurements

The ratio `bench` reports on `random1000.txt`, `sorted1000.txt`,
`reverse1000.txt`, `duplicates.txt`, and `identical.txt`. Your worst case
and its cause. One improvement and its estimated effect.

| File | Ratio |
|---|---|
| `random1000.txt` | 0.47x |
| `sorted1000.txt` | 13.54x |
| `reverse1000.txt` | 10.04x |
| `duplicates.txt` | 3.25x |
| `identical.txt` | 5.15x |

**Worst case and cause:**

Our worst case is `sorted1000.txt` at `13.54x` (`0.261 ms` vs. `0.019 ms`). Basically, `qsort_asm` struggles the most when the array is already sorted. This is because our Lomuto partition always chooses the last element, `arr[hi]`, as the pivot. So when the array is already sorted, the pivot will always be the biggest element, which results in unbalanced partitions.

Because of that, almost nothing gets separated into the other side. We keep getting `(n - 1)` and `0` partitions, meaning the array is barely being divided at all. This happens again and again for 999 recursive calls, giving us around `499,500` comparisons and `O(n²)` time. So instead of quickly breaking the array into smaller parts, we're basically going through almost the whole array every time.

`sorted1000.txt` is also slower than `reverse1000.txt` (`13.54x` vs. `10.04x`, or `0.261 ms` vs. `0.213 ms`) because every `arr[j] <= pivot` check is true in the sorted array. This causes the code to perform `499,500` self-swaps on top of all the comparisons.

Meanwhile, `random1000.txt` performs much better at `0.47x` because the values are more naturally divided during partitioning. `qsort_asm` also beats C's `qsort` here because it compares values directly in registers instead of calling `cmp_int` through a function pointer on every comparison. C's `qsort` also avoids our sorted worst-case behavior by using better pivot selection.

**One improvement and estimated effect:**
One improvement we can make is using a **median-of-three pivot**. Instead of always choosing the last element, we take the middle value from `arr[lo]`, `arr[mid]`, and `arr[hi]` and swap it into `arr[hi]` as the pivot. This helps avoid the problem we had with already sorted or reverse-sorted arrays because the pivot is more likely to be closer to the middle. This should make the partitions more balanced, reducing the work from around `499,500` comparisons (`O(n²)`) to around `10,000` comparisons (`O(n log₂ n)`).

Because of this, `qsort_asm` on `sorted1000.txt` could potentially go from `0.261 ms` to around `0.03–0.04 ms` (narrowing the ratio from `13.54x` down to around `1.6x–2.1x`, or an estimated `6x–8x` speedup). This would make it much closer to the `0.032 ms` we got from `random1000.txt`. This is only an estimate, but basically, **a better pivot gives us more balanced splits, which means fewer comparisons, fewer swaps, and faster sorting.**

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

- **Quadratic `O(n²)` runtime and `O(n)` stack depth on sorted, reverse-sorted, and all-equal inputs:** `qsort_asm` becomes much slower when the array is already sorted, sorted in reverse, or contains the same values. We got `13.54x` on `sorted1000.txt`, `10.04x` on `reverse1000.txt`, and `5.15x` on `identical.txt`. This happens because we always choose the last element, `arr[hi]`, as the pivot. For these types of arrays, the pivot does not split the values evenly, so one side gets almost the entire array while the other side gets nothing. This means we have to keep going through almost the same number of elements again and again, resulting in more recursive calls and slower sorting. If the array is very large, these repeated calls could also use up too much stack space. We kept the required Lomuto partitioning but included median-of-three pivot selection as a possible improvement.

- **Linear recursion depth `O(hi - lo)` in `sum_range_asm`:** `sum_range_asm` can also use a lot of stack space when the range is very large because `sum_range_inner` processes one number at a time using `lo + 1`. So even if the final sum is still valid, the many recursive calls could eventually use up the call stack. We kept the required recursive approach and added a `lo == hi` base case along with `lo > hi` so cases like `sum_range_asm(INT_MAX, INT_MAX)` can stop safely without doing `lo + 1`.

### Quirks

- **Swap overhead (`xchg` vs. `mov`) and self-swaps on sorted inputs:** Initially, `sort.asm` used `xchg` to swap elements, but this turned out to be slower because it uses a hardware lock when swapping values in memory. This made `sorted1000.txt` (`2.928 ms`, `166.31x`) especially slow because it performed `499,500` self-swaps. We replaced `xchg` with `mov`-based swaps using two registers (`ebx`/`edx` inside `.part_loop` and `ebx`/`ecx` at `.part_end`), which reduced the runtime of `sorted1000.txt` to `0.261 ms` (`13.54x`). However, `sorted1000.txt` (`0.261 ms`) is still slightly slower than `reverse1000.txt` (`0.213 ms`) because every `arr[j] <= pivot` check is true for an already sorted array. This means we're still swapping elements even when `arr[i]` and `arr[j]` are actually the same element (`i == j`).

- **`bsearch_asm` does not choose a specific index when values are duplicated:** If the same value appears multiple times in `duplicates.txt`, `identical.txt`, or `extremes.txt`, `bsearch_asm` returns the first matching index it happens to find. It does not continue looking for the first or last occurrence. This is fine for our case because the requirement only checks if the returned index contains the correct key, so there is no need for extra searching.

