        .section .text
        .align  2
        .global sudoku_solver
        .type   sudoku_solver, @function

# Solve a valid, solvable 4x4 Sudoku puzzle using backtracking.
# Input: a0 points to 16 row-major int32_t cells; 0 means empty, 1-4 are clues.
# Output: fill the board in place without modifying fixed clues; no public return value.
# Tail-jump to the internal search routine, preserving the original return address.
# Public entry point: a0 contains the base address of the 4x4 board.
# The jump reuses the caller's return address; the search routine returns to the caller.
sudoku_solver:
        j       .Lsudoku_search
        .size   sudoku_solver, .-sudoku_solver

        .type   .Lsudoku_search, @function
# Internal search: a0 = board; return a0 = 1 on success, or 0 on failure.
# Use a 32-byte stack frame at each level to maintain 16-byte stack alignment.
# Recursive depth-first search with backtracking.
# Saved registers: s0=board, s1=cell index, s2=candidate, s3=cell address.
# Each stack frame is 32 bytes, preserving 16-byte alignment at calls.
.Lsudoku_search:
        addi    sp, sp, -32
        sw      ra, 28(sp)  # Save ra before recursive and helper calls
        sw      s0, 24(sp)
        sw      s1, 20(sp)
        sw      s2, 16(sp)
        sw      s3, 12(sp)
        mv      s0, a0  # Keep board pointer across calls
        li      s1, 0  # Current cell index
# Scan the board in row-major order for the first zero-valued cell.
# Each int32_t occupies 4 bytes, so board[i] is at board + (i << 2).
.Lsudoku_find:
        li      t0, 16
        beq     s1, t0, .Lsudoku_success  # No empty cells remain: solution found
        slli    t0, s1, 2
        add     s3, s0, t0  # Address of board[index]
        lw      t1, 0(s3)
        beq     t1, zero, .Lsudoku_empty
        addi    s1, s1, 1  # Skip nonempty clues without changing them
        j       .Lsudoku_find
# An empty cell was found; enumerate candidate values 1, 2, 3, and 4.
.Lsudoku_empty:
        li      s2, 1  # Candidate value from 1 to 4
# Call the validity helper before modifying the board.
# Arguments: a0=board, a1=linear cell index, a2=candidate.
# On a valid placement, recurse. A failed recursive attempt is undone.
.Lsudoku_try:
        mv      a0, s0
        mv      a1, s1
        mv      a2, s2
        jal     ra, .Lsudoku_valid  # Check row, column, and 2x2 subgrid
        beq     a0, zero, .Lsudoku_next
        sw      s2, 0(s3)  # Place candidate only if valid
        mv      a0, s0
        jal     ra, .Lsudoku_search  # Recursively solve remaining empty cells
        bne     a0, zero, .Lsudoku_success  # Keep solution if recursion succeeds
        sw      zero, 0(s3)  # Undo trial placement on failure
# Advance to the next candidate. If all four fail, return failure
# so the previous recursion level can try a different value.
.Lsudoku_next:
        addi    s2, s2, 1
        li      t0, 5
        bltu    s2, t0, .Lsudoku_try
        li      a0, 0  # All candidates failed: backtrack
        j       .Lsudoku_return
# Success means every cell is nonzero after valid placements.
# Leave all chosen values in memory and propagate success up the call stack.
.Lsudoku_success:
        li      a0, 1
# Restore callee-saved registers and ra from their original stack slots.
# Release the 32-byte frame and return the Boolean result in a0.
.Lsudoku_return:
        lw      s3, 12(sp)
        lw      s2, 16(sp)
        lw      s1, 20(sp)
        lw      s0, 24(sp)
        lw      ra, 28(sp)
        addi    sp, sp, 32  # Restore stack pointer and callee-saved registers
        ret
        .size   .Lsudoku_search, .-.Lsudoku_search

        .type   .Lsudoku_valid, @function
# Inputs: a0 = board, a1 = index, a2 = candidate; target cell is still zero.
# Return a0 = 1 if valid, 0 if conflicting; leaf helper uses caller-saved registers.
# Leaf routine: check whether a candidate conflicts with the current board.
# Input: a0=board pointer, a1=index (0..15), a2=value (1..4).
# Output: a0=1 when allowed; a0=0 on any row/column/box conflict.
# For a 4-column board: row=index>>2 and column=index&3.
.Lsudoku_valid:
        srli    t0, a1, 2  # row = index / 4
        andi    t1, a1, 3  # col = index % 4
        slli    t2, t0, 4  # Four int32_t values per row = 16 bytes
        add     t2, a0, t2  # Start address of current row
        li      t3, 4
# Inspect four consecutive 32-bit entries in the selected row.
# If any entry equals the candidate, reject immediately.
.Lvalid_row:
        lw      t4, 0(t2)
        beq     t4, a2, .Lvalid_no
        addi    t2, t2, 4
        addi    t3, t3, -1
        bne     t3, zero, .Lvalid_row
        slli    t2, t1, 2
        add     t2, a0, t2  # Address of first row at current column
        li      t3, 4
# Inspect the same column across four rows.
# A row is 4 words = 16 bytes, hence the 16-byte stride.
.Lvalid_col:
        lw      t4, 0(t2)
        beq     t4, a2, .Lvalid_no
        addi    t2, t2, 16  # Move down one row (16 bytes)
        addi    t3, t3, -1
        bne     t3, zero, .Lvalid_col
        andi    t0, t0, 2  # Subgrid starting row is 0 or 2
        andi    t1, t1, 2  # Subgrid starting column is 0 or 2
        slli    t0, t0, 4
        slli    t1, t1, 2
        add     t2, a0, t0
        add     t2, t2, t1  # Top-left cell of the 2x2 subgrid
        lw      t4, 0(t2)
        beq     t4, a2, .Lvalid_no
        lw      t4, 4(t2)
        beq     t4, a2, .Lvalid_no
        lw      t4, 16(t2)
        beq     t4, a2, .Lvalid_no
        lw      t4, 20(t2)
        beq     t4, a2, .Lvalid_no
        li      a0, 1
        ret
# Shared rejection path for a duplicate in the row, column, or box.
.Lvalid_no:
        li      a0, 0
        ret
        .size   .Lsudoku_valid, .-.Lsudoku_valid
