SHELL := /usr/bin/env bash

# Paths are kept relative on purpose. The repository may be checked out
# under a directory whose name contains spaces or hyphens, and absolute
# paths in Make rule targets would be interpreted as multiple
# space-separated entries.
SERVER_BIN      := server/co-server
SERVER_ADDR     := 127.0.0.1:8080
SERVER_HOST     := http://$(SERVER_ADDR)
SERVER_PID_FILE := .server.pid
SERVER_LOG      := .server.log

BASELINE_LATENCY := 10ms
HICCUP_AT        := 30s
HICCUP_DURATION  := 1s

VENV            := .venv
PYTHON          := $(VENV)/bin/python
SYS_PYTHON      := python3

# Destination folder for `make publish-blog`. Read from the environment
# so the repository never carries a contributor's local layout. Set it
# in your shell, e.g. `export BLOG_IMG_DIR=/path/to/blog/img`, or pass
# it inline: `make publish-blog BLOG_IMG_DIR=/path/to/blog/img`. Quote
# the value if the path contains spaces.
BLOG_IMG_DIR    ?=

.PHONY: help setup mvp \
        scenario-01 scenario-02 scenario-03 scenario-04 scenario-05 \
        build-server run-server stop-server \
        build-images-01 build-images-02 build-images-03 build-images-04 build-images-05 \
        build-images publish-blog \
        clean check-tools

help:
	@echo "Targets:"
	@echo "  make check-tools          # report which load tools are installed"
	@echo "  make setup                # pip install Python deps for the analysis pipeline"
	@echo "  make mvp                  # run the canonical scenario end-to-end and render images"
	@echo "  make scenario-01          # control: 8 tools against a healthy server"
	@echo "  make scenario-02          # 8 tools against a server with a 1s hiccup at t=30s"
	@echo "  make scenario-03          # 8 tools against a server whose baseline ramps 10ms->100ms"
	@echo "  make scenario-04          # 8 tools against a server with recurring 200ms pauses"
	@echo "  make scenario-05          # 8 tools against a saturated server (capacity < target rate)"
	@echo "  make build-images-NN      # render images for the matching scenario (01-05)"
	@echo "  make publish-blog         # rsync images/ into the idle-ti.me content folder"
	@echo "  make clean                # remove binaries, results, server logs"

setup: $(VENV)/.installed

$(VENV)/.installed: analysis/requirements.txt
	@if [ ! -d "$(VENV)" ]; then $(SYS_PYTHON) -m venv $(VENV); fi
	$(PYTHON) -m pip install --upgrade pip >/dev/null
	$(PYTHON) -m pip install -r analysis/requirements.txt
	@touch $@

# Reports tool availability without failing the build, so a contributor can
# see what they need to install before running anything heavy.
check-tools:
	@echo "Checking tool availability..."
	@command -v go    >/dev/null && echo "  go    : $$(go version)"          || echo "  go    : MISSING (brew install go)"
	@command -v ab    >/dev/null && echo "  ab    : $$(ab -V | head -1)"      || echo "  ab    : MISSING (apt-get install apache2-utils)"
	@command -v wrk2     >/dev/null && echo "  wrk2  : present"                                || echo "  wrk2  : MISSING (no brew formula on Apple Silicon — see README)"
	@(command -v vegeta >/dev/null || [ -x "$$HOME/go/bin/vegeta" ]) && echo "  vegeta: present" || echo "  vegeta: MISSING (go install github.com/tsenart/vegeta/v12@latest)"
	@command -v k6       >/dev/null && echo "  k6    : $$(k6 version | head -1)"               || echo "  k6    : MISSING (brew install k6)"
	@command -v jmeter   >/dev/null && echo "  jmeter: present"                                || echo "  jmeter: MISSING (brew install jmeter)"
	@command -v wrk      >/dev/null && echo "  wrk   : present"                                || echo "  wrk   : MISSING (brew install wrk)"
	@command -v hey      >/dev/null && echo "  hey   : present"                                || echo "  hey   : MISSING (brew install hey)"
	@command -v $(SYS_PYTHON) >/dev/null && echo "  python: $$($(SYS_PYTHON) --version)" || echo "  python: MISSING"

build-server: $(SERVER_BIN)

$(SERVER_BIN): server/main.go server/go.mod
	cd server && go build -o co-server .

# Starts the server in the background with the canonical hiccup scheduled.
# Subsequent runs reuse the binary if it is up to date.
run-server: build-server
	@if [ -f $(SERVER_PID_FILE) ] && kill -0 $$(cat $(SERVER_PID_FILE)) 2>/dev/null; then \
	  echo "server already running, pid $$(cat $(SERVER_PID_FILE))"; \
	else \
	  $(SERVER_BIN) -addr $(SERVER_ADDR) -baseline-latency $(BASELINE_LATENCY) \
	                -hiccup-at $(HICCUP_AT) -hiccup-duration $(HICCUP_DURATION) \
	                > $(SERVER_LOG) 2>&1 & echo $$! > $(SERVER_PID_FILE); \
	  sleep 0.5; \
	  echo "server started, pid $$(cat $(SERVER_PID_FILE)), log $(SERVER_LOG)"; \
	fi

stop-server:
	@if [ -f $(SERVER_PID_FILE) ]; then \
	  pid=$$(cat $(SERVER_PID_FILE)); \
	  if kill -0 $$pid 2>/dev/null; then kill $$pid && echo "server stopped (pid $$pid)"; fi; \
	  rm -f $(SERVER_PID_FILE); \
	fi

# Each runner gets a fresh server so that the pathology under test is
# replayed from t=0 with a clean state. We start, run, stop in sequence —
# separate targets keep make output legible.
#
# Each scenario passes its own SERVER_FLAGS via the umbrella target. The
# umbrella target enumerates the eight load tools and chains them.

EIGHT_TOOLS := ab wrk hey vegeta k6-bad k6-good jmeter-bad jmeter-good

define run_eight_tools
$(MAKE) -s _run-ab          SCENARIO=$(1) SERVER_FLAGS='$(2)' && \
$(MAKE) -s _run-wrk         SCENARIO=$(1) SERVER_FLAGS='$(2)' && \
$(MAKE) -s _run-hey         SCENARIO=$(1) SERVER_FLAGS='$(2)' && \
$(MAKE) -s _run-vegeta      SCENARIO=$(1) SERVER_FLAGS='$(2)' && \
$(MAKE) -s _run-k6-bad      SCENARIO=$(1) SERVER_FLAGS='$(2)' && \
$(MAKE) -s _run-k6-good     SCENARIO=$(1) SERVER_FLAGS='$(2)' && \
$(MAKE) -s _run-jmeter-bad  SCENARIO=$(1) SERVER_FLAGS='$(2)' && \
$(MAKE) -s _run-jmeter-good SCENARIO=$(1) SERVER_FLAGS='$(2)'
endef

scenario-01: build-server
	@$(call run_eight_tools,01-healthy,)

scenario-02: build-server
	@$(call run_eight_tools,02-single-hiccup,-hiccup-at $(HICCUP_AT) -hiccup-duration $(HICCUP_DURATION))

scenario-03: build-server
	@$(call run_eight_tools,03-sustained-slowdown,-ramp-start 20s -ramp-end 50s -ramp-to 100ms)

scenario-04: build-server
	@$(call run_eight_tools,04-gc-pauses,-gc-pause-every 10s -gc-pause-duration 200ms)

scenario-05: build-server
	@$(call run_eight_tools,05-saturation,-max-concurrency 500)

scenario-02-ab: build-server
	@$(MAKE) -s _run-ab SCENARIO=02-single-hiccup SERVER_FLAGS='-hiccup-at $(HICCUP_AT) -hiccup-duration $(HICCUP_DURATION)'

scenario-02-wrk2: build-server
	@$(MAKE) -s _run-wrk2 SCENARIO=02-single-hiccup SERVER_FLAGS='-hiccup-at $(HICCUP_AT) -hiccup-duration $(HICCUP_DURATION)'

# ---- internal recipes (one server lifecycle per runner) ---------------------
# These accept SCENARIO, SERVER_HICCUP_AT, SERVER_HICCUP_DURATION as variables.
# Not meant to be called directly from the command line.

.PHONY: _run-ab _run-vegeta _run-wrk2 _run-wrk _run-hey \
        _run-k6-bad _run-k6-good _run-jmeter-bad _run-jmeter-good \
        _start-server _stop-server-internal

_run-ab: _start-server
	@HOST=$(SERVER_HOST) bash load-tools/ab/run.sh $(SCENARIO)
	@$(MAKE) -s _stop-server-internal

_run-vegeta: _start-server
	@HOST=$(SERVER_HOST) bash load-tools/vegeta/run.sh $(SCENARIO)
	@$(MAKE) -s _stop-server-internal

_run-wrk2: _start-server
	@HOST=$(SERVER_HOST) bash load-tools/wrk2/run.sh $(SCENARIO)
	@$(MAKE) -s _stop-server-internal

_run-wrk: _start-server
	@HOST=$(SERVER_HOST) bash load-tools/wrk/run.sh $(SCENARIO)
	@$(MAKE) -s _stop-server-internal

_run-hey: _start-server
	@HOST=$(SERVER_HOST) bash load-tools/hey/run.sh $(SCENARIO)
	@$(MAKE) -s _stop-server-internal

_run-k6-bad: _start-server
	@HOST=$(SERVER_HOST) bash load-tools/k6-bad/run.sh $(SCENARIO)
	@$(MAKE) -s _stop-server-internal

_run-k6-good: _start-server
	@HOST=$(SERVER_HOST) bash load-tools/k6-good/run.sh $(SCENARIO)
	@$(MAKE) -s _stop-server-internal

_run-jmeter-bad: _start-server
	@HOST=$(SERVER_HOST) bash load-tools/jmeter-bad/run.sh $(SCENARIO)
	@$(MAKE) -s _stop-server-internal

_run-jmeter-good: _start-server
	@HOST=$(SERVER_HOST) bash load-tools/jmeter-good/run.sh $(SCENARIO)
	@$(MAKE) -s _stop-server-internal

_start-server:
	@$(MAKE) -s _stop-server-internal
	@$(SERVER_BIN) -addr $(SERVER_ADDR) -baseline-latency $(BASELINE_LATENCY) $(SERVER_FLAGS) \
	               > $(SERVER_LOG).$(SCENARIO) 2>&1 & echo $$! > $(SERVER_PID_FILE)
	@sleep 0.5

_stop-server-internal:
	@if [ -f $(SERVER_PID_FILE) ]; then \
	  pid=$$(cat $(SERVER_PID_FILE)); \
	  if kill -0 $$pid 2>/dev/null; then kill $$pid; fi; \
	  rm -f $(SERVER_PID_FILE); \
	fi

build-images-01: setup
	@$(PYTHON) analysis/generate_images.py --scenario 01-healthy --mode auto

build-images-02: setup
	@$(PYTHON) analysis/generate_images.py --scenario 02-single-hiccup --mode auto

build-images-03: setup
	@$(PYTHON) analysis/generate_images.py --scenario 03-sustained-slowdown --mode auto

build-images-04: setup
	@$(PYTHON) analysis/generate_images.py --scenario 04-gc-pauses --mode auto

build-images-05: setup
	@$(PYTHON) analysis/generate_images.py --scenario 05-saturation --mode auto

build-images: build-images-01 build-images-02 build-images-03 build-images-04 build-images-05

# Default target for "everything in one shot". The leading dash on the
# scenario line tells make to keep going if Go or wrk2 are missing —
# build-images-02 then falls back to synthetic data so a contributor
# always gets a rendered comparison plot.
mvp:
	-@$(MAKE) scenario-02
	@$(MAKE) build-images-02

publish-blog:
	@if [ -z "$(BLOG_IMG_DIR)" ]; then \
	  echo "BLOG_IMG_DIR is not set." >&2; \
	  echo "  export BLOG_IMG_DIR=/path/to/blog/img   # one-time" >&2; \
	  echo "  make publish-blog                       # then this" >&2; \
	  echo "or pass it inline: make publish-blog BLOG_IMG_DIR=/path/to/blog/img" >&2; \
	  exit 1; \
	fi
	@if [ ! -d "$(BLOG_IMG_DIR)" ]; then \
	  echo "blog image dir does not exist: $(BLOG_IMG_DIR)" >&2; exit 1; \
	fi
	rsync -av --delete images/ "$(BLOG_IMG_DIR)/"

clean: stop-server
	rm -f $(SERVER_BIN) $(SERVER_LOG) $(SERVER_LOG).* jmeter.log
	rm -rf results/*/ab results/*/wrk results/*/wrk2 results/*/hey \
	       results/*/vegeta results/*/k6-bad results/*/k6-good \
	       results/*/jmeter-bad results/*/jmeter-good

# Removes the virtualenv too. Kept separate so `make clean` does not force
# a re-install on every iteration.
distclean: clean
	rm -rf $(VENV)
