package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// These are saved Minecraft counters, not reconstructed log sessions. Game time
// is in ticks (nominally 20/s), so lag can make it differ from wall-clock time.
func playerStatsMetrics(root string) (string, error) {
	var out strings.Builder
	server := filepath.Base(root)
	data, err := os.ReadFile(filepath.Join(root, "usercache.json"))
	if err != nil {
		return "", err
	}
	var users []struct {
		Name string `json:"name"`
		UUID string `json:"uuid"`
	}
	if err = json.Unmarshal(data, &users); err != nil {
		return "", err
	}
	names := map[string]string{}
	for _, u := range users {
		if namePattern.MatchString(u.Name) {
			names[strings.ToLower(u.UUID)] = u.Name
		}
	}
	files, err := filepath.Glob(filepath.Join(root, "world/players/stats/*.json"))
	if err != nil {
		return "", err
	}
	// Glob returns an empty list for a missing directory too; do not report success.
	if _, err = os.Stat(filepath.Join(root, "world/players/stats")); err != nil {
		return "", err
	}
	var errors []string
	for _, file := range files {
		uuid := strings.TrimSuffix(filepath.Base(file), ".json")
		name := names[strings.ToLower(uuid)]
		if name == "" {
			name = uuid
		}
		ls := labels("server", server, "player", name, "uuid", uuid)
		metrics, err := readPlayerStats(file, ls, server, name, uuid)
		metric(&out, "minecraft_player_stats_file_collection_success", boolFloat(err == nil), ls)
		if err != nil {
			errors = append(errors, fmt.Sprintf("%s: %v", uuid, err))
			continue
		}
		out.WriteString(metrics)
	}
	if len(errors) > 0 {
		return out.String(), fmt.Errorf("%s", strings.Join(errors, "; "))
	}
	return out.String(), nil
}

func readPlayerStats(file, ls, server, name, uuid string) (string, error) {
	data, err := os.ReadFile(file)
	if err != nil {
		return "", err
	}
	var document struct {
		Stats map[string]map[string]float64 `json:"stats"`
	}
	if err = json.Unmarshal(data, &document); err != nil {
		return "", err
	}
	if document.Stats == nil {
		return "", fmt.Errorf("missing stats object")
	}
	// Reject corrupt negative counters instead of publishing misleading data.
	for _, category := range document.Stats {
		for _, value := range category {
			if value < 0 {
				return "", fmt.Errorf("negative stat")
			}
		}
	}
	info, err := os.Stat(file)
	if err != nil {
		return "", err
	}
	var out strings.Builder
	custom := document.Stats["minecraft:custom"]
	if custom == nil {
		return "", fmt.Errorf("missing custom stats object")
	}
	for stat, metricName := range map[string]string{
		"play_time":  "minecraft_player_game_play_seconds_total",
		"deaths":     "minecraft_player_deaths_total",
		"mob_kills":  "minecraft_player_mob_kills_total",
		"jump":       "minecraft_player_jumps_total",
		"leave_game": "minecraft_player_logouts_total",
	} {
		value, present := custom["minecraft:"+stat]
		if stat == "play_time" {
			if !present {
				continue
			}
			value /= 20
		}
		metric(&out, metricName, value, ls)
	}
	for category, metricName := range map[string]string{
		"mined":   "minecraft_player_blocks_mined_total",
		"crafted": "minecraft_player_items_crafted_total",
	} {
		total := 0.0
		for _, value := range document.Stats["minecraft:"+category] {
			total += value
		}
		metric(&out, metricName, total, ls)
	}
	// Keep cardinality bounded: no per-block, item or entity labels.
	modes := []string{"walk", "sprint", "crouch", "swim", "aviate", "fly", "boat", "horse", "minecart", "strider", "happy_ghast", "nautilus", "walk_under_water", "walk_on_water", "climb", "fall"}
	sort.Strings(modes)
	for _, mode := range modes {
		metric(&out, "minecraft_player_distance_meters_total", custom["minecraft:"+mode+"_one_cm"]/100, labels("server", server, "player", name, "uuid", uuid, "mode", mode))
	}
	metric(&out, "minecraft_player_stats_saved_timestamp_seconds", float64(info.ModTime().Unix()), ls)
	return out.String(), nil
}
