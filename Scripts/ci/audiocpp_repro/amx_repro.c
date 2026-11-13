// Tái hiện lỗi 1.3.924: bật codec qua Accelerate (`vieneu_v3_turbo.codec_blas`) làm app chết trên iPhone ở lượt
// tổng hợp đầu tiên, còn CLI trên CI thì không. Chương trình này gọi C API **y như app** (`VieNeuTurboRuntime`):
// registry → model → session CPU 2 luồng (+ option) → `audiocpp_session_run` với `reference_codes_file` +
// `speaker_embedding_file`, lấy mẫu mặc định (như trình đọc), audio.cpp tự cắt đoạn ở 200 byte như app.
// Khác CLI ở chỗ chạy được trên:
//   main      luồng chính (stack 8 MB, như CLI)
//   gcd       hàng đợi GCD QoS userInitiated (luồng worker stack 512 KB — đúng như app trên iPhone)
//   pthread   pthread tự tạo, stack 512 KB
// Dùng: amx_repro <model.gguf> <ref_codes.txt> <speaker.emb.txt> <main|gcd|pthread> <0|1 codec_blas> <abort_file>
//                 <text>...   (mỗi text một lượt, theo thứ tự)
#include "audiocpp.h"

#include <dispatch/dispatch.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct {
    audiocpp_session * session;
    const char * codes;
    const char * emb;
    const char * text;
    int index;
    int ok;
} job_t;

static double now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1e3 + (double)ts.tv_nsec * 1e-6;
}

static void run_job(job_t * job) {
    printf("[%d] bắt đầu (%zu byte phiên âm)\n", job->index, strlen(job->text));
    fflush(stdout);
    audiocpp_request * request = audiocpp_request_create();
    audiocpp_request_set_text(request, job->text, NULL);
    audiocpp_request_set_option(request, "reference_codes_file", job->codes);
    audiocpp_request_set_option(request, "speaker_embedding_file", job->emb);
    audiocpp_request_set_option(request, "seed", "7");
    audiocpp_result * result = NULL;
    const double started = now_ms();
    const audiocpp_status status = audiocpp_session_run(job->session, request, &result);
    const double elapsed = now_ms() - started;
    if (status != AUDIOCPP_OK) {
        printf("[%d] LỖI %s — %s\n", job->index, audiocpp_status_string(status), audiocpp_last_error());
        job->ok = 0;
    } else {
        const float * samples = NULL;
        size_t frames = 0;
        int rate = 0;
        int channels = 0;
        audiocpp_result_audio(result, &samples, &frames, &rate, &channels);
        printf("[%d] xong %.0f ms · %.2f s tiếng\n", job->index, elapsed, rate > 0 ? (double)frames / rate : 0.0);
        job->ok = 1;
    }
    fflush(stdout);
    audiocpp_result_free(result);
    audiocpp_request_free(request);
}

static void * pthread_entry(void * arg) {
    run_job((job_t *)arg);
    return NULL;
}

static int check(audiocpp_status status, const char * what) {
    if (status != AUDIOCPP_OK) {
        printf("%s lỗi: %s — %s\n", what, audiocpp_status_string(status), audiocpp_last_error());
        return 0;
    }
    return 1;
}

int main(int argc, char ** argv) {
    if (argc < 8) {
        fprintf(stderr, "dùng: %s model codes emb main|gcd|pthread 0|1 abort_file text...\n", argv[0]);
        return 2;
    }
    const char * mode = argv[4];
    const int codec_blas = atoi(argv[5]);
    if (!check(audiocpp_set_abort_file(argv[6]), "audiocpp_set_abort_file")) return 1;

    audiocpp_registry * registry = NULL;
    if (!check(audiocpp_registry_create(NULL, &registry), "registry")) return 1;
    audiocpp_model_config config = {"vieneu_v3_turbo", NULL, NULL, NULL};
    audiocpp_model * model = NULL;
    if (!check(audiocpp_model_load(registry, argv[1], &config, NULL, &model), "model_load")) return 1;
    audiocpp_options * options = NULL;
    if (codec_blas) {
        options = audiocpp_options_create();
        audiocpp_options_set(options, "vieneu_v3_turbo.codec_blas", "true");
    }
    audiocpp_backend_config backend = {"cpu", 0, 2};
    audiocpp_session * session = NULL;
    if (!check(audiocpp_session_create(model, "tts", "offline", &backend, options, &session), "session_create")) return 1;
    audiocpp_options_free(options);
    printf("session: chế độ %s, codec_blas=%d\n", mode, codec_blas);
    fflush(stdout);

    int failures = 0;
    for (int i = 7; i < argc; ++i) {
        job_t job = {session, argv[2], argv[3], argv[i], i - 6, 0};
        if (strcmp(mode, "main") == 0) {
            run_job(&job);
        } else if (strcmp(mode, "gcd") == 0) {
            // Block chép biến cục bộ theo giá trị ⇒ chuyển con trỏ để `job.ok` về đúng bản gốc.
            job_t * job_ptr = &job;
            dispatch_semaphore_t done = dispatch_semaphore_create(0);
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                run_job(job_ptr);
                dispatch_semaphore_signal(done);
            });
            dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
        } else {
            pthread_attr_t attr;
            pthread_attr_init(&attr);
            pthread_attr_setstacksize(&attr, 512 * 1024);
            pthread_t thread;
            pthread_create(&thread, &attr, pthread_entry, &job);
            pthread_join(thread, NULL);
            pthread_attr_destroy(&attr);
        }
        failures += job.ok ? 0 : 1;
    }
    audiocpp_session_free(session);
    audiocpp_model_free(model);
    audiocpp_registry_free(registry);
    printf("xong hết, %d lượt lỗi\n", failures);
    return failures == 0 ? 0 : 1;
}
