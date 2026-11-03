;
; util.asm - gcd_asm and sum_range_asm, both recursive, callable from C.
;
; This is your starting point: it assembles and links as-is, so the build
; works before you write any code. Right now gcd_asm returns 0 and
; sum_range_asm returns 0, so the benchmark's --gcd and --reentrancy demos
; fail. Your job is to replace both.
;
; The contracts, from bench.c:
;
;       int b                       [ebp+12]
;       int a                       [ebp+8]
;       int gcd_asm(int a, int b)   returns the greatest common divisor
;
;       int hi                      [ebp+12]
;       int lo                      [ebp+8]
;       int sum_range_asm(lo, hi)   returns the sum of lo..hi inclusive
;
; Both are C-facing and must obey cdecl: prologue, args at [ebp+8]+, return
; in eax, preserve ebx/esi/edi/ebp, clean arguments after every call.
;
; gcd_asm also sets the global `gcd_depth` to the recursion depth of its
; most recent call. The depth is the number of gcd calls on the stack at
; the deepest point, the first call counted as 1. gcd(1071, 462) makes
; four calls, so it reaches 4. bench.c declares the global extern and
; prints it after --gcd:
;
;       int gcd_depth               (in .bss, exported, one int)
;
; The manual's requirements:
;
;   * Both recursive (Euclid's algorithm for gcd).
;   * sum_range_asm must be reentrant. It has to stay correct when a second
;     call begins before the first has finished. That means no .data or
;     .bss storage that changes during execution. Everything lives on the
;     stack and in registers. The static gcd_depth global is gcd's, not
;     sum_range's, and it is diagnostic rather than part of a result.
;   * sum_range_asm calls the C function bench_callback(void) once each
;     time C calls it, which is how bench makes one call overlap another.
;     The recursive calls must not call it again. bench counts the calls.
;     Declare it extern and call it with cdecl. It is not in the manual's
;     pseudocode, but it is what the reentrancy demo runs on.
;   * No calls into the C standard library.
;
; Euclid:
;
;   gcd(a, b):
;       if b == 0: return a
;       return gcd(b, a % b)
;
; sum_range, written so that nothing lives outside the stack:
;
;   sum_range(lo, hi):
;       if lo > hi: return 0
;       return lo + sum_range(lo + 1, hi)
;

; Windows C puts a leading underscore on every exported name. Linux C does
; not. The Makefile passes -d ELF_TYPE on Linux. This block then respells
; the names below to match. asm_io.inc does the same for _asm_main in the
; bootcamp blocks. Leave this block alone.
%ifdef ELF_TYPE
  %define _gcd_asm gcd_asm
  %define _sum_range_asm sum_range_asm
  %define _gcd_depth gcd_depth
  %define _bench_callback bench_callback
  section .note.GNU-stack noalloc noexec nowrite progbits
%endif

segment .bss
        global  _gcd_depth
_gcd_depth      resd    1

segment .text
        global  _gcd_asm
        extern  _bench_callback
_gcd_asm:
        enter   0,0
        pusha

        ;
        ; TODO: gcd. Count the calls. Reset gcd_depth at entry, then keep
        ; the deepest level reached, with the first call as level 1. Carry
        ; the current level in a register or count it in the global, but
        ; leave the peak behind. bench.c reads gcd_depth after the call
        ; returns, so a counter that returns to zero on exit prints 0.
        ;

        ; ----------------------------------------------------------------
        ; gcd_asm(int a, int b)
        ;
        ; - wrapper for gcd_asm, it zeroes gcd_depth
        ; - calls gcd_inner with the first call numbered level 1
        ; - touches only eax, no callee-saved reg to preserve
        ; - converts function args into (a, b, level)
        ;    and it cleans up afterward
        ; - pushes the args right to left
        ;
        ; stack frame: 
        ;         int b           [ebp + 12]
        ;         int a           [ebp + 8]
        ;
        ;         return address  [ebp + 4]
        ;         saved ebp       [ebp + 0]
        ; -----------------------------------------------------------

        ; reset the diagnostic to 0 before each call
        mov     dword [_gcd_depth], 0 

        ; pushing args (a, b, level) right to left 
        ; first call counted as 1
        push    dword 1                 ; push level = 1 
        push    dword [ebp + 12]        ; push b
        push    dword [ebp + 8]         ; push a
        call    gcd_inner

        ; clean up: removes 3 args x 4 bytes
        add     esp, 12

        leave                           ; result is already in eax
        ret

        ;--------------------------------------------------------------------------
        ; gcd_inner(int a, int b, int level)
        ;
        ; - args pushed right to left convention
        ; - clean up after (caller removes them)
        ; - whoever calls gcd_inner, reads the result from eax
        ; - uses only eax, ecx, and edx (scratch registers)
        ; - no callee-saved preserved
        ; - level lets the recursion count how deep it is
        ;
        ; stack frame:
        ;         args:
        ;         int level       [ebp + 16] 
        ;         int b           [ebp + 12]
        ;         int a           [ebp + 8]
        ;
        ;         return address  [ebp + 4]
        ;         saved ebp       [ebp + 0]
        ;
        ; - gcd_depth must hold the deepest (peak) level reached
        ;   after the whole call returns
        ; - if we decrement the counter on the way out, 
        ;   it would end at 0 (if we track the calls)
        ; - each level records its own level only if it's deeper 
        ;   than what it is stored
        ; 
        ; Euclid:  gcd(a, 0) = a      gcd(a, b) = gcd(b, a % b)
        ; Operands are nonnegative, so idiv's remainder is the true a % b.
        ; ---------------------------------------------------------------------------
gcd_inner:
        enter   0,0

        mov     ecx, [ebp + 16]         ; ecx = level

        ; if level <= gcd_depth, keep the current peak
        cmp     ecx, [_gcd_depth]
        jle     .keep               

        ; else, (level > gcd_depth) store the new peak
        mov     [_gcd_depth], ecx       ; gcd_depth = level 

.keep:          ; euclid algo
        
        ; base case
        mov     eax, [ebp + 8]          ; eax = a
        mov     ecx, [ebp + 12]         ; ecx = b

        ; checks if b == 0 
        test    ecx, ecx
        jz      .done                   ; return a (already in eax)

        ; a mod b
        cdq                             ; sign-extend eax into edx:eax  
        idiv    ecx                     ; edx = a % b, eax = a / b

        ; builds args for gcd_inner(b, a % b, level + 1)
        mov     eax, [ebp + 16]         ; eax = level
        inc     eax                     ; level + 1

        ; push arguments for inner recursive call
        push    eax                     ; push level + 1
        push    edx                     ; push a % b
        push    ecx                     ; push b (new a in gcd_inner(a, b, level))

        ; recursive call
        call    gcd_inner

        ; clean up 3 args x 4 bytes
        add     esp, 12

.done:  
        leave
        ret

        global  _sum_range_asm
; -------------------------------------------------------------------------
; int sum_range_asm(int lo, int hi)
; Subsystem Owner: Percie Louise Y. Samaniego
;
; This is the main function that C calls to get the sum from lo to hi.
; It first saves lo and hi in ebx and esi, then calls bench_callback()
; once before starting the actual recursion in sum_range_inner(). We keep
; lo and hi in registers because bench_callback() may start another
; sum_range_asm() call before this one finishes. The outer call must still
; have its own values after the nested call returns, so each call keeps
; its values in its own stack frame and saved registers.
;
; Reentrancy design:
;       - Nothing that changes while the function runs is stored in .data/.bss.
;       - Each call gets its own stack frame and saved registers.
;       - lo and hi are kept in ebx and esi while the callback is running.
;       - The recursive helper only uses its own stack frames for its values.
;
; Stack frame:
;   [ebp + 12] = int hi
;   [ebp + 8]  = int lo
;   [ebp + 4]  = return address
;   [ebp + 0]  = saved ebp
;   [ebp - 4]  = saved ebx
;   [ebp - 8]  = saved esi
; -------------------------------------------------------------------------
_sum_range_asm:


        ; TODO: sum_range. Call bench_callback once, then recurse on
        ; (lo + 1, hi) and add lo. The base case lo > hi is 0. Put the
        ; recursion in a second routine that does not call bench_callback.
        ; Keep every intermediate on the stack. A global counter or
        ; accumulator here is what breaks reentrancy.
        ;

        enter   0,0
        push    ebx                     ; preserve callee-saved registers
        push    esi

        mov     ebx, [ebp + 8]          ; ebx = lo (held across bench_callback)
        mov     esi, [ebp + 12]         ; esi = hi (held across bench_callback)

        ; Notify harness once per C call; may start a nested sum_range_asm
        call    _bench_callback

        ; Push arguments right-to-left: sum_range_inner(lo, hi)
        push    esi                     ; arg 2: hi
        push    ebx                     ; arg 1: lo
        call    sum_range_inner
        add     esp, 8                  ; caller cleans 2 args x 4 bytes

        pop     esi                     ; restore in reverse order
        pop     ebx
        leave
        ret

; -------------------------------------------------------------------------
; sum_range_inner(int lo, int hi)
;
; Internal recursive helper (does NOT call bench_callback):
;   if lo > hi:  return 0
;   if lo == hi: return lo   (avoids signed overflow on lo + 1 at INT_MAX)
;   return lo + sum_range_inner(lo + 1, hi)
;
; Stack frame:
;   [ebp + 12] = int hi
;   [ebp + 8]  = int lo
;   [ebp + 4]  = return address
;   [ebp + 0]  = saved ebp
;   [ebp - 4]  = saved ebx (holds this frame's `lo` across child call)
; -------------------------------------------------------------------------
sum_range_inner:
        enter   0,0
        push    ebx                     ; preserve callee-saved ebx

        mov     ebx, [ebp + 8]          ; ebx = lo
        mov     ecx, [ebp + 12]         ; ecx = hi

        cmp     ebx, ecx
        jg      .empty_range            ; if lo > hi, sum is 0
        je      .single_elem            ; if lo == hi, sum is lo

        ; Recursive step: lo + sum_range_inner(lo + 1, hi)
        lea     eax, [ebx + 1]          ; eax = lo + 1
        push    ecx                     ; arg 2: hi
        push    eax                     ; arg 1: lo + 1
        call    sum_range_inner
        add     esp, 8                  ; caller cleans 2 args x 4 bytes

        add     eax, ebx                ; eax = lo + sum_range_inner(lo + 1, hi)
        jmp     .done

.empty_range:
        xor     eax, eax                ; return 0
        jmp     .done

.single_elem:
        mov     eax, ebx                ; return lo

.done:
        pop     ebx
        leave
        ret
