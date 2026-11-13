// Microbench `cblas_sgemm` (Accelerate) cho P0a của báo cáo tối ưu VieNeu Turbo: runner macOS có dùng AMX không.
//
// Vì sao cần: hướng chính của báo cáo là đưa phần chạy theo lô của Turbo (nạp prompt, codec) sang Accelerate. Nếu
// máy ảo CI không cho Accelerate chạm AMX thì số đo trên CI không nói được gì về hướng đó ⇒ phải đo trên máy.
// Ngưỡng: một luồng NEON fp32 của lõi M1 tối đa ~100 GFLOPS (4 ống FMA × 4 làn × 2 × 3,2 GHz). Một luồng mà
// vượt hẳn mức đó (> 300) thì chỉ có thể là AMX. iPhone 11 (A13) của anh Bửu đo được 380–388 GFLOPS (đợt Nano).
//
// Shape lấy từ graph thật: [M×K]·[K×N], M = số hàng (token / khung), row-major.
// Dùng: sgemm_bench   (đặt VECLIB_MAXIMUM_THREADS=1 để ép một luồng)
#include <Accelerate/Accelerate.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static double now_s(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

static double cpu_s(void) {
    struct timespec ts;
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

static void bench(const char *label, int m, int k, int n) {
    float *a = malloc(sizeof(float) * (size_t)m * k);
    float *b = malloc(sizeof(float) * (size_t)k * n);
    float *c = malloc(sizeof(float) * (size_t)m * n);
    if (!a || !b || !c) {
        printf("%s: thiếu bộ nhớ\n", label);
        exit(1);
    }
    for (size_t i = 0; i < (size_t)m * k; ++i) a[i] = (float)((i * 2654435761u) % 1000) / 1000.0f - 0.5f;
    for (size_t i = 0; i < (size_t)k * n; ++i) b[i] = (float)((i * 2246822519u) % 1000) / 1000.0f - 0.5f;
    // Hâm nóng: lượt đầu của Accelerate có chi phí dựng.
    for (int i = 0; i < 3; ++i) {
        cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans, m, n, k, 1.0f, a, k, b, n, 0.0f, c, n);
    }
    const double flop = 2.0 * m * k * n;
    int iters = (int)(4e10 / flop);  // ~40 GFLOP mỗi shape
    if (iters < 5) iters = 5;
    const double t0 = now_s();
    const double c0 = cpu_s();
    for (int i = 0; i < iters; ++i) {
        cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans, m, n, k, 1.0f, a, k, b, n, 0.0f, c, n);
    }
    const double wall = now_s() - t0;
    const double cpu = cpu_s() - c0;
    printf("%-28s [%4d×%4d]·[%4d×%4d]: %7.1f GFLOPS · %7.3f ms/lượt · CPU %7.3f ms/lượt (checksum %.3f)\n",
           label, m, k, k, n, flop * iters / wall / 1e9, wall / iters * 1e3, cpu / iters * 1e3, (double)c[(size_t)m * n / 2]);
    free(a);
    free(b);
    free(c);
}

int main(void) {
    const char *threads = getenv("VECLIB_MAXIMUM_THREADS");
    printf("VECLIB_MAXIMUM_THREADS=%s\n", threads ? threads : "(mặc định)");
    bench("Nano VE ff (mốc máy 388)", 128, 512, 1024);
    bench("Turbo prefill qkv/o", 186, 768, 768);
    bench("Turbo prefill MLP up", 186, 768, 3072);
    bench("Turbo prefill MLP down", 186, 3072, 768);
    bench("Codec 400 Hz ffn", 1600, 256, 1024);
    bench("Codec 400 Hz attn proj", 1600, 256, 768);
    return 0;
}
