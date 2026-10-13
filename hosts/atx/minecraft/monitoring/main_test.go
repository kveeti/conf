package main

import (
	"bytes"
	"compress/gzip"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestPlayers(t *testing.T) {
	p := newPlayers()
	at := time.Date(2026, 10, 9, 12, 0, 0, 0, time.UTC)
	p.apply(event{at, "Starting minecraft server version 1.21"})
	p.apply(event{at, "81133 joined the game"})
	p.apply(event{at.Add(time.Second), "81133 joined the game"})
	p.apply(event{at.Add(time.Minute), "There are 1 of a max of 10 players online: 81133 [AFK]"})
	if len(p.online) != 1 || !p.known["81133"] {
		t.Fatal(p)
	}
	p.apply(event{at.Add(2 * time.Minute), "FishNet (/1.2.3.4:5) lost connection: Disconnected"})
	if len(p.online) != 1 {
		t.Fatal("failed login affected state")
	}
	p.apply(event{at.Add(3 * time.Minute), "81133 left the game"})
	if p.total("81133", at.Add(time.Hour)) != 180 {
		t.Fatal(p.seconds)
	}
	p.apply(event{at.Add(4 * time.Minute), "There are 1 of a max of 10 players online: 71680"})
	p.apply(event{at.Add(5 * time.Minute), "Stopping server"})
	if len(p.online) != 0 || p.total("71680", at.Add(time.Hour)) != 60 {
		t.Fatal(p)
	}
}
func TestUnknownAndMalformedList(t *testing.T) {
	p := newPlayers()
	at := time.Now()
	p.apply(event{at, "81133 joined the game"})
	if p.reliable {
		t.Fatal("join alone cannot establish global state")
	}
	p.apply(event{at, "There are 2 of a max of 10 players online: 81133"})
	if p.reliable {
		t.Fatal("invalid list establishes state")
	}
	p.apply(event{at, "There are 0 of a max of 10 players online: "})
	if !p.reliable || len(p.online) != 0 {
		t.Fatal(p)
	}
}
func TestMidnight(t *testing.T) {
	data := []byte("[23:59:59] [Server thread/INFO]: 81133 joined the game\n[00:01:00] [Server thread/INFO]: 81133 left the game\n")
	for _, latest := range []bool{false, true} {
		day := time.Date(2026, 10, 8, 0, 0, 0, 0, time.UTC)
		if latest {
			day = day.AddDate(0, 0, 1)
		}
		events, err := parseLog(data, day, latest)
		if err != nil {
			t.Fatal(err)
		}
		if len(events) != 2 || events[0].at.Format("2006-01-02") != "2026-10-08" || events[1].at.Sub(events[0].at) != 61*time.Second {
			t.Fatal(events)
		}
	}
}
func TestNumericRotationAndLiveUpdates(t *testing.T) {
	dir := t.TempDir()
	writeGzip := func(name, line string) {
		f, err := os.Create(filepath.Join(dir, name))
		if err != nil {
			t.Fatal(err)
		}
		w := gzip.NewWriter(f)
		_, _ = w.Write([]byte(line))
		w.Close()
		f.Close()
	}
	writeGzip("2026-10-08-2.log.gz", "[12:00:00] [Server thread/INFO]: 81133 joined the game\n")
	writeGzip("2026-10-08-10.log.gz", "[12:00:00] [Server thread/INFO]: 81133 left the game\n")
	path := filepath.Join(dir, "latest.log")
	os.WriteFile(path, []byte("[13:00:00] [Server thread/INFO]: There are 0 of a max of 10 players online: \n[13:01:00] [Server thread/INFO]: 71680 joined the game"), 0600)
	at := time.Date(2026, 10, 8, 14, 0, 0, 0, time.UTC)
	os.Chtimes(path, at, at)
	reader := &logReader{map[string]cachedLog{}, time.UTC}
	events, err := reader.read(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(events) != 3 || !strings.Contains(events[0].message, "joined") {
		t.Fatal(events)
	}
	f, _ := os.OpenFile(path, os.O_APPEND|os.O_WRONLY, 0600)
	f.WriteString("\n")
	f.Close()
	os.Chtimes(path, at, at)
	events, err = reader.read(dir)
	if err != nil || len(events) != 4 {
		t.Fatal(events, err)
	}
	// Rotation to a new latest log must not retain the old cache.
	os.WriteFile(path, []byte("[14:00:00] [Server thread/INFO]: Starting minecraft server version test\n"), 0600)
	os.Chtimes(path, at, at)
	events, err = reader.read(dir)
	if err != nil || len(events) != 3 {
		t.Fatal(events, err)
	}
}
func TestSilenceAndUncleanRestart(t *testing.T) {
	at := time.Date(2026, 10, 9, 12, 0, 0, 0, time.UTC)
	p := newPlayers()
	p.apply(event{at, "Starting minecraft server version test"})
	p.apply(event{at.Add(time.Minute), "81133 joined the game"})
	p.apply(event{at.Add(2 * time.Minute), "Saved the game"})
	p.apply(event{at.Add(10 * time.Minute), "Starting minecraft server version test"})
	if len(p.online) != 0 || p.total("81133", at.Add(time.Hour)) != 60 {
		t.Fatal(p)
	}
	p.apply(event{at.Add(11 * time.Minute), "81133 joined the game"})
	p.advance(at.Add(time.Hour))
	if p.reliable || len(p.online) != 0 {
		t.Fatal("long silence must become unknown")
	}
	p.apply(event{at.Add(time.Hour), "There are 1 of a max of 10 players online: 81133"})
	if !p.reliable || len(p.online) != 1 {
		t.Fatal("player list must reconcile state")
	}
}

func TestQuietSessionIsNotLost(t *testing.T) {
	at := time.Date(2026, 10, 9, 12, 0, 0, 0, time.UTC)
	p := newPlayers()
	p.apply(event{at, "Starting minecraft server version test"})
	p.apply(event{at, "81133 joined the game"})
	p.apply(event{at.Add(2 * time.Hour), "81133 left the game"})
	if p.total("81133", at.Add(3*time.Hour)) != 7200 {
		t.Fatal(p.seconds)
	}
}

func TestHistoryCrashGap(t *testing.T) {
	at := time.Date(2026, 10, 9, 12, 0, 0, 0, time.UTC)
	events := []event{{at, "Starting minecraft server version test"}, {at, "81133 joined the game"}, {at.Add(time.Minute), "Saved the game"}, {at.Add(time.Hour), "Starting minecraft server version test"}}
	var out bytes.Buffer
	if err := writeHistory(&out, events, "servu"); err != nil {
		t.Fatal(err)
	}
	decoder := json.NewDecoder(&out)
	for decoder.More() {
		var s struct{ Timestamps []int64 }
		if err := decoder.Decode(&s); err != nil {
			t.Fatal(err)
		}
		for _, timestamp := range s.Timestamps {
			if timestamp >= at.Add(time.Minute).UnixMilli() && timestamp < at.Add(time.Hour).UnixMilli() {
				t.Fatal("sample invented inside crash gap", timestamp)
			}
		}
	}
}

func TestHistory(t *testing.T) {
	at := time.Date(2026, 10, 9, 12, 0, 0, 0, time.UTC)
	events := []event{{at, "Starting minecraft server version test"}, {at.Add(10 * time.Second), "81133 joined the game"}, {at.Add(40 * time.Second), "81133 left the game"}, {at.Add(time.Minute), "Saved the game"}}
	var out bytes.Buffer
	if err := writeHistory(&out, events, "servu"); err != nil {
		t.Fatal(err)
	}
	decoder := json.NewDecoder(&out)
	found := false
	for decoder.More() {
		var s struct {
			Metric     map[string]string
			Values     []float64
			Timestamps []int64
		}
		if err := decoder.Decode(&s); err != nil {
			t.Fatal(err)
		}
		if s.Metric["__name__"] == "minecraft_player_online" {
			found = true
			if len(s.Values) != 2 || s.Values[0] != 1 || s.Values[1] != 0 || s.Timestamps[0] != at.Add(30*time.Second).UnixMilli() {
				t.Fatal(s)
			}
		}
	}
	if !found {
		t.Fatal("missing player series")
	}
}
