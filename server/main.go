package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"
)

type config struct {
	addr            string
	baselineLatency time.Duration

	// Single hiccup at a fixed offset (scenario 02).
	hiccupAt       time.Duration
	hiccupDuration time.Duration

	// Linear baseline-latency ramp (scenario 03).
	rampStart time.Duration
	rampEnd   time.Duration
	rampTo    time.Duration

	// Recurring short pauses (scenario 04).
	gcPauseEvery    time.Duration
	gcPauseDuration time.Duration

	// Bounded server capacity (scenario 05).
	maxConcurrency int
}

// hiccupGate blocks every request that arrives while a pause is in progress.
// A scheduled pause grabs the write lock for `duration`, so all in-flight
// /api requests pile up at gate.RLock() and unblock together when the pause
// ends — the same shape as a stop-the-world GC pause from the client side.
type hiccupGate struct {
	mu sync.RWMutex
}

func (g *hiccupGate) wait() {
	g.mu.RLock()
	g.mu.RUnlock()
}

func (g *hiccupGate) hold(d time.Duration) {
	g.mu.Lock()
	time.Sleep(d)
	g.mu.Unlock()
}

func main() {
	cfg := parseFlags()

	gate := &hiccupGate{}
	startedAt := time.Now()

	// Concurrency cap (scenario 05). A buffered channel acts as a counting
	// semaphore. Requests that find the slot taken queue on the channel send.
	var slot chan struct{}
	if cfg.maxConcurrency > 0 {
		slot = make(chan struct{}, cfg.maxConcurrency)
	}

	if cfg.hiccupAt > 0 && cfg.hiccupDuration > 0 {
		time.AfterFunc(cfg.hiccupAt, func() {
			log.Printf("hiccup START at +%s for %s", time.Since(startedAt).Round(time.Millisecond), cfg.hiccupDuration)
			gate.hold(cfg.hiccupDuration)
			log.Printf("hiccup END at +%s", time.Since(startedAt).Round(time.Millisecond))
		})
	}

	if cfg.gcPauseEvery > 0 && cfg.gcPauseDuration > 0 {
		go func() {
			ticker := time.NewTicker(cfg.gcPauseEvery)
			defer ticker.Stop()
			for range ticker.C {
				log.Printf("gc-pause START at +%s for %s", time.Since(startedAt).Round(time.Millisecond), cfg.gcPauseDuration)
				gate.hold(cfg.gcPauseDuration)
			}
		}()
	}

	currentBaseline := func() time.Duration {
		if cfg.rampEnd <= cfg.rampStart || cfg.rampTo <= cfg.baselineLatency {
			return cfg.baselineLatency
		}
		t := time.Since(startedAt)
		if t <= cfg.rampStart {
			return cfg.baselineLatency
		}
		if t >= cfg.rampEnd {
			return cfg.rampTo
		}
		span := float64(cfg.rampEnd - cfg.rampStart)
		progress := float64(t-cfg.rampStart) / span
		delta := time.Duration(float64(cfg.rampTo-cfg.baselineLatency) * progress)
		return cfg.baselineLatency + delta
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/healthy", func(w http.ResponseWriter, r *http.Request) {
		if cfg.baselineLatency > 0 {
			time.Sleep(cfg.baselineLatency)
		}
		fmt.Fprintln(w, "ok")
	})
	mux.HandleFunc("/api", func(w http.ResponseWriter, r *http.Request) {
		if slot != nil {
			slot <- struct{}{}
			defer func() { <-slot }()
		}
		if d := currentBaseline(); d > 0 {
			time.Sleep(d)
		}
		gate.wait()
		fmt.Fprintln(w, "ok")
	})

	srv := &http.Server{
		Addr:              cfg.addr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

	go func() {
		log.Printf("listening on %s (baseline=%s, hiccup at=+%s, duration=%s)",
			cfg.addr, cfg.baselineLatency, cfg.hiccupAt, cfg.hiccupDuration)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("server error: %v", err)
		}
	}()

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	<-sig
	log.Println("shutting down")
	_ = srv.Close()
}

func parseFlags() config {
	cfg := config{}
	flag.StringVar(&cfg.addr, "addr", ":8080", "listen address")
	flag.DurationVar(&cfg.baselineLatency, "baseline-latency", 1*time.Millisecond, "baseline latency added to every response")
	flag.DurationVar(&cfg.hiccupAt, "hiccup-at", 0, "schedule a single hiccup this duration after startup (0 disables)")
	flag.DurationVar(&cfg.hiccupDuration, "hiccup-duration", 0, "duration of the scheduled hiccup")
	flag.DurationVar(&cfg.rampStart, "ramp-start", 0, "scenario 03: when the baseline-latency ramp begins")
	flag.DurationVar(&cfg.rampEnd, "ramp-end", 0, "scenario 03: when the baseline-latency ramp ends")
	flag.DurationVar(&cfg.rampTo, "ramp-to", 0, "scenario 03: target baseline-latency at ramp-end (must exceed -baseline-latency)")
	flag.DurationVar(&cfg.gcPauseEvery, "gc-pause-every", 0, "scenario 04: interval between recurring pauses (0 disables)")
	flag.DurationVar(&cfg.gcPauseDuration, "gc-pause-duration", 0, "scenario 04: duration of each recurring pause")
	flag.IntVar(&cfg.maxConcurrency, "max-concurrency", 0, "scenario 05: cap on concurrent /api in-flight requests (0 disables)")
	flag.Parse()
	return cfg
}
