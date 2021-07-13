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

void ff_fft4_double_riscv    (AVTXContext *s, void *out, void *in, ptrdiff_t stride);
void ff_fft8_double_riscv    (AVTXContext *s, void *out, void *in, ptrdiff_t stride);
void ff_fft16_double_riscv   (AVTXContext *s, void *out, void *in, ptrdiff_t stride);

#include <float.h>
static void fft8(FFTComplex *z)
{
    FFTSample r1 = z[0].re - z[4].re;
    FFTSample r2 = z[0].im - z[4].im;
    FFTSample r3 = z[1].re - z[5].re;
    FFTSample r4 = z[1].im - z[5].im;

    FFTSample r5 = z[2].re - z[6].re;
    FFTSample r6 = z[2].im - z[6].im;
    FFTSample r7 = z[3].re - z[7].re;
    FFTSample r8 = z[3].im - z[7].im;

    FFTSample q1 = z[0].re + z[4].re;
    FFTSample q2 = z[0].im + z[4].im;
    FFTSample q3 = z[1].re + z[5].re;
    FFTSample q4 = z[1].im + z[5].im;

    FFTSample q5 = z[2].re + z[6].re;
    FFTSample q6 = z[2].im + z[6].im;
    FFTSample q7 = z[3].re + z[7].re;
    FFTSample q8 = z[3].im + z[7].im;

    FFTSample s3 = q1 - q3;
    FFTSample s1 = q1 + q3;
    FFTSample s4 = q2 - q4;
    FFTSample s2 = q2 + q4;

    FFTSample s7 = q5 - q7;
    FFTSample s5 = q5 + q7;
    FFTSample s8 = q6 - q8;
    FFTSample s6 = q6 + q8;

    FFTSample e1 = s1 * -1;
    FFTSample e2 = s2 * -1;
    FFTSample e3 = s3 * -1;
    FFTSample e4 = s4 * -1;

    FFTSample e5 = s5 *  1;
    FFTSample e6 = s6 *  1;
    FFTSample e7 = s7 * -1;
    FFTSample e8 = s8 *  1;

    FFTSample w1 =  e5 - e1;
    FFTSample w2 =  e6 - e2;
    FFTSample w3 =  e8 - e3;
    FFTSample w4 =  e7 - e4;

    FFTSample w5 =  s1 - e5;
    FFTSample w6 =  s2 - e6;
    FFTSample w7 =  s3 - e8;
    FFTSample w8 =  s4 - e7;

    z[0].re = w1;
    z[0].im = w2;
    z[2].re = w3;
    z[2].im = w4;
    z[4].re = w5;
    z[4].im = w6;
    z[6].re = w7;
    z[6].im = w8;

    FFTSample z1 = r1 - r4;
    FFTSample z2 = r1 + r4;
    FFTSample z3 = r3 - r2;
    FFTSample z4 = r3 + r2;

    FFTSample z5 = r5 - r6;
    FFTSample z6 = r5 + r6;
    FFTSample z7 = r7 - r8;
    FFTSample z8 = r7 + r8;

    z3 *= -1;
    z5 *= -M_SQRT1_2;
    z6 *= -M_SQRT1_2;
    z7 *=  M_SQRT1_2;
    z8 *=  M_SQRT1_2;

    FFTSample t5 = z7 - z6;
    FFTSample t6 = z8 + z5;
    FFTSample t7 = z8 - z5;
    FFTSample t8 = z7 + z6;

    FFTSample u1 =  z2 + t5;
    FFTSample u2 =  z3 + t6;
    FFTSample u3 =  z1 - t7;
    FFTSample u4 =  z4 + t8;

    FFTSample u5 =  z2 - t5;
    FFTSample u6 =  z3 - t6;
    FFTSample u7 =  z1 + t7;
    FFTSample u8 =  z4 - t8;

    z[1].re = u1;
    z[1].im = u2;
    z[3].re = u3;
    z[3].im = u4;
    z[5].re = u5;
    z[5].im = u6;
    z[7].re = u7;
    z[7].im = u8;
}

static av_unused void test_fft(AVTXContext *s, void *_out, void *_in,
                               ptrdiff_t stride)
{
    FFTComplex *in = _in;
    FFTComplex *out = _out;

    FFTComplex *temp = av_malloc(2 * s->m * sizeof(FFTComplex)), *orig = temp;
    for (int i = 0; i < s->m; i++) {
        temp[i] = in[i];
        out[i] = in[s->revtab[i]];
    }

    fft8(out);

    ff_fft8_double_riscv(s, temp, temp, stride);

    av_free(orig);
}

#if 0
    temp += 0; out += temp - orig;

    FFTComplex *ptr = (void *)out;

    printf("\nIDX =      0re      0im      1re      1im      2re      2im      3re      3im\n"
             "REF = %f %f %f %f %f %f %f %f\n"
             "OUT = %f %f %f %f %f %f %f %f\n"
             "TST =        %i        %i        %i        %i        %i        %i        %i        %i\n\n",
           ptr[0].re, ptr[0].im, ptr[1].re, ptr[1].im,
           ptr[2].re, ptr[2].im, ptr[3].re, ptr[3].im,
           temp[0].re, temp[0].im, temp[1].re, temp[1].im,
           temp[2].re, temp[2].im, temp[3].re, temp[3].im,
           fabsf(ptr[0].re - temp[0].re) <= 2*FLT_EPSILON, fabsf(ptr[0].im - temp[0].im) <= 2*FLT_EPSILON,
           fabsf(ptr[1].re - temp[1].re) <= 2*FLT_EPSILON, fabsf(ptr[1].im - temp[1].im) <= 2*FLT_EPSILON,
           fabsf(ptr[2].re - temp[2].re) <= 2*FLT_EPSILON, fabsf(ptr[2].im - temp[2].im) <= 2*FLT_EPSILON,
           fabsf(ptr[3].re - temp[3].re) <= 2*FLT_EPSILON, fabsf(ptr[3].im - temp[3].im) <= 2*FLT_EPSILON);

    out -= temp - orig;

#endif

av_cold void ff_tx_init_double_riscv(AVTXContext *s, av_tx_fn *tx) {
    printf("Reached init\n");
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
            TXFN(ff_fft8_double_riscv, 1, 8, 0);
            break;
        case 16:
            TXFN(ff_fft16_double_riscv, 1, 8, 0);
            break;
        }
    }

    //testing only
    //if (s->n == 1 && have_rvv(cpu_flags))
    //    TXFN(test_fft, 1, 8, 0);

    if (gen_revtab)
        ff_tx_gen_split_radix_parity_revtab(s->revtab, s->m, s->inv, basis,
                                            revtab_interleave);
#undef TXFN
}

