.section .text
        .align  2
        .global array_sort
        .type   array_sort, @function

# void array_sort(int32_t *array, uint32_t size)
#
# a0: Pointer to the first signed 32-bit array element.
# a1: Number of elements (0 through 128).
#
# Sort the array in ascending SIGNED order using merge sort.
# The final sorted values are written back into the input array.
# A 128-element temporary buffer is allocated on the stack.
#
# Calling convention:
#   - s0 and s1 are callee-saved and are restored before returning.
#   - The stack remains 16-byte aligned at every function call.
#   - All helper routines use caller-saved registers only.
#
# Stack frame (544 bytes):
#   0..511   Temporary merge buffer (128 * 4 bytes)
#   528      Saved s1 (buffer base)
#   532      Saved s0 (array base)
#   536      Saved ra
#   540      Unused padding
array_sort:
        addi    sp, sp, -544       # Reserve temporary storage and saved-register slots.
        sw      ra, 536(sp)        # Preserve the return address.
        sw      s0, 532(sp)        # Preserve the caller's s0.
        sw      s1, 528(sp)        # Preserve the caller's s1.
        mv      s0, a0             # Keep the original array base in s0.
        mv      s1, sp             # Use the beginning of the frame as the buffer.

        li      t0, 2              # Arrays with fewer than two elements are sorted.
        bltu    a1, t0, .Lsort_done

        # Recursive helper arguments:
        #   a0 = array base, a1 = temporary buffer base
        #   a2 = left index (inclusive), a3 = right index (exclusive)
        mv      a3, a1             # Preserve size before replacing a1 with buffer.
        mv      a1, s1             # Temporary buffer pointer.
        mv      a2, zero           # Left boundary = 0.
        mv      a0, s0             # Original array pointer.
        jal     ra, .Lmerge_sort

.Lsort_done:
        lw      s1, 528(sp)        # Restore callee-saved registers.
        lw      s0, 532(sp)
        lw      ra, 536(sp)
        addi    sp, sp, 544        # Release the temporary buffer and frame.
        ret

# Recursive merge sort over the half-open range [left, right).
# Arguments: a0=array, a1=buffer, a2=left, a3=right.
# This routine saves its working state because recursive calls overwrite
# caller-saved argument registers.
.Lmerge_sort:
        addi    sp, sp, -48        # Allocate an aligned recursive stack frame.
        sw      ra, 44(sp)
        sw      s0, 40(sp)
        sw      s1, 36(sp)
        sw      s2, 32(sp)
        sw      s3, 28(sp)
        sw      s4, 24(sp)
        sw      s5, 20(sp)
        mv      s0, a0             # Array base.
        mv      s1, a1             # Buffer base.
        mv      s2, a2             # Left index.
        mv      s3, a3             # Right index (exclusive).

        sub     t0, s3, s2         # Number of elements in the current range.
        li      t1, 2
        bltu    t0, t1, .Lmerge_return # Length 0 or 1: already sorted.

        srli    t0, t0, 1          # Half the range length, rounded down.
        add     s4, s2, t0         # Midpoint = left + (right-left)/2.

        # Sort the left half [left, mid).
        mv      a0, s0
        mv      a1, s1
        mv      a2, s2
        mv      a3, s4
        jal     ra, .Lmerge_sort

        # Sort the right half [mid, right).
        mv      a0, s0
        mv      a1, s1
        mv      a2, s4
        mv      a3, s3
        jal     ra, .Lmerge_sort

        # Merge two sorted halves into buffer[left:right].
        mv      t0, s2             # i: current index in left half.
        mv      t1, s4             # j: current index in right half.
        mv      t2, s2             # k: destination index in buffer.

.Lmerge_compare:
        bgeu    t0, s4, .Lcopy_right # Left half exhausted.
        bgeu    t1, s3, .Lcopy_left  # Right half exhausted.
        slli    t3, t0, 2          # Convert left element index to byte offset.
        add     t3, s0, t3
        lw      t4, 0(t3)          # Load signed left value.
        slli    t3, t1, 2
        add     t3, s0, t3
        lw      t5, 0(t3)          # Load signed right value.
        blt     t5, t4, .Ltake_right # Signed comparison: right < left.

        # Left value <= right value; take left to preserve stable order.
        slli    t3, t2, 2
        add     t3, s1, t3
        sw      t4, 0(t3)
        addi    t0, t0, 1
        addi    t2, t2, 1
        j       .Lmerge_compare

.Ltake_right:
        slli    t3, t2, 2
        add     t3, s1, t3
        sw      t5, 0(t3)
        addi    t1, t1, 1
        addi    t2, t2, 1
        j       .Lmerge_compare

.Lcopy_left:
        bgeu    t0, s4, .Lcopy_back # No remaining left elements.
        slli    t3, t0, 2
        add     t3, s0, t3
        lw      t4, 0(t3)
        slli    t3, t2, 2
        add     t3, s1, t3
        sw      t4, 0(t3)
        addi    t0, t0, 1
        addi    t2, t2, 1
        j       .Lcopy_left

.Lcopy_right:
        bgeu    t1, s3, .Lcopy_back # No remaining right elements.
        slli    t3, t1, 2
        add     t3, s0, t3
        lw      t4, 0(t3)
        slli    t3, t2, 2
        add     t3, s1, t3
        sw      t4, 0(t3)
        addi    t1, t1, 1
        addi    t2, t2, 1
        j       .Lcopy_right

.Lcopy_back:
        mv      t0, s2             # Copy merged range back into input array.
.Lcopy_back_loop:
        bgeu    t0, s3, .Lmerge_return
        slli    t1, t0, 2
        add     t2, s1, t1
        lw      t3, 0(t2)          # Read merged value from temporary buffer.
        add     t2, s0, t1
        sw      t3, 0(t2)          # Overwrite original array element.
        addi    t0, t0, 1
        j       .Lcopy_back_loop

.Lmerge_return:
        lw      s5, 20(sp)
        lw      s4, 24(sp)
        lw      s3, 28(sp)
        lw      s2, 32(sp)
        lw      s1, 36(sp)
        lw      s0, 40(sp)
        lw      ra, 44(sp)
        addi    sp, sp, 48
        ret

        .size   array_sort, .-array_sort
