#include "sudoku_config.h"

extern void sudoku_solver(int *arr_ptr);

int sudoku_verifier(int *arr_ptr, const int *clues) {
    // Every non-zero input value is a fixed clue and must remain unchanged.
    for (int i = 0; i < 16; i++) {
        if (clues[i] != 0 && arr_ptr[i] != clues[i]) {
            return -1;
        }
    }

    // check each row and column
    for (int i = 0; i < 4; i++) {
        int row[5] = { 0 }, col[5] = { 0 };
        for (int j = 0; j < 4; j++) {
            int r = arr_ptr[4 * i + j];
            int c = arr_ptr[4 * j + i];

            if (r < 1 || r > 4 || row[r]) {
                return -1;
            }
            if (c < 1 || c > 4 || col[c]) {
                return -1;
            }

            row[r] = 1;
            col[c] = 1;
        }
    }

    // check each sub-block
    for (int bi = 0; bi < 2; bi++) {
        for (int bj = 0; bj < 2; bj++) {
            int seen[5] = { 0 };
            for (int i = 0; i < 2; i++) {
                for (int j = 0; j < 2; j++) {
                    int v = arr_ptr[(bi * 2 + i) * 4 + (bj * 2 + j)];
                    if (v < 1 || v > 4 || seen[v]) {
                        return -1;
                    }
                    seen[v] = 1;
                }
            }
        }
    }

    return 0;
}

int main(void) {
    const int clues[] = { SUDOKU_RANDOM_ARRAY };
    int arr[]          = { SUDOKU_RANDOM_ARRAY };
    sudoku_solver(arr);
    return sudoku_verifier(arr, clues);
}
