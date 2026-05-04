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
	hiccupAt        time.Duration
	hiccupDuration  time.Duration
}

// hiccupGate blocks every request that arrives while a hiccup is in progress.
// A scheduled hiccup grabs the write lock for `duration`, so all in-flight
// /api requests pile up at gate.RLock() and unblock together when the hiccup
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

	if cfg.hiccupAt > 0 && cfg.hiccupDuration > 0 {
		time.AfterFunc(cfg.hiccupAt, func() {
			log.Printf("hiccup START at +%s for %s", time.Since(startedAt).Round(time.Millisecond), cfg.hiccupDuration)
			gate.hold(cfg.hiccupDuration)
			log.Printf("hiccup END at +%s", time.Since(startedAt).Round(time.Millisecond))
		})
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/healthy", func(w http.ResponseWriter, r *http.Request) {
		if cfg.baselineLatency > 0 {
			time.Sleep(cfg.baselineLatency)
		}
		fmt.Fprintln(w, "ok")
	})
	mux.HandleFunc("/api", func(w http.ResponseWriter, r *http.Request) {
		if cfg.baselineLatency > 0 {
			time.Sleep(cfg.baselineLatency)
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
	flag.Parse()
	return cfg
}
