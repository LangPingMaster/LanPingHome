#include "merge_config.h"

#include "print.h"

extern void array_sort(int *arr_ptr, unsigned arr_size);

int array_sort_verifier(int *arr_ptr, unsigned arr_size) {
    for (unsigned i = 0; i + 1 < arr_size; i++) {
        my_printf("i: %d, i+1: %d\n", arr_ptr[i], arr_ptr[i + 1]);
        if (arr_ptr[i] > arr_ptr[i + 1]) {
            return -1;
        }
    }
    return 0;
}

int main(void) {
    int arr[] = { MERGE_SORT_RANDOM_ARRAY };
    array_sort(arr, MERGE_SORT_RANDOM_ARRAY_SIZE);
    return array_sort_verifier(arr, MERGE_SORT_RANDOM_ARRAY_SIZE);
}
