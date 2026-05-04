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

.PHONY: help setup mvp scenario-02 scenario-02-ab scenario-02-wrk2 \
        scenario-02-vegeta build-server run-server stop-server \
        build-images-02 build-images publish-blog clean check-tools

help:
	@echo "Targets:"
	@echo "  make check-tools          # report which load tools are installed"
	@echo "  make setup                # pip install Python deps for the analysis pipeline"
	@echo "  make mvp                  # run the canonical scenario end-to-end and render images"
	@echo "  make scenario-02          # ab + wrk2 against a fresh server with a 1s hiccup at t=30s"
	@echo "  make build-images-02      # render images from current results (or synthetic if missing)"
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
scenario-02-ab: build-server
	@$(MAKE) -s stop-server
	@$(SERVER_BIN) -addr $(SERVER_ADDR) -baseline-latency $(BASELINE_LATENCY) \
	               -hiccup-at $(HICCUP_AT) -hiccup-duration $(HICCUP_DURATION) \
	               > $(SERVER_LOG).ab 2>&1 & echo $$! > $(SERVER_PID_FILE)
	@sleep 0.5
	@HOST=$(SERVER_HOST) bash load-tools/ab/run.sh 02-single-hiccup
	@$(MAKE) -s stop-server

scenario-02-wrk2: build-server
	@$(MAKE) -s stop-server
	@$(SERVER_BIN) -addr $(SERVER_ADDR) -baseline-latency $(BASELINE_LATENCY) \
	               -hiccup-at $(HICCUP_AT) -hiccup-duration $(HICCUP_DURATION) \
	               > $(SERVER_LOG).wrk2 2>&1 & echo $$! > $(SERVER_PID_FILE)
	@sleep 0.5
	@HOST=$(SERVER_HOST) bash load-tools/wrk2/run.sh 02-single-hiccup
	@$(MAKE) -s stop-server

scenario-02-vegeta: build-server
	@$(MAKE) -s stop-server
	@$(SERVER_BIN) -addr $(SERVER_ADDR) -baseline-latency $(BASELINE_LATENCY) \
	               -hiccup-at $(HICCUP_AT) -hiccup-duration $(HICCUP_DURATION) \
	               > $(SERVER_LOG).vegeta 2>&1 & echo $$! > $(SERVER_PID_FILE)
	@sleep 0.5
	@HOST=$(SERVER_HOST) bash load-tools/vegeta/run.sh 02-single-hiccup
	@$(MAKE) -s stop-server

# Default scenario uses ab (closed-loop, susceptible) and Vegeta (open-loop,
# honest). wrk2 is supported but not invoked by default because it cannot
# be built on Apple Silicon without patches.
scenario-02: scenario-02-ab scenario-02-vegeta

build-images-02: setup
	@$(PYTHON) analysis/generate_images.py --scenario 02-single-hiccup --mode auto

build-images: build-images-02

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
	rm -f $(SERVER_BIN) $(SERVER_LOG) $(SERVER_LOG).ab $(SERVER_LOG).wrk2 $(SERVER_LOG).vegeta
	rm -rf results/*/ab results/*/wrk2 results/*/vegeta

# Removes the virtualenv too. Kept separate so `make clean` does not force
# a re-install on every iteration.
distclean: clean
	rm -rf $(VENV)
