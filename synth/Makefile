# synth/Makefile  (M3)   usage from the repo root:
#   make -C synth                       base config (1 KB / 16 B), generic cells
#   make -C synth TARGET=xilinx         base config, Xilinx 7-series cells
#   make -C synth CACHE_BYTES=4096 BLOCK_BYTES=64 TARGET=ice40
#   make -C synth sweep                 all configs x all targets + summary tables
#   make -C synth fmax                  nextpnr-ice40 timing runs (needs nextpnr-ice40)
#   make -C synth clean                 remove full logs (synth/build)
# For the root Makefile (M4):   synth: ; $(MAKE) -C synth sweep
CACHE_BYTES   ?= 1024
BLOCK_BYTES   ?= 16
TARGET        ?= generic
WRITE_SUPPORT ?= 0

.PHONY: synth sweep fmax summary clean
synth:
	sh run_synth.sh $(CACHE_BYTES) $(BLOCK_BYTES) $(TARGET) $(WRITE_SUPPORT)
	python3 summarize.py

sweep:
	sh sweep.sh

# '-' : a config that does not fit the device is a result, not a build error
fmax:
	-sh run_fmax.sh 512  16 nobram
	-sh run_fmax.sh 1024 16 nobram
	sh run_fmax.sh 512  16 bram
	sh run_fmax.sh 1024 16 bram

summary:
	python3 summarize.py

clean:
	rm -rf build
