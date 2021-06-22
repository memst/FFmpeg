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
void ff_fft16_double_riscv      (AVTXContext *s, void *out, void *in, ptrdiff_t stride);

void ff_fft4_double_riscv_v128  (AVTXContext *s, void *out, void *in, ptrdiff_t stride);
void ff_fft8_double_riscv_v128  (AVTXContext *s, void *out, void *in, ptrdiff_t stride);

av_cold void ff_tx_init_double_riscv(AVTXContext *s, av_tx_fn *tx) {
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
#if 0
/* A method to check the VLEN length is yet to be implemented, if VLEN = 128b, 
 * a different set of methods for FFTs can be used that better utilise the 
 * registers, but are incompatible with other register lengths.
 */
            if (0)
                TXFN(ff_fft8_double_riscv_v128, 1, 8, 0); //_v128 is faster but 
                                     //works only on processors with VLEN = 128
            else
#endif
            TXFN(ff_fft8_double_riscv, 1, 8, 0);
            break;
        case 16:
            TXFN(ff_fft16_double_riscv, 1, 8, 0);
            break;
        }
    }

    
    if (gen_revtab)
        ff_tx_gen_split_radix_parity_revtab(s->revtab, s->m, s->inv, basis,
                                            revtab_interleave);
#undef TXFN
}

