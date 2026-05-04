SHELL := /usr/bin/env bash

# Paths are kept relative on purpose. The repository may be checked out
# under a directory whose name contains spaces or hyphens (e.g. Dropbox
# folders such as "16 - dev"), and absolute paths in Make rule targets
# would be interpreted as multiple space-separated entries.
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

# The blog image dir contains spaces; we never expand it inside a target
# or prerequisite list — only inside shell command bodies, where it is quoted.
BLOG_IMG_DIR    := /Users/jerome/Share/Dropbox/16 - dev/11 - idle-time web site/idle-ti.me/content/blog/coordinated-omission/img

.PHONY: help setup mvp \
        scenario-01 scenario-01-ab scenario-01-vegeta \
        scenario-01-k6-bad scenario-01-k6-good \
        scenario-01-jmeter-bad scenario-01-jmeter-good \
        scenario-01-wrk scenario-01-hey \
        scenario-02 scenario-02-ab scenario-02-wrk2 scenario-02-vegeta \
        scenario-02-k6-bad scenario-02-k6-good \
        scenario-02-jmeter-bad scenario-02-jmeter-good \
        scenario-02-wrk scenario-02-hey \
        build-server run-server stop-server \
        build-images-01 build-images-02 build-images publish-blog \
        clean check-tools

help:
	@echo "Targets:"
	@echo "  make check-tools          # report which load tools are installed"
	@echo "  make setup                # pip install Python deps for the analysis pipeline"
	@echo "  make mvp                  # run the canonical scenario end-to-end and render images"
	@echo "  make scenario-01          # ab + Vegeta against a healthy server (control)"
	@echo "  make scenario-02          # ab + Vegeta against a server with a 1s hiccup at t=30s"
	@echo "  make build-images-01      # render images for scenario 01 (or synthetic if missing)"
	@echo "  make build-images-02      # render images for scenario 02 (or synthetic if missing)"
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

# Each runner gets a fresh server so that the hiccup is replayed from t=30s.
# We start, run, stop in sequence — separate targets keep make output legible.
#
# Variables HICCUP_AT and HICCUP_DURATION default to scenario-02's profile;
# the scenario-01 targets override them to "0" so the server stays healthy.

scenario-01-ab: build-server
	@$(MAKE) -s _run-ab SCENARIO=01-healthy SERVER_HICCUP_AT=0 SERVER_HICCUP_DURATION=0

scenario-01-vegeta: build-server
	@$(MAKE) -s _run-vegeta SCENARIO=01-healthy SERVER_HICCUP_AT=0 SERVER_HICCUP_DURATION=0

scenario-01-k6-bad: build-server
	@$(MAKE) -s _run-k6-bad SCENARIO=01-healthy SERVER_HICCUP_AT=0 SERVER_HICCUP_DURATION=0

scenario-01-k6-good: build-server
	@$(MAKE) -s _run-k6-good SCENARIO=01-healthy SERVER_HICCUP_AT=0 SERVER_HICCUP_DURATION=0

scenario-01-jmeter-bad: build-server
	@$(MAKE) -s _run-jmeter-bad SCENARIO=01-healthy SERVER_HICCUP_AT=0 SERVER_HICCUP_DURATION=0

scenario-01-jmeter-good: build-server
	@$(MAKE) -s _run-jmeter-good SCENARIO=01-healthy SERVER_HICCUP_AT=0 SERVER_HICCUP_DURATION=0

scenario-01-wrk: build-server
	@$(MAKE) -s _run-wrk SCENARIO=01-healthy SERVER_HICCUP_AT=0 SERVER_HICCUP_DURATION=0

scenario-01-hey: build-server
	@$(MAKE) -s _run-hey SCENARIO=01-healthy SERVER_HICCUP_AT=0 SERVER_HICCUP_DURATION=0

scenario-01: scenario-01-ab scenario-01-vegeta scenario-01-k6-bad scenario-01-k6-good \
             scenario-01-jmeter-bad scenario-01-jmeter-good \
             scenario-01-wrk scenario-01-hey

scenario-02-ab: build-server
	@$(MAKE) -s _run-ab SCENARIO=02-single-hiccup SERVER_HICCUP_AT=$(HICCUP_AT) SERVER_HICCUP_DURATION=$(HICCUP_DURATION)

scenario-02-wrk2: build-server
	@$(MAKE) -s _run-wrk2 SCENARIO=02-single-hiccup SERVER_HICCUP_AT=$(HICCUP_AT) SERVER_HICCUP_DURATION=$(HICCUP_DURATION)

scenario-02-vegeta: build-server
	@$(MAKE) -s _run-vegeta SCENARIO=02-single-hiccup SERVER_HICCUP_AT=$(HICCUP_AT) SERVER_HICCUP_DURATION=$(HICCUP_DURATION)

scenario-02-k6-bad: build-server
	@$(MAKE) -s _run-k6-bad SCENARIO=02-single-hiccup SERVER_HICCUP_AT=$(HICCUP_AT) SERVER_HICCUP_DURATION=$(HICCUP_DURATION)

scenario-02-k6-good: build-server
	@$(MAKE) -s _run-k6-good SCENARIO=02-single-hiccup SERVER_HICCUP_AT=$(HICCUP_AT) SERVER_HICCUP_DURATION=$(HICCUP_DURATION)

scenario-02-jmeter-bad: build-server
	@$(MAKE) -s _run-jmeter-bad SCENARIO=02-single-hiccup SERVER_HICCUP_AT=$(HICCUP_AT) SERVER_HICCUP_DURATION=$(HICCUP_DURATION)

scenario-02-jmeter-good: build-server
	@$(MAKE) -s _run-jmeter-good SCENARIO=02-single-hiccup SERVER_HICCUP_AT=$(HICCUP_AT) SERVER_HICCUP_DURATION=$(HICCUP_DURATION)

scenario-02-wrk: build-server
	@$(MAKE) -s _run-wrk SCENARIO=02-single-hiccup SERVER_HICCUP_AT=$(HICCUP_AT) SERVER_HICCUP_DURATION=$(HICCUP_DURATION)

scenario-02-hey: build-server
	@$(MAKE) -s _run-hey SCENARIO=02-single-hiccup SERVER_HICCUP_AT=$(HICCUP_AT) SERVER_HICCUP_DURATION=$(HICCUP_DURATION)

# Default scenario runs all 8 supported tools: ab + wrk + hey (closed loop),
# Vegeta + k6 (×2) + JMeter (×2) (the open/closed pairs configurable in the
# article's tooling list). wrk2 is supported but not invoked by default
# because it cannot be built on Apple Silicon without patches.
scenario-02: scenario-02-ab scenario-02-wrk scenario-02-hey \
             scenario-02-vegeta scenario-02-k6-bad scenario-02-k6-good \
             scenario-02-jmeter-bad scenario-02-jmeter-good

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
	@$(SERVER_BIN) -addr $(SERVER_ADDR) -baseline-latency $(BASELINE_LATENCY) \
	               -hiccup-at $(SERVER_HICCUP_AT) -hiccup-duration $(SERVER_HICCUP_DURATION) \
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

build-images: build-images-01 build-images-02

# Default target for "everything in one shot". The leading dash on the
# scenario line tells make to keep going if Go or wrk2 are missing —
# build-images-02 then falls back to synthetic data so a contributor
# always gets a rendered comparison plot.
mvp:
	-@$(MAKE) scenario-02
	@$(MAKE) build-images-02

publish-blog:
	@if [ ! -d "$(BLOG_IMG_DIR)" ]; then \
	  echo "blog image dir does not exist: $(BLOG_IMG_DIR)" >&2; exit 1; \
	fi
	rsync -av --delete images/ "$(BLOG_IMG_DIR)/"

clean: stop-server
	rm -f $(SERVER_BIN) $(SERVER_LOG) $(SERVER_LOG).*
	rm -rf results/*/ab results/*/wrk results/*/wrk2 results/*/hey \
	       results/*/vegeta results/*/k6-bad results/*/k6-good \
	       results/*/jmeter-bad results/*/jmeter-good

# Removes the virtualenv too. Kept separate so `make clean` does not force
# a re-install on every iteration.
distclean: clean
	rm -rf $(VENV)
