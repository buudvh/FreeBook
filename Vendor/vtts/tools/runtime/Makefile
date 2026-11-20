CC ?= cc
# -ffp-contract=off: no fused multiply-add, so the streaming and whole-utterance paths (which sum in
# the same order but are written as different expressions) give bit-identical results
CFLAGS ?= -std=c99 -O2 -ffp-contract=off -Wall -Wextra -Werror -Iinclude
SAN = -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g
SRC = src/vtts_model.c src/vtts_synth.c src/vtts_kernels_ref.c

build/golden_test: $(SRC) test/golden_test.c include/vtts.h include/vtts_port.h
	mkdir -p build
	$(CC) $(CFLAGS) $(SAN) $(SRC) test/golden_test.c -lm -o $@

build/libvtts.a: $(SRC) include/vtts.h
	mkdir -p build
	$(CC) $(CFLAGS) -c src/vtts_model.c -o build/vtts_model.o
	$(CC) $(CFLAGS) -c src/vtts_synth.c -o build/vtts_synth.o
	ar rcs $@ build/vtts_model.o build/vtts_synth.o

clean:
	rm -rf build
.PHONY: clean

build/vtts_cli: $(SRC) tools/vtts_cli.c include/vtts.h
	mkdir -p build
	$(CC) $(CFLAGS) -O3 $(SRC) tools/vtts_cli.c -lm -o $@

build/stream_test: $(SRC) test/stream_test.c include/vtts.h
	mkdir -p build
	$(CC) $(CFLAGS) $(SAN) $(SRC) test/stream_test.c -lm -o $@

TEXT_SRC = src/vtts_text.c src/vtts_text_en.c src/vtts_text_zh.c src/vtts_text_ko.c src/vtts_text_hi.c src/vtts_text_ja.c \
           src/vtts_text_lt.c src/vtts_text_th.c src/vtts_lex.c
TEXT_SRC += src/vtts_text_fr.c src/vtts_text_de.c src/vtts_text_it.c src/vtts_text_tr.c src/vtts_re.c src/vtts_text_ru.c \
            src/vtts_text_pl.c src/vtts_text_ar.c src/vtts_text_fi.c src/vtts_text_el.c \
            src/vtts_text_tl.c src/vtts_text_sw.c src/vtts_text_nx.c src/vtts_text_nx_nl.c src/vtts_text_nx_sc.c
TEXT_HDR = include/vtts_text.h include/vtts_langs.h include/vtts_lex.h include/vtts_zlex.h include/vtts_jlex.h src/vtts_text_en.h src/vtts_text_zh.h \
           src/vtts_text_ko.h src/vtts_text_hi.h src/vtts_text_ja.h src/vtts_text_lt.h src/vtts_text_th.h \
           src/vtts_text_tables.h src/vtts_text_th_tables.h
TEXT_HDR += src/vtts_text_fr.h src/vtts_text_fr_tables.h src/vtts_text_de.h src/vtts_text_de_tables.h \
            src/vtts_text_ltx.h src/vtts_text_it.h src/vtts_text_tr.h src/vtts_text_it_tables.h src/vtts_text_tr_tables.h \
            src/vtts_re.h src/vtts_text_ru.h src/vtts_text_ru_tables.h include/vtts_rlex.h src/vtts_text_pl.h \
            src/vtts_text_pl_tables.h src/vtts_text_ar.h src/vtts_text_ar_tables.h \
            src/vtts_text_fi.h src/vtts_text_fi_tables.h src/vtts_text_el.h src/vtts_text_el_tables.h \
            src/vtts_text_ms_tables.h src/vtts_text_tl.h src/vtts_text_tl_tables.h src/vtts_text_sw.h src/vtts_text_sw_tables.h \
            src/vtts_text_nx.h src/vtts_text_nx_int.h src/vtts_text_nx_tables.h
TEXT_SRC += src/vtts_text_lo.c
TEXT_HDR += src/vtts_text_lo.h src/vtts_text_lo_tables.h
TEXT_SRC += src/vtts_text_da.c
TEXT_HDR += src/vtts_text_da.h src/vtts_text_da_tables.h
TEXT_SRC += src/vtts_text_nsp.c src/vtts_text_km.c src/vtts_text_my.c
TEXT_HDR += src/vtts_text_sent_tables.h
TEXT_HDR += src/vtts_text_nsp.h src/vtts_text_km.h src/vtts_text_km_tables.h src/vtts_text_my.h src/vtts_text_my_tables.h
build/text_test: $(TEXT_SRC) test/text_test.c $(TEXT_HDR)
	mkdir -p build
	$(CC) $(CFLAGS) $(SAN) -Isrc $(TEXT_SRC) test/text_test.c -o $@

build/lex_test: $(TEXT_SRC) test/lex_test.c $(TEXT_HDR)
	mkdir -p build
	$(CC) $(CFLAGS) $(SAN) -Isrc $(TEXT_SRC) test/lex_test.c -o $@

build/en_norm_test: $(TEXT_SRC) test/en_norm_test.c $(TEXT_HDR)
	mkdir -p build
	$(CC) $(CFLAGS) $(SAN) -Isrc $(TEXT_SRC) test/en_norm_test.c -o $@

build/token_set_test: $(SRC) $(TEXT_SRC) test/token_set_test.c include/vtts.h $(TEXT_HDR)
	mkdir -p build
	$(CC) $(CFLAGS) $(SAN) -Isrc $(SRC) $(TEXT_SRC) test/token_set_test.c -lm -o $@

# Host synthesizer from text: front-end chosen by the model's token set (like the firmware)
build/vtts_say: $(SRC) $(TEXT_SRC) tools/vtts_say.c include/vtts.h $(TEXT_HDR)
	mkdir -p build
	$(CC) $(CFLAGS) $(SAN) -Isrc $(SRC) $(TEXT_SRC) tools/vtts_say.c -lm -o $@

# Blobs of the device front-end, built from the Python tables (needs uv at the repository root).
build/lex_en.bin: ../src/vtts/frontend/en/vlex.py ../scripts/frontend/build_lexicon.py
	mkdir -p build
	cd .. && uv run python scripts/frontend/build_lexicon.py --out runtime/$@

build/zh_lex.bin: ../src/vtts/frontend/lexicons/zh/chars.tsv ../src/vtts/frontend/lexicons/zh/phrases.tsv ../scripts/frontend/build_zh_blob.py
	mkdir -p build
	cd .. && uv run python scripts/frontend/build_zh_blob.py --out runtime/$@

build/ru_lex.bin: ../src/vtts/frontend/lexicons/ru/overrides.tsv ../src/vtts/frontend/lexicons/ru/stress.tsv \
                  ../src/vtts/frontend/lexicons/ru/stress_suffixes.tsv ../scripts/frontend/build_ru_blob.py
	mkdir -p build
	cd .. && uv run python scripts/frontend/build_ru_blob.py --out runtime/$@

build/ja_lex.bin: ../src/vtts/frontend/lexicons/ja/words.tsv ../src/vtts/frontend/lexicons/ja/after_kanji.tsv \
                  ../src/vtts/frontend/lexicons/ja/after_katakana.tsv ../src/vtts/frontend/lexicons/ja/kanji.tsv \
                  ../scripts/frontend/build_ja_blob.py
	mkdir -p build
	cd .. && uv run python scripts/frontend/build_ja_blob.py --out runtime/$@

# Mandarin (VTTS_LANG_ZH) parity with text_to_ids(text, "zh") and the fuzz run in every mode.
zh_test: build/text_test build/lex_en.bin build/zh_lex.bin
	./build/text_test --lex build/lex_en.bin --zh build/zh_lex.bin test/text_parity_zh.tsv
	./build/text_test --fuzz --lex build/lex_en.bin --zh build/zh_lex.bin

# Korean (VTTS_LANG_KO) parity with text_to_ids(text, "ko"); tables are compiled in (no blob).
ko_test: build/text_test build/lex_en.bin
	./build/text_test --lex build/lex_en.bin test/text_parity_ko.tsv

# Hindi (VTTS_LANG_HI) parity with text_to_ids(text, "hi") and the fuzz run (hi among the modes);
# tables are compiled in (no blob).
hi_test: build/text_test build/lex_en.bin
	./build/text_test --lex build/lex_en.bin test/text_parity_hi.tsv
	./build/text_test --fuzz --lex build/lex_en.bin

# Japanese (VTTS_LANG_JA) parity with text_to_ids(text, "ja"), NFKC against unicodedata, the fuzz run
# and the reading lookup benchmark.
ja_test: build/text_test build/lex_en.bin build/ja_lex.bin
	./build/text_test --lex build/lex_en.bin --ja build/ja_lex.bin --nfkc test/ja_nfkc.tsv
	./build/text_test --lex build/lex_en.bin --ja build/ja_lex.bin test/text_parity_ja.tsv
	./build/text_test --fuzz --lex build/lex_en.bin --ja build/ja_lex.bin

# Reading lookups and ja-mode throughput on the host (optimized, no sanitizers).
build/text_bench: $(TEXT_SRC) test/text_test.c $(TEXT_HDR)
	mkdir -p build
	$(CC) $(CFLAGS) -Isrc $(TEXT_SRC) test/text_test.c -o $@

ja_bench: build/text_bench build/lex_en.bin build/ja_lex.bin
	./build/text_bench --lex build/lex_en.bin --ja build/ja_lex.bin --bench ../src/vtts/frontend/lexicons/ja/words.tsv

# Spanish, Indonesian, Portuguese (VTTS_LANG_ES|ID|PT) parity with text_to_ids(text, "es"|"id"|"pt")
# and the fuzz run of the three modes; tables are compiled in (no blob).
lt_test: build/text_test build/lex_en.bin
	./build/text_test --lex build/lex_en.bin test/text_parity_es.tsv
	./build/text_test --lex build/lex_en.bin test/text_parity_id.tsv
	./build/text_test --lex build/lex_en.bin test/text_parity_pt.tsv
	./build/text_test --fuzz-lt --lex build/lex_en.bin

# Italian and Turkish (VTTS_LANG_IT|TR) parity with text_to_ids(text, "it"|"tr") and the fuzz run of both
# modes; tables are compiled in (no blob); each language builds only with VTTS_ENABLE_IT / VTTS_ENABLE_TR
# (1 by default).
it_tr_test: build/text_test build/lex_en.bin
	./build/text_test --lex build/lex_en.bin test/text_parity_it.tsv
	./build/text_test --lex build/lex_en.bin test/text_parity_tr.tsv
	./build/text_test --fuzz-it-tr --lex build/lex_en.bin

# All text front-end tests (no model needed); the model golden tests run from pytest.
test: build/token_set_test build/text_test build/lex_test build/en_norm_test build/lex_en.bin build/zh_lex.bin build/ja_lex.bin \
      build/ru_lex.bin
	./build/token_set_test
	./build/text_test test/text_parity.tsv
	./build/text_test --lex build/lex_en.bin test/text_parity_v2.tsv
	./build/lex_test build/lex_en.bin test/lex_expect.tsv
	./build/en_norm_test test/en_norm.tsv
	$(MAKE) zh_test
	$(MAKE) ko_test
	$(MAKE) hi_test
	$(MAKE) ja_test
	$(MAKE) lt_test
	$(MAKE) th_test
	$(MAKE) fr_test
	$(MAKE) de_test
	$(MAKE) it_tr_test
	$(MAKE) ru_test
	$(MAKE) pl_test
	$(MAKE) ar_test
	$(MAKE) fi_test
	$(MAKE) el_test
	$(MAKE) ms_test
	$(MAKE) tl_test
	$(MAKE) sw_test
	$(MAKE) nx_test
	$(MAKE) da_test
	$(MAKE) lo_test
	$(MAKE) km_test
	$(MAKE) my_test
	$(MAKE) langs_test
.PHONY: zh_test ko_test hi_test ja_test ja_bench lt_test th_test it_tr_test ru_test pl_test ar_test fi_test el_test test

# Thai (VTTS_LANG_TH) parity with text_to_ids(text, "th"); tables are compiled in (no blob).
th_test: build/text_test build/lex_en.bin
	./build/text_test --lex build/lex_en.bin test/text_parity_th.tsv
	./build/text_test --fuzz-th --lex build/lex_en.bin

# French (VTTS_LANG_FR, built with VTTS_ENABLE_FR=1, the default) parity with text_to_ids(text, "fr")
# and the fuzz run in fr mode; tables are compiled in (no blob).
fr_test: build/text_test build/lex_en.bin
	./build/text_test --lex build/lex_en.bin test/text_parity_fr.tsv
	./build/text_test --fuzz-fr --lex build/lex_en.bin
.PHONY: fr_test

# German (VTTS_LANG_DE, VTTS_ENABLE_DE) parity with text_to_ids(text, "de") (its own sentence split:
# ordinals and abbreviations keep their dot) and the fuzz run; tables are compiled in (no blob).
de_test: build/text_test build/lex_en.bin
	./build/text_test --lex build/lex_en.bin test/text_parity_de.tsv
	./build/text_test --fuzz-de --lex build/lex_en.bin
.PHONY: de_test

# Per-language build switches (include/vtts_langs.h): the front-end built with every optional language
# off, then with each one alone; langs_test checks the modes offered and that the others are refused.
OPT_LANGS = ZH KO JA HI TH ES ID PT FR DE IT TR RU PL AR FI EL MS TL SW NL SV NO DA LO KM MY
NO_LANGS = $(foreach L,$(OPT_LANGS),-DVTTS_ENABLE_$(L)=0)
langs_test: $(SRC) $(TEXT_SRC) test/langs_test.c include/vtts.h $(TEXT_HDR) build/lex_en.bin
	mkdir -p build
	$(CC) $(CFLAGS) $(SAN) $(NO_LANGS) -Isrc $(SRC) $(TEXT_SRC) test/langs_test.c -lm -o build/langs_test_none
	./build/langs_test_none build/lex_en.bin
	for L in $(OPT_LANGS); do \
	    D=$$(for M in $(OPT_LANGS); do if [ $$M = $$L ]; then echo -DVTTS_ENABLE_$$M=1; else echo -DVTTS_ENABLE_$$M=0; fi; done); \
	    $(CC) $(CFLAGS) $$D -Isrc $(SRC) $(TEXT_SRC) test/langs_test.c -lm -o build/langs_test_one \
	    && ./build/langs_test_one build/lex_en.bin || exit 1; \
	done
	$(CC) $(CFLAGS) $(SAN) -Isrc $(SRC) $(TEXT_SRC) test/langs_test.c -lm -o build/langs_test_all
	./build/langs_test_all build/lex_en.bin
.PHONY: langs_test
# Russian (VTTS_LANG_RU) parity with text_to_ids(text, "ru") and the ru fuzz run; the stress tables are
# the RLEX blob (build/ru_lex.bin), the rest is compiled in (VTTS_ENABLE_RU, default 1).
ru_test: build/text_test build/lex_en.bin build/ru_lex.bin
	./build/text_test --lex build/lex_en.bin --ru build/ru_lex.bin test/text_parity_ru.tsv
	./build/text_test --fuzz-ru --lex build/lex_en.bin --ru build/ru_lex.bin
	./build/text_test --fuzz-ru --lex build/lex_en.bin

# Polish (VTTS_LANG_PL) parity with text_to_ids(text, "pl") and the pl fuzz run; tables and the
# normalizer's patterns are compiled in (VTTS_ENABLE_PL, default 1), no blob.
pl_test: build/text_test build/lex_en.bin
	./build/text_test --lex build/lex_en.bin test/text_parity_pl.tsv
	./build/text_test --fuzz-pl --lex build/lex_en.bin
.PHONY: ru_test pl_test ar_test

# Arabic (VTTS_LANG_AR, VTTS_ENABLE_AR) parity with text_to_ids(text, "ar") and the fuzz run of the ar
# mode; tables are compiled in (no blob).
ar_test: build/text_test build/lex_en.bin
	./build/text_test --lex build/lex_en.bin test/text_parity_ar.tsv
	./build/text_test --fuzz-ar --lex build/lex_en.bin
# Finnish (VTTS_LANG_FI) parity with text_to_ids(text, "fi"); tables are compiled in (no blob).
fi_test: build/text_test build/lex_en.bin
	./build/text_test --lex build/lex_en.bin test/text_parity_fi.tsv
	./build/text_test --fuzz-fi --lex build/lex_en.bin

# Greek (VTTS_LANG_EL) parity with text_to_ids(text, "el"); tables are compiled in (no blob).
el_test: build/text_test build/lex_en.bin
	./build/text_test --lex build/lex_en.bin test/text_parity_el.tsv
	./build/text_test --fuzz-el --lex build/lex_en.bin

# Malay (VTTS_LANG_MS, built with VTTS_ENABLE_MS, the default) parity with text_to_ids(text, "ms") and the
# fuzz run of the mode; tables are compiled in (vtts_text_ms_tables.h, no blob).
ms_test: build/text_test build/lex_en.bin
	./build/text_test --lex build/lex_en.bin test/text_parity_ms.tsv
	./build/text_test --fuzz-ms --lex build/lex_en.bin

# Tagalog (VTTS_LANG_TL, built with VTTS_ENABLE_TL=1, the default) parity with text_to_ids(text, "tl")
# and the fuzz run; tables are compiled in (no blob).
tl_test: build/text_test build/lex_en.bin
	./build/text_test --lex build/lex_en.bin test/text_parity_tl.tsv
	./build/text_test --fuzz-tl --lex build/lex_en.bin
.PHONY: tl_test

# Swahili (VTTS_LANG_SW, built with VTTS_ENABLE_SW=1, the default) parity with text_to_ids(text, "sw")
# and the fuzz run; tables are compiled in (no blob). (langs_test covers the builds without it.)
sw_test: build/text_test build/lex_en.bin
	./build/text_test --lex build/lex_en.bin test/text_parity_sw.tsv
	./build/text_test --fuzz-sw --lex build/lex_en.bin
.PHONY: sw_test
# Dutch, Swedish, Norwegian (VTTS_LANG_NL, _SV, _NO) parity with text_to_ids(text, "nl" | "sv" | "no");
# tables are compiled in (no blob). Each language is built only with VTTS_ENABLE_NL / _SV / _NO (default 1
# on the host).
nx_test: build/text_test build/lex_en.bin
	./build/text_test --lex build/lex_en.bin test/text_parity_nl.tsv
	./build/text_test --lex build/lex_en.bin test/text_parity_sv.tsv
	./build/text_test --lex build/lex_en.bin test/text_parity_no.tsv
	./build/text_test --fuzz-nx --lex build/lex_en.bin
.PHONY: nx_test

# Lao (VTTS_LANG_LO, VTTS_ENABLE_LO) parity with text_to_ids(text, "lo") and
# the fuzz run; tables are compiled in (no blob).
lo_test: build/text_test build/lex_en.bin
	./build/text_test --lex build/lex_en.bin test/text_parity_lo.tsv
	./build/text_test --fuzz-lo --lex build/lex_en.bin
.PHONY: lo_test

# Danish (VTTS_LANG_DA, VTTS_ENABLE_DA) parity with text_to_ids(text, "da") and
# the fuzz run; tables (with the NST readings) are compiled in (no blob).
da_test: build/text_test build/lex_en.bin
	./build/text_test --lex build/lex_en.bin test/text_parity_da.tsv
	./build/text_test --fuzz-da --lex build/lex_en.bin
.PHONY: da_test

# Khmer (VTTS_LANG_KM, VTTS_ENABLE_KM) parity with text_to_ids(text, "km"); tables are compiled in (no blob).
km_test: build/text_test build/lex_en.bin
	./build/text_test --lex build/lex_en.bin test/text_parity_km.tsv
	./build/text_test --fuzz-km --lex build/lex_en.bin
.PHONY: km_test

# Burmese (VTTS_LANG_MY, VTTS_ENABLE_MY) parity with text_to_ids(text, "my"); tables are compiled in (no blob).
my_test: build/text_test build/lex_en.bin
	./build/text_test --lex build/lex_en.bin test/text_parity_my.tsv
	./build/text_test --fuzz-my --lex build/lex_en.bin
.PHONY: my_test

# Firmware path (streaming, chunk schedule, gaps) against the host render of whole texts, sample by
# sample as int16. usage: make say_parity MODEL=path/to/model.vtts [PARITY_ARGS="--first 12 --chunk 128"]
build/say_parity: $(SRC) $(TEXT_SRC) test/say_parity.c include/vtts.h $(TEXT_HDR)
	mkdir -p build
	$(CC) $(CFLAGS) -O3 -Isrc $(SRC) $(TEXT_SRC) test/say_parity.c -lm -o $@

say_parity: build/say_parity build/lex_en.bin
	./build/say_parity $(MODEL) build/lex_en.bin test/say_parity.txt $(PARITY_ARGS)
.PHONY: say_parity
