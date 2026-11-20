/* vtts_bridge_smoke.c — kiểm thử shim `vtts_bridge` trên máy CI (macOS), gọi đúng các hàm mà `VttsRuntime` (Swift) gọi.
 *
 * `Scripts/ci/check_vtts_assets.sh` biên dịch file này cùng shim + runtime vtts ĐÃ VENDOR (`Vendor/vtts/Sources/CVTTS`)
 * với đúng cờ `VTTS_ENABLE_<L>=0` của gói SPM, bật ASan + UBSan, rồi chạy cho từng giọng. Bản dựng thử đặt
 * `-DVTTS_BRIDGE_SEGMENT_CP=150` để đường chia đoạn dài chạy với vài câu (bản app chia ở 2000 code point; shim có
 * `#error` bảo đảm ngưỡng luôn dưới VTTS_TEXT_MAX_CP = 4096, mức front-end bỏ im lặng phần sau).
 *
 * usage: vtts_bridge_smoke MODEL.vtts LEX.bin OUT.wav "câu thử" [--long]
 * Kiểm: tạo handle; câu thử ra ≥ 0,5 s tiếng, không NaN / Inf, RMS đủ lớn; chuỗi rỗng và chuỗi chỉ dấu câu ra 0 mẫu
 * không lỗi; thẻ huỷ đã bật ⇒ VTTS_BRIDGE_ERR_CANCELLED; `--long`: 8 bản câu thử liền nhau (bị chia thành nhiều phần)
 * ra đúng 8 lần tiếng câu thử + khoảng 150 ms giữa các câu. Ghi WAV 16-bit của câu thử. Lỗi bất kỳ ⇒ thoát mã ≠ 0. */
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "vtts_bridge.h"

static int fail(const char *what, int code) {
    fprintf(stderr, "FAIL %s: %d (%s)\n", what, code, vtts_bridge_error_name(code));
    return 1;
}

static int write_wav(const char *path, const float *pcm, long n, int sr) {
    FILE *f = fopen(path, "wb");
    uint32_t data, riff, rate, byte_rate, fmt_len = 16;
    uint16_t tag = 1, channels = 1, align = 2, bits = 16;
    long i;
    if (!f) return -1;
    data = (uint32_t)n * 2;
    riff = 36 + data;
    rate = (uint32_t)sr;
    byte_rate = rate * 2;
    fwrite("RIFF", 1, 4, f); fwrite(&riff, 4, 1, f); fwrite("WAVEfmt ", 1, 8, f);
    fwrite(&fmt_len, 4, 1, f); fwrite(&tag, 2, 1, f); fwrite(&channels, 2, 1, f); fwrite(&rate, 4, 1, f);
    fwrite(&byte_rate, 4, 1, f); fwrite(&align, 2, 1, f); fwrite(&bits, 2, 1, f);
    fwrite("data", 1, 4, f); fwrite(&data, 4, 1, f);
    for (i = 0; i < n; i++) {
        float v = pcm[i] > 1.0f ? 1.0f : pcm[i] < -1.0f ? -1.0f : pcm[i];
        int16_t s = (int16_t)lrintf(v * 32767.0f); /* cùng cách đổi của tools/vtts_say.c để so được */
        fwrite(&s, 2, 1, f);
    }
    return fclose(f);
}

/* 0 khi PCM hợp lệ (không NaN / Inf) và đủ to; in thời lượng + RMS. */
static int check_pcm(const char *label, const float *pcm, long n, int sr, double min_seconds) {
    double sum = 0.0, rms, seconds = (double)n / (double)sr;
    long i;
    for (i = 0; i < n; i++) {
        if (!isfinite(pcm[i])) {
            fprintf(stderr, "FAIL %s: mẫu %ld không hữu hạn\n", label, i);
            return 1;
        }
        sum += (double)pcm[i] * (double)pcm[i];
    }
    rms = n > 0 ? sqrt(sum / (double)n) : 0.0;
    printf("%s: %.2f s, rms %.4f\n", label, seconds, rms);
    if (seconds < min_seconds) {
        fprintf(stderr, "FAIL %s: chỉ %.2f s tiếng (cần ≥ %.2f s)\n", label, seconds, min_seconds);
        return 1;
    }
    if (rms < 0.005) {
        fprintf(stderr, "FAIL %s: gần như im lặng (rms %.5f)\n", label, rms);
        return 1;
    }
    return 0;
}

static int expect_silent(vtts_bridge *b, const char *label, const char *text) {
    float *pcm = NULL;
    long n = -1;
    int rc = vtts_bridge_synthesize(b, text, 1.0f, &pcm, &n);
    if (rc != VTTS_BRIDGE_OK) return fail(label, rc);
    if (pcm != NULL || n != 0) {
        fprintf(stderr, "FAIL %s: mong 0 mẫu, được %ld\n", label, n);
        vtts_bridge_free_pcm(pcm);
        return 1;
    }
    printf("%s: 0 mẫu (đúng)\n", label);
    return 0;
}

int main(int argc, char **argv) {
    const char *model, *lex, *out_wav, *text;
    vtts_bridge *b;
    vtts_bridge_cancel *cancel;
    float *pcm = NULL, *long_pcm = NULL;
    long n = 0, long_n = 0;
    int err = 0, rc, sr, failures = 0, copies = 0, run_long;
    char *long_text;
    size_t sentence_len, long_cap, used = 0;
    long code_points = 0;

    if (argc < 5) {
        fprintf(stderr, "usage: %s MODEL.vtts LEX.bin OUT.wav TEXT [--long]\n", argv[0]);
        return 2;
    }
    model = argv[1];
    lex = argv[2];
    out_wav = argv[3];
    text = argv[4];
    run_long = argc > 5 && strcmp(argv[5], "--long") == 0;

    b = vtts_bridge_create(model, lex, &err);
    if (!b) return fail("vtts_bridge_create", err);
    sr = vtts_bridge_sample_rate(b);
    printf("model %s: token_set %s, %d Hz\n", model, vtts_bridge_token_set_name(b), sr);
    if (sr <= 0) {
        vtts_bridge_destroy(b);
        return fail("sample_rate", sr);
    }

    /* 1. Câu thử Việt + Anh */
    rc = vtts_bridge_synthesize(b, text, 1.0f, &pcm, &n);
    if (rc != VTTS_BRIDGE_OK) {
        fprintf(stderr, "vtts error %d\n", vtts_bridge_last_vtts_error(b));
        vtts_bridge_destroy(b);
        return fail("synthesize", rc);
    }
    printf("chunks %d\n", vtts_bridge_last_chunk_count(b));
    failures += check_pcm("câu thử", pcm, n, sr, 0.5);
    if (pcm && write_wav(out_wav, pcm, n, sr) != 0) {
        fprintf(stderr, "FAIL ghi %s\n", out_wav);
        failures++;
    }

    /* 2. Không có gì để đọc */
    failures += expect_silent(b, "chuỗi rỗng", "");
    failures += expect_silent(b, "chỉ dấu câu", " ... !!! ,,, ");

    /* 3. Đoạn dài hơn ngưỡng chia của shim (bản dựng thử: 150 code point) ⇒ nhiều phần, mỗi phần một lượt front-end. */
    if (!run_long) goto cancel_test;
    sentence_len = strlen(text);
    long_cap = (sentence_len + 1) * 8 + 1;
    long_text = malloc(long_cap);
    if (!long_text) {
        vtts_bridge_destroy(b);
        return fail("malloc", 0);
    }
    while (copies < 8 && used + sentence_len + 2 <= long_cap) {
        const unsigned char *p;
        memcpy(long_text + used, text, sentence_len);
        used += sentence_len;
        long_text[used++] = ' ';
        copies++;
        for (p = (const unsigned char *)text; *p; p++) {
            if ((*p & 0xC0) != 0x80) code_points++;
        }
        code_points++;
    }
    long_text[used] = '\0';
    printf("đoạn dài: %d bản câu thử, %ld code point, %zu byte\n", copies, code_points, used);
    rc = vtts_bridge_synthesize(b, long_text, 1.0f, &long_pcm, &long_n);
    if (rc != VTTS_BRIDGE_OK) {
        failures += fail("synthesize đoạn dài", rc);
    } else {
        /* Mỗi bản là một câu riêng (kết bằng dấu chấm) và shim chỉ cắt ở ranh giới câu ⇒ cùng id, cùng số mẫu như câu
         * thử; giữa hai bản (kể cả giữa hai phần) 150 ms im lặng. Mất / lặp một câu thì lệch ≥ 12% — đòi lệch dưới 2%. */
        long gap = 150L * sr / 1000;
        double expected = (double)copies * (double)n + (double)(copies - 1) * (double)gap;
        double ratio = expected > 0 ? (double)long_n / expected : 0.0;
        printf("đoạn dài: %d chunk, %.1f s, %.3f lần mức mong đợi\n", vtts_bridge_last_chunk_count(b),
               (double)long_n / sr, ratio);
        failures += check_pcm("đoạn dài", long_pcm, long_n, sr, 1.0);
        if (ratio < 0.98 || ratio > 1.02) {
            fprintf(stderr, "FAIL đoạn dài: %ld mẫu, mong ≈ %.0f — mất / thừa chữ khi chia đoạn?\n", long_n, expected);
            failures++;
        }
    }
    vtts_bridge_free_pcm(long_pcm);
    free(long_text);

cancel_test:
    /* 4. Thẻ huỷ đã bật trước khi chạy ⇒ dừng ở chunk đầu, không trả tiếng. */
    cancel = vtts_bridge_cancel_create();
    if (!cancel) {
        failures += fail("cancel_create", 0);
    } else {
        float *c_pcm = NULL;
        long c_n = 0;
        vtts_bridge_cancel_request(cancel);
        rc = vtts_bridge_synthesize_cancellable(b, text, 1.0f, cancel, &c_pcm, &c_n);
        if (rc != VTTS_BRIDGE_ERR_CANCELLED || c_pcm != NULL || c_n != 0) {
            fprintf(stderr, "FAIL huỷ: rc %d (%s), %ld mẫu\n", rc, vtts_bridge_error_name(rc), c_n);
            failures++;
        } else {
            printf("huỷ: dừng đúng (cancelled)\n");
        }
        vtts_bridge_free_pcm(c_pcm);
        vtts_bridge_cancel_destroy(cancel);
    }

    vtts_bridge_free_pcm(pcm);
    vtts_bridge_destroy(b);
    if (failures) {
        fprintf(stderr, "%d kiểm tra hỏng\n", failures);
        return 1;
    }
    printf("OK\n");
    return 0;
}
