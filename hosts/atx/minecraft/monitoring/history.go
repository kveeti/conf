package main

import (
	"encoding/json"
	"io"
	"sort"
	"strings"
	"time"
)

const historyUnknown = "<minecraft-exporter: unknown history boundary>"

// A later unclean restart proves the previous open sessions did not continue
// until that restart. Keep only the last log evidence, and leave the gap unknown.
// Conversely, a paired join/leave proves a long session even if it was quiet.
func historyEvents(events []event) []event {
	p := newPlayers()
	var result []event
	for _, e := range events {
		if strings.HasPrefix(e.message, "Starting minecraft server version") && len(p.online) > 0 {
			boundary := event{p.lastEvent, historyUnknown}
			result = append(result, boundary)
			p.apply(boundary)
		}
		result = append(result, e)
		p.apply(e)
	}
	return result
}

// JSON-lines import format accepted by VictoriaMetrics /api/v1/import.
// Run explicitly once; the live exporter never writes historical data itself.
func writeHistory(w io.Writer, events []event, server string) error {
	if len(events) == 0 {
		return nil
	}
	events = historyEvents(events)
	all := newPlayers()
	for _, e := range events {
		all.apply(e)
	}
	names := make([]string, 0, len(all.known))
	for name := range all.known {
		names = append(names, name)
	}
	sort.Strings(names)
	type series struct {
		Metric     map[string]string `json:"metric"`
		Values     []float64         `json:"values"`
		Timestamps []int64           `json:"timestamps"`
	}
	samples := map[string]*series{}
	add := func(name, player string, at time.Time, value float64) {
		key := name + ":" + player
		s := samples[key]
		if s == nil {
			s = &series{Metric: map[string]string{"__name__": name, "server": server, "instance": "minecraft", "host": "minecraft", "job": "minecraft"}}
			if player != "" {
				s.Metric["player"] = player
			}
			samples[key] = s
		}
		s.Values = append(s.Values, value)
		s.Timestamps = append(s.Timestamps, at.UnixMilli())
	}
	p := newPlayers()
	index := 0
	// Do not extrapolate past the last log entry.
	for at := events[0].at.Truncate(30 * time.Second).Add(30 * time.Second); !at.After(events[len(events)-1].at); at = at.Add(30 * time.Second) {
		for index < len(events) && !events[index].at.After(at) {
			p.apply(events[index])
			index++
		}
		if !p.reliable {
			continue
		}
		add("minecraft_players_online", "", at, float64(len(p.online)))
		for _, name := range names {
			_, online := p.online[name]
			add("minecraft_player_online", name, at, boolFloat(online))
		}
	}
	encoder := json.NewEncoder(w)
	keys := make([]string, 0, len(samples))
	for key := range samples {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	for _, key := range keys {
		if err := encoder.Encode(samples[key]); err != nil {
			return err
		}
	}
	return nil
}
