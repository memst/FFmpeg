/*
 * This file is part of FFmpeg.
 *
 * FFmpeg is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * FFmpeg is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with FFmpeg; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#define TX_DOUBLE
#include "libavutil/tx_priv.h"
#include "libavutil/riscv/cpu.h"

#include "libavutil/tx_template.c"
#include "../lavu_fft_test/memst_fft16.c"
static int count = 0;

void ff_fft4_double_riscv       (AVTXContext *s, void *out, void *in, ptrdiff_t stride);
void ff_fft8_double_riscv       (AVTXContext *s, void *out, void *in, ptrdiff_t stride);
void ff_fft8_double_riscv_v128  (AVTXContext *s, void *out, void *in, ptrdiff_t stride);
void ff_fft16_double_riscv      (AVTXContext *s, void *out, void *in, ptrdiff_t stride);

static av_unused void test_fft(AVTXContext *s, void *_out, void *_in,
                               ptrdiff_t stride)
{
    printf("count: %d\n", count);
    FFTComplex *in = _in;
    FFTComplex *out = _out;

    FFTComplex *temp = av_malloc(2 * s->m * sizeof(FFTComplex)), *orig = temp;
    for (int i = 0; i < s->m; i++) {
        temp[i] = in[i];
        out[i] = in[s->revtab[i]];
    }
    switch (s->m){
        case 8:
            ff_fft8_double_riscv_v128(s, out, out, 0);
            break;
        case 16:
            if (count == 0){
                memst_fft16(s, out, out, 0);
                count++;
            } else{
                fft8(out+0);
                fft4(out+8);
                fft4(out+12);
                ff_fft16_double_riscv(s, out, out, 0); 
            }

            break;
    }
    

    //ff_fft8_double_riscv(s, temp, temp, stride);

    av_free(orig);
}

av_cold void ff_tx_init_double_riscv(AVTXContext *s, av_tx_fn *tx) {
    /*
        TO-DO: Create cpu flags to check the vlen avilable, fft8 works only with vlen 128 and above.
        This is quite a reasonable length, but spec doesn't perscribe it.
    */

    int cpu_flags = av_get_cpu_flags();
    int gen_revtab = 0, basis, revtab_interleave;

    if (s->flags & AV_TX_UNALIGNED)
        return;

#define TXFN(fn, gentab, sr_basis, interleave) \
    do {                                       \
        *tx = fn;                              \
        gen_revtab = gentab;                   \
        basis = sr_basis;                      \
        revtab_interleave = interleave;        \
    } while (0)

    if (s->n == 1 && have_rvv(cpu_flags)) {
        switch(s->m){
        case 4:
            TXFN(ff_fft4_double_riscv, 1, 8, 0);
            break;
        case 8:
            if (1)//There should be a method to check VLEN, or it should be in 
                  //a flag, but that would potentially take up 16b
                TXFN(ff_fft8_double_riscv_v128, 1, 8, 0); //_v128 is faster but 
                                     //works only on processors with VLEN = 128
            else
                TXFN(ff_fft8_double_riscv, 1, 8, 0);
            break;
        case 16:
            TXFN(ff_fft16_double_riscv, 0, 8, 0);
            break;
        }
    }

    //Test only
    TXFN(test_fft, 0, 8, 0);

    
    if (gen_revtab)
        ff_tx_gen_split_radix_parity_revtab(s->revtab, s->m, s->inv, basis,
                                            revtab_interleave);

    //Test only
    int* revtab = s->revtab;
    for  (int i = 0; i < s->m; i++)
        printf("%d ", revtab[i]);
    printf("\n");
#undef TXFN
}

