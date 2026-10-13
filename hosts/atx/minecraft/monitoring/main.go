// Minecraft exporter: standard library only, no commands sent to the game console.
package main

import (
	"bufio"
	"bytes"
	"compress/gzip"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

var linePattern = regexp.MustCompile(`^\[(\d{2}:\d{2}:\d{2})\] \[Server thread/INFO\]: (.*)$`)
var playerPattern = regexp.MustCompile(`^([A-Za-z0-9_]{1,16}) (joined the game|left the game)$`)
var listPattern = regexp.MustCompile(`^There are (\d+) of a max of \d+ players online: ?(.*)$`)
var namePattern = regexp.MustCompile(`^[A-Za-z0-9_]{1,16}$`)
var archivePattern = regexp.MustCompile(`^(\d{4}-\d{2}-\d{2})-(\d+)\.log\.gz$`)

type event struct {
	at      time.Time
	message string
}
type cachedLog struct {
	size     int64
	modified time.Time
	events   []event
}
type logReader struct {
	cache    map[string]cachedLog
	location *time.Location
}

// Archive dates describe the day the file started. Times can cross midnight.
// latest.log's mtime describes its last line's day, not necessarily its first.
func parseLog(data []byte, day time.Time, latest bool) ([]event, error) {
	var result []event
	scanner := bufio.NewScanner(bytes.NewReader(data))
	scanner.Buffer(make([]byte, 4096), 1024*1024)
	previous := -1
	for scanner.Scan() {
		match := linePattern.FindStringSubmatch(strings.TrimRight(scanner.Text(), "\r"))
		if match == nil {
			continue
		}
		clock, err := time.Parse("15:04:05", match[1])
		if err != nil {
			continue
		}
		seconds := clock.Hour()*3600 + clock.Minute()*60 + clock.Second()
		// Small backwards jumps can be clock corrections; large ones are midnight.
		if previous >= 0 && previous-seconds > 12*3600 {
			day = day.AddDate(0, 0, 1)
		}
		previous = seconds
		at := time.Date(day.Year(), day.Month(), day.Day(), clock.Hour(), clock.Minute(), clock.Second(), 0, day.Location())
		result = append(result, event{at, match[2]})
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	if latest && len(result) > 0 {
		last := result[len(result)-1].at
		// Shift calendar days (not 24-hour durations, for DST).
		// Number of midnight rollovers is the difference between first and last dates.
		first := result[0].at
		shift := 0
		for d := first; d.Format("2006-01-02") < last.Format("2006-01-02"); d = d.AddDate(0, 0, 1) {
			shift++
		}
		for i := range result {
			result[i].at = result[i].at.AddDate(0, 0, -shift)
		}
	}
	return result, nil
}

func (r *logReader) read(dir string) ([]event, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	type file struct {
		name, date string
		index      int
		latest     bool
	}
	var files []file
	for _, entry := range entries {
		if entry.Name() == "latest.log" {
			files = append(files, file{name: entry.Name(), latest: true})
			continue
		}
		if m := archivePattern.FindStringSubmatch(entry.Name()); m != nil {
			n, _ := strconv.Atoi(m[2])
			files = append(files, file{entry.Name(), m[1], n, false})
		}
	}
	sort.Slice(files, func(i, j int) bool {
		a, b := files[i], files[j]
		if a.latest != b.latest {
			return !a.latest
		}
		if a.date != b.date {
			return a.date < b.date
		}
		return a.index < b.index
	})
	if len(files) == 0 {
		return nil, fmt.Errorf("no Minecraft logs in %s", dir)
	}
	var all []event
	seen := map[string]bool{}
	for _, item := range files {
		path := filepath.Join(dir, item.name)
		seen[path] = true
		info, err := os.Stat(path)
		if err != nil {
			return nil, err
		}
		cached, ok := r.cache[path]
		if !ok || cached.size != info.Size() || !cached.modified.Equal(info.ModTime()) {
			data, err := os.ReadFile(path)
			if err != nil {
				return nil, err
			}
			if !item.latest {
				zipped, err := gzip.NewReader(bytes.NewReader(data))
				if err != nil {
					return nil, err
				}
				data, err = io.ReadAll(io.LimitReader(zipped, 64*1024*1024+1))
				zipped.Close()
				if err != nil {
					return nil, err
				}
				if len(data) > 64*1024*1024 {
					return nil, fmt.Errorf("log too large: %s", path)
				}
			} else {
				// A concurrently written partial last line is not an event yet.
				if end := bytes.LastIndexByte(data, '\n'); end >= 0 {
					data = data[:end+1]
				} else {
					data = nil
				}
			}
			day := info.ModTime().In(r.location)
			if !item.latest {
				day, err = time.ParseInLocation("2006-01-02", item.date, r.location)
				if err != nil {
					return nil, err
				}
			}
			parsed, err := parseLog(data, day, item.latest)
			if err != nil {
				return nil, err
			}
			cached = cachedLog{info.Size(), info.ModTime(), parsed}
			r.cache[path] = cached
		}
		all = append(all, cached.events...)
	}
	for path := range r.cache {
		if !seen[path] {
			delete(r.cache, path)
		}
	}
	// Preserve file order for events with the same timestamp.
	sort.SliceStable(all, func(i, j int) bool { return all[i].at.Before(all[j].at) })
	return all, nil
}

type players struct {
	known     map[string]bool
	online    map[string]time.Time
	seconds   map[string]float64
	reliable  bool
	lastEvent time.Time
}

func newPlayers() *players {
	return &players{known: map[string]bool{}, online: map[string]time.Time{}, seconds: map[string]float64{}}
}

// servu's backup job writes player lists every 12–18 minutes. After a long
// silence we cannot distinguish an idle server from a crash or missing logs.
func (p *players) advance(at time.Time) {
	if !p.lastEvent.IsZero() && at.Sub(p.lastEvent) > 30*time.Minute {
		for name := range p.online {
			p.leave(name, p.lastEvent)
		}
		p.reliable = false
	}
}
func (p *players) leave(name string, at time.Time) {
	if start, ok := p.online[name]; ok {
		if at.After(start) {
			p.seconds[name] += at.Sub(start).Seconds()
		}
		delete(p.online, name)
	}
}
func (p *players) apply(e event) {
	if e.message == historyUnknown {
		for name := range p.online {
			p.leave(name, e.at)
		}
		p.reliable = false
		p.lastEvent = e.at
		return
	}
	if strings.HasPrefix(e.message, "Starting minecraft server version") {
		// A restart without a stop does not establish the time of the crash.
		for name := range p.online {
			p.leave(name, p.lastEvent)
		}
		p.reliable = true
	} else if e.message == "Stopping server" {
		for name := range p.online {
			p.leave(name, e.at)
		}
		p.reliable = true
	}
	p.lastEvent = e.at
	if m := playerPattern.FindStringSubmatch(e.message); m != nil {
		name := m[1]
		p.known[name] = true
		if m[2] == "joined the game" {
			if _, ok := p.online[name]; !ok {
				p.online[name] = e.at
			}
		} else {
			p.leave(name, e.at)
		}
		return
	}
	if m := listPattern.FindStringSubmatch(e.message); m != nil {
		names := map[string]bool{}
		for _, name := range strings.Split(m[2], ",") {
			name = strings.TrimSpace(strings.TrimSuffix(strings.TrimSpace(name), " [AFK]"))
			if name == "" {
				continue
			}
			if !namePattern.MatchString(name) {
				return
			}
			names[name] = true
		}
		count, _ := strconv.Atoi(m[1])
		if len(names) != count {
			return
		}
		for name := range p.online {
			if !names[name] {
				p.leave(name, e.at)
			}
		}
		for name := range names {
			p.known[name] = true
			if _, ok := p.online[name]; !ok {
				p.online[name] = e.at
			}
		}
		p.reliable = true
	}
}

// Playtime is a gauge reconstructed from retained logs, not a monotonic counter.
func (p *players) total(name string, now time.Time) float64 {
	result := p.seconds[name]
	if start, ok := p.online[name]; ok && now.After(start) {
		result += now.Sub(start).Seconds()
	}
	return result
}

func labels(values ...string) string {
	var parts []string
	for i := 0; i < len(values); i += 2 {
		parts = append(parts, values[i]+"="+strconv.Quote(values[i+1]))
	}
	return "{" + strings.Join(parts, ",") + "}"
}
func metric(out *strings.Builder, name string, value float64, ls string) {
	fmt.Fprintf(out, "%s%s %g\n", name, ls, value)
}
func command(timeout time.Duration, name string, args ...string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	return exec.CommandContext(ctx, name, args...).Output()
}
func diskBytes(path string) (float64, error) {
	out, err := command(90*time.Second, "du", "-s", "-B1", "--", path)
	if err != nil {
		return 0, err
	}
	fields := strings.Fields(string(out))
	if len(fields) < 1 {
		return 0, fmt.Errorf("empty du output")
	}
	return strconv.ParseFloat(fields[0], 64)
}

// Read process counters from procfs. starttime makes PID reuse a distinct series.
func processMetrics(root string, ticks float64) (string, bool, error) {
	entries, err := os.ReadDir("/proc")
	if err != nil {
		return "", false, err
	}
	var out strings.Builder
	count := 0
	for _, entry := range entries {
		if _, err := strconv.Atoi(entry.Name()); err != nil {
			continue
		}
		dir := filepath.Join("/proc", entry.Name())
		cwd, err := os.Readlink(filepath.Join(dir, "cwd"))
		if err != nil || cwd != root {
			continue
		}
		exe, err := os.Readlink(filepath.Join(dir, "exe"))
		if err != nil || filepath.Base(exe) != "java" {
			continue
		}
		data, err := os.ReadFile(filepath.Join(dir, "stat"))
		if err != nil {
			return "", false, err
		}
		end := strings.LastIndexByte(string(data), ')')
		if end < 0 {
			return "", false, fmt.Errorf("invalid proc stat")
		}
		fields := strings.Fields(string(data[end+1:]))
		if len(fields) < 22 {
			return "", false, fmt.Errorf("short proc stat")
		}
		user, e1 := strconv.ParseFloat(fields[11], 64)
		system, e2 := strconv.ParseFloat(fields[12], 64)
		rss, e3 := strconv.ParseFloat(fields[21], 64)
		if e1 != nil || e2 != nil || e3 != nil {
			return "", false, fmt.Errorf("invalid process counters")
		}
		ls := labels("server", filepath.Base(root), "pid", entry.Name(), "start_ticks", fields[19])
		metric(&out, "minecraft_process_cpu_seconds_total", (user+system)/ticks, ls)
		metric(&out, "minecraft_process_resident_memory_bytes", rss*float64(os.Getpagesize()), ls)
		details, err := processDetails(dir, fields, ticks, ls)
		metric(&out, "minecraft_process_details_collection_success", boolFloat(err == nil), ls)
		if err == nil {
			out.WriteString(details)
		}
		count++
	}
	if count > 1 {
		return "", false, fmt.Errorf("multiple Java processes for %s", root)
	}
	return out.String(), count == 1, nil
}

type exporter struct {
	mu           sync.RWMutex
	fast, slow   string
	reader       *logReader
	root, backup string
	ticks        float64
}

func (x *exporter) collectFast() {
	var out strings.Builder
	ls := labels("server", filepath.Base(x.root))
	process, running, processErr := processMetrics(x.root, x.ticks)
	if processErr != nil {
		log.Printf("process: %v", processErr)
	}
	metric(&out, "minecraft_process_collection_success", boolFloat(processErr == nil), ls)
	if processErr == nil {
		out.WriteString(process)
		metric(&out, "minecraft_server_running", boolFloat(running), ls)
	}
	events, err := x.reader.read(filepath.Join(x.root, "logs"))
	metric(&out, "minecraft_log_collection_success", boolFloat(err == nil), ls)
	if err != nil {
		log.Printf("logs: %v", err)
	} else {
		p := newPlayers()
		for _, e := range events {
			p.apply(e)
		}
		now := time.Now()
		p.advance(now)
		if processErr == nil && !running {
			for name := range p.online {
				p.leave(name, p.lastEvent)
			}
			p.reliable = true
		}
		// A known Java process is required before publishing live player state.
		if processErr == nil && p.reliable {
			metric(&out, "minecraft_players_online", float64(len(p.online)), ls)
			for name := range p.known {
				pl := labels("server", filepath.Base(x.root), "player", name)
				_, online := p.online[name]
				metric(&out, "minecraft_player_online", boolFloat(online), pl)
			}
		}
		for name := range p.known {
			metric(&out, "minecraft_player_retained_log_seconds", p.total(name, now), labels("server", filepath.Base(x.root), "player", name))
		}
	}
	out.WriteString(filesystemMetrics(x.root, filepath.Base(x.root)))
	out.WriteString(backupStatusMetrics(x.backup, filepath.Base(x.root)))
	stats, statsErr := playerStatsMetrics(x.root)
	out.WriteString(stats)
	metric(&out, "minecraft_player_stats_collection_success", boolFloat(statsErr == nil), ls)
	if statsErr != nil {
		log.Printf("player stats: %v", statsErr)
	}
	metric(&out, "minecraft_fast_collection_timestamp_seconds", float64(time.Now().Unix()), ls)
	x.mu.Lock()
	x.fast = out.String()
	x.mu.Unlock()
}
func boolFloat(b bool) float64 {
	if b {
		return 1
	}
	return 0
}
func (x *exporter) collectSlow() {
	var out strings.Builder
	ls := labels("server", filepath.Base(x.root))
	paths := map[string]string{"server": x.root, "world": filepath.Join(x.root, "world"), "backups": x.backup, "bluemap": filepath.Join(x.root, "bluemap")}
	for _, dim := range []string{"overworld", "the_nether", "the_end"} {
		paths[dim] = filepath.Join(x.root, "world/dimensions/minecraft", dim)
	}
	for kind, path := range paths {
		value, err := diskBytes(path)
		dl := labels("server", filepath.Base(x.root), "kind", kind)
		metric(&out, "minecraft_disk_collection_success", boolFloat(err == nil), dl)
		if err == nil {
			metric(&out, "minecraft_disk_bytes", value, dl)
		} else {
			log.Printf("disk %s: %v", kind, err)
		}
	}
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	cmd := exec.CommandContext(ctx, "restic", "--no-lock", "--repo", x.backup, "snapshots", "--json")
	cmd.Env = append(os.Environ(), "RESTIC_PASSWORD=minecraft")
	data, err := cmd.Output()
	cancel()
	var snapshots []struct {
		Time time.Time `json:"time"`
	}
	if err == nil {
		err = json.Unmarshal(data, &snapshots)
	}
	metric(&out, "minecraft_backup_collection_success", boolFloat(err == nil), ls)
	if err == nil {
		metric(&out, "minecraft_backup_snapshots", float64(len(snapshots)), ls)
		if len(snapshots) > 0 {
			var latest time.Time
			for _, s := range snapshots {
				if s.Time.After(latest) {
					latest = s.Time
				}
			}
			metric(&out, "minecraft_backup_latest_snapshot_timestamp_seconds", float64(latest.Unix()), ls)
		}
	} else {
		log.Printf("snapshots: %v", err)
	}
	metric(&out, "minecraft_slow_collection_timestamp_seconds", float64(time.Now().Unix()), ls)
	x.mu.Lock()
	x.slow = out.String()
	x.mu.Unlock()
}
func (x *exporter) serve(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
	x.mu.RLock()
	defer x.mu.RUnlock()
	io.WriteString(w, x.fast+x.slow)
}

func main() {
	listen := flag.String("listen", "127.0.0.1:9150", "loopback metrics address")
	root := flag.String("server", "/home/veeti/servers/servu", "server working directory")
	backup := flag.String("repository", "/home/veeti/backups/servu/repository", "Restic repository")
	zone := flag.String("timezone", "Local", "timezone used by Minecraft log timestamps")
	history := flag.Bool("history", false, "write historical VictoriaMetrics JSON lines to stdout instead of serving")
	flag.Parse()
	location, err := time.LoadLocation(*zone)
	if err != nil {
		log.Fatal(err)
	}
	if *history {
		reader := &logReader{map[string]cachedLog{}, location}
		events, err := reader.read(filepath.Join(*root, "logs"))
		if err != nil {
			log.Fatal(err)
		}
		if err := writeHistory(os.Stdout, events, filepath.Base(*root)); err != nil {
			log.Fatal(err)
		}
		return
	}
	ticksData, err := command(5*time.Second, "getconf", "CLK_TCK")
	if err != nil {
		log.Fatal(err)
	}
	ticks, err := strconv.ParseFloat(strings.TrimSpace(string(ticksData)), 64)
	if err != nil || ticks <= 0 {
		log.Fatal("invalid CLK_TCK")
	}
	resolved, err := filepath.EvalSymlinks(*root)
	if err != nil {
		log.Fatal(err)
	}
	x := &exporter{reader: &logReader{map[string]cachedLog{}, location}, root: resolved, backup: *backup, ticks: ticks}
	x.collectFast()
	go func() {
		for range time.Tick(10 * time.Second) {
			x.collectFast()
		}
	}()
	go func() {
		x.collectSlow()
		for range time.Tick(5 * time.Minute) {
			x.collectSlow()
		}
	}()
	mux := http.NewServeMux()
	mux.HandleFunc("/metrics", x.serve)
	server := &http.Server{Addr: *listen, Handler: mux, ReadHeaderTimeout: 5 * time.Second, WriteTimeout: 10 * time.Second, IdleTimeout: 30 * time.Second}
	log.Printf("Minecraft metrics on %s", *listen)
	log.Fatal(server.ListenAndServe())
}
