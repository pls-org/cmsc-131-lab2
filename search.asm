; Searching Subsystem: Justin B. Lauricio 
;
; search.asm - bsearch_asm, a recursive binary search callable from C.
;
; This is your starting point: it assembles and links as-is, so the build
; works before you write any code. Right now it always returns 0, which
; makes the benchmark report a match at index 0 for any key. Your job is to
; replace that with the search described below.
;
; The contract, from bench.c:
;
;       int key                    [ebp+16]
;       int n                      [ebp+12]
;       int *arr                   [ebp+8]
;
; Return the index of key in the sorted array, or -1 if it is absent.
; Preserve ebx/esi/edi/ebp, return in eax, and obey cdecl for the outer
; routine (the internal recursive one may use any convention you document).
;
; Requirements from the manual:
;
;   * Recursive.
;   * Compute the midpoint as lo + (hi - lo) / 2, never (lo + hi) / 2.
;     The sum can overflow 32 bits on large arrays. The difference cannot.
;     This exact bug lived in the Java standard library for nine years.
;   * An absent key returns -1.
;   * An empty array and a single-element array must behave.
;   * No calls into the C standard library.
;
; The manual's pseudocode:
;
;   bsearch(arr, lo, hi, key):
;       if lo > hi: return -1
;       mid = lo + (hi - lo) / 2
;       if arr[mid] == key: return mid
;       if arr[mid] < key:  return bsearch(arr, mid + 1, hi, key)
;       else:               return bsearch(arr, lo, mid - 1, key)
;

; Windows C puts a leading underscore on every exported name. Linux C does
; not. The Makefile passes -d ELF_TYPE on Linux. This block then respells
; the names below to match. asm_io.inc does the same for _asm_main in the
; bootcamp blocks. Leave this block alone.
%ifdef ELF_TYPE
  %define _bsearch_asm bsearch_asm
  section .note.GNU-stack noalloc noexec nowrite progbits
%endif

segment .text
        global  _bsearch_asm
_bsearch_asm:
        enter   0,0
        pusha

        ;
        ; TODO: search.
        ;
        ; n is a count, so the search range is lo=0, hi=n-1. An empty array
        ; has n=0, which makes hi=-1 before the first comparison. That case
        ; must return -1 immediately.
        ;
        ; For the midpoint, compute hi - lo first, halve it, then add lo.
        ; The base case runs before the midpoint, so hi - lo is never
        ; negative there and a shift halves it. If you reach for idiv
        ; instead, sign-extend with cdq. mov edx, 0 is right only for a
        ; dividend that cannot be negative.
        ;

        ;----------------------------------------------------------------
        ; bsearch_asm(int *arr, int n, int key)
        ;
        ; converts function args into (arr, lo, hi, key), 
        ; and it cleans up afterward.
        ;
        ; where the stack frame:
        ;         int key         [ebp + 16]
        ;         int n           [ebp + 12]
        ;         int *arr        [ebp + 8] 
        ;
        ;         return address  [ebp + 4]
        ;         saved ebp       [ebp + 0]
        ;----------------------------------------------------------------

        mov     eax, [ebp + 12]         ; eax = n
        dec     eax                     ; eax = hi = n - 1

        ; cdecl pushes args right to left 
        push    dword [ebp + 16]        ; push key 
        push    eax                     ; push hi  
        push    dword 0                 ; lo = 0
        push    dword [ebp + 8]         ; push arr
        call    bsearch_inner

        ; clean up: 4 args x 4 bytes
        add     esp, 16                

        leave                           ; result is already in eax
        ret

        ; -------------------------------------------------------------------------
        ; bsearch_inner(int *arr, int lo, int hi, int key)
        ;
        ; - whoever calls bsearch_inner reads the result from eax
        ; - ebx and esi are preserved
        ; - ecx and edx are used as scratch registers
        ;
        ; stack frame:
        ;         args:
        ;         int key         [ebp + 20]
        ;         int hi          [ebp + 16]
        ;         int lo          [ebp + 12] 
        ;         int *rr         [ebp + 8]
        ;
        ;         return address  [ebp + 4]
        ;         saved ebp       [ebp + 0]
        ;
        ;         preserved registers:
        ;         saved ebx       [ebp - 4]
        ;         saved esi       [ebp - 8]
        ;
        ; - when bsearch_inner calls itself, the outer 
        ;   invocation relies on ebx and esi surviving the inner call
        ; 
        ; for tracking, register used inside one call:
        ;       esi = *arr    ecx = lo    edx = hi   ebx = mid  
        ; ------------------------------------------------------------------------

        bsearch_inner:
                ; prologue
                enter   0,0
                push    ebx     
                push    esi

                mov     esi, [ebp + 8]          ; esi = *arr
                mov     ecx, [ebp + 12]         ; ecx = lo
                mov     edx, [ebp + 16]         ; edx = hi

                ; base case
                cmp     ecx, edx                ; if lo > hi: nothing left
                jg      .absent                 ; return -1  

                ; mid = lo + (hi - lo) / 2
                ; the sum can overflow if we use (lo + hi) / 2
                ; hi - lo is never larger than the array, so this can't overflow

                mov     ebx, edx                ; ebx = hi
                sub     ebx, ecx                ; ebx = hi - lo
                shr     ebx, 1                  ; ebx = (hi - lo) / 2
                add     ebx, ecx                ; ebx = lo + (hi - lo) / 2

                mov     eax, [esi + ebx*4]      ; eax = arr[mid]
                cmp     eax, [ebp + 20]         ; check if arr[mid] == key
                je      .found                  ; return mid
                jl      .go_right               ; arr[mid] < key: search right

                ; else (arr[mid] > key), search left
                ; bsearch(arr, lo, mid - 1, key)
                lea     eax, [ebx - 1]          ; new hi: hi = mid - 1
                push    dword [ebp + 20]        ; push key
                push    eax                     ; push hi (eax = new hi)
                push    ecx                     ; push lo
                push    esi                     ; push *arr

                ; recursive call
                call    bsearch_inner
                add     esp, 16                 ; clean up (4 args x 4 bytes)
                jmp     .done


        .go_right:
                ; bsearch(arr, mid + 1, hi, key)
                ; search right: mid + 1 to hi

                lea     eax, [ebx + 1]          ; new lo: lo = mid + 1
                push    dword [ebp + 20]        ; push key
                push    edx                     ; push hi 
                push    eax                     ; push lo (eax = new lo)
                push    esi                     ; push *arr

                ; recursive call
                call    bsearch_inner
                add     esp, 16                 ; clean up (4 args x 4 bytes)
                jmp     .done  

        .found: 
                mov     eax, ebx                ; return mid
                jmp     .done

        .absent:        
                mov     eax, -1                 ; return -1

        .done:   
                ; restore in reverse order
                pop     esi
                pop     ebx
                leave 
                ret

        
