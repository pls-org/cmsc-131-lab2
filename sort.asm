;
; Subsystem Owner: Samantha F. Mok
;
; sort.asm - qsort_asm, a recursive quicksort callable from C.
;
; This is your starting point: it assembles and links as-is, so the build
; works before you write any code. Right now it does nothing, which makes
; the benchmark print "NOT SORTED" and "Match: NO". Your job is to replace
; that with the sort described below.
;
; The contract, from bench.c:
;
;       int n                     [ebp+12]
;       int *arr                  [ebp+8]
;
; Sort n 32-bit signed integers in place, ascending. This is the C-facing
; routine. It must obey cdecl (prologue, args at [ebp+8]+, return in eax,
; preserve ebx/esi/edi/ebp, clean arguments after every call it makes). The
; manual lets you use any convention you document for the internal recursive
; routine, but the outer one is fixed.
;
; Requirements from the manual:
;
;   * Recursive. An iterative sort with an explicit stack array does not
;     satisfy the activity.
;   * Lomuto partition with the last element as pivot (the manual's scheme).
;   * No calls into the C standard library.
;   * Clean the arguments off the stack after each call. The next pop
;     otherwise loads an argument into a register you promised to
;     preserve, and the outer call's array base is gone.
;
; The manual's pseudocode:
;
;   qsort(arr, lo, hi):
;       if lo >= hi: return
;       p = partition(arr, lo, hi)
;       qsort(arr, lo, p - 1)
;       qsort(arr, p + 1, hi)
;
;   partition(arr, lo, hi):
;       pivot = arr[hi]
;       i = lo - 1
;       for j = lo to hi - 1:
;           if arr[j] <= pivot:
;               i = i + 1
;               swap arr[i], arr[j]
;       swap arr[i + 1], arr[hi]
;       return i + 1
;

; Windows C puts a leading underscore on every exported name. Linux C does
; not. The Makefile passes -d ELF_TYPE on Linux. This block then respells
; the names below to match. asm_io.inc does the same for _asm_main in the
; bootcamp blocks. Leave this block alone.
%ifdef ELF_TYPE
  %define _qsort_asm qsort_asm
  section .note.GNU-stack noalloc noexec nowrite progbits
%endif

segment .text
        global  _qsort_asm

_qsort_asm:
        enter   0,0
        
        ; preserve callee-saved registers
        push    ebx                 ; stack: [ebp - 4]
        push    esi                 ;        [ebp - 8]
        push    edi                 ;        [ebp - 12]

        ; load arguments
        mov     edi, [ebp + 8]      ; edi = arr
        mov     edx, [ebp + 12]     ; edx = n (number of elements)
        
        ; base case for empty or 1-element array
        cmp     edx, 1              ; if n <= 1, exit
        jle     .done_sorting   

        dec     edx                 ; edx = n - 1 (hi)
        mov     ecx, 0              ; ecx = 0 (lo)

        ; register convention: 
        ; edi = arr (base pointer) - holds starting memory address
        ; ecx = lo or lower bound of array to be sorted 
        ; edx = hi or upper bound of array to be sorted

        call    .qsort_recursive

.done_sorting:
        ; restore callee-saved registers
        pop     edi
        pop     esi
        pop     ebx
        leave
        ret

; -------------------------------------------------------------
; internal recursive function
; inputs: edi = arr, ecx = lo, edx = hi
; -------------------------------------------------------------
.qsort_recursive:
        cmp     ecx, edx
        jge     .qsort_return       ; return if lo >= hi

        ; save lo and hi on stack: [esp+4] = lo, [esp] = hi
        push    ecx                 
        push    edx                 

; --------------------- PARTITION (refer to pseudocode) ---------------------
        mov     esi, ecx            ; i = lo
        dec     esi                 ; i = lo - 1
        mov     eax, [edi+edx*4]    ; pivot = arr[hi]

; ecx is currently lo, acting as j (element index)
.part_loop:
        cmp     ecx, [esp]          ; compare j (ecx) to hi (at [esp])
        jge     .part_end           ; if j >= hi, partition done
        
        cmp     [edi+ecx*4], eax    ; compare arr[j] to pivot
        jg      .no_swap            ; if arr[j] > pivot, don't swap

        ; swap arr[i+1] and arr[j]
        inc     esi                 ; i = i + 1
        mov     ebx, [edi+ecx*4]    ; ebx = arr[j]
        xchg    ebx, [edi+esi*4]    ; arr[i] = arr[j], ebx = old arr[i]
        mov     [edi+ecx*4], ebx    ; arr[j] = old arr[i]

.no_swap:
        inc     ecx                 ; j = j + 1, move to next element
        jmp     .part_loop          ; loop back

.part_end:
        inc     esi                 ; i = i + 1 (final pivot index)
        mov     edx, [esp]          ; edx = hi

        ; swap arr[i+1] and arr[hi]
        mov     ebx, [edi+esi*4]    ; ebx = arr[i+1]
        xchg    ebx, [edi+edx*4]    ; arr[hi] = arr[i+1], ebx = old arr[hi]
        mov     [edi+esi*4], ebx    ; arr[i+1] = old arr[hi]

        ; --------------------- RECURSIVE CALLS ---------------------
        push    esi                 ; stack: [esp + 8] = lo, [esp + 4] = hi, [esp] = pivot

        ; left call: qsort(arr, lo, pivot - 1)
        mov     ecx, [esp + 8]      ; ecx = original lo (offset shifted by push esi)
        mov     edx, esi
        dec     edx                 ; edx = pivot - 1
        call    .qsort_recursive

        ; right call: qsort(arr, pivot + 1, hi)
        pop     esi                 ; restore pivot index (pops 4 bytes)
        mov     ecx, esi
        inc     ecx                 ; ecx = pivot + 1
        mov     edx, [esp]          ; edx = original hi (at esp after pop)
        call    .qsort_recursive

        ; clear saved lo and hi from stack (2 dwords = 8 bytes)
        add     esp, 8              ; restore esp to return address location

.qsort_return:
        ret                         ; pops return address
