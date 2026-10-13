package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSavedPlayerStats(t *testing.T) {
	root := filepath.Join(t.TempDir(), "servu")
	dir := filepath.Join(root, "world/players/stats")
	if err := os.MkdirAll(dir, 0700); err != nil {
		t.Fatal(err)
	}
	os.WriteFile(filepath.Join(root, "usercache.json"), []byte(`[{"uuid":"abc","name":"81133"}]`), 0600)
	file := filepath.Join(dir, "abc.json")
	os.WriteFile(file, []byte(`{"stats":{"minecraft:custom":{"minecraft:play_time":2400,"minecraft:deaths":3,"minecraft:aviate_one_cm":12345},"minecraft:mined":{"minecraft:stone":12,"minecraft:dirt":5},"minecraft:crafted":{"minecraft:bread":4}}}`), 0600)
	result, err := playerStatsMetrics(root)
	if err != nil {
		t.Fatal(err)
	}
	for _, expected := range []string{
		`minecraft_player_game_play_seconds_total{server="servu",player="81133",uuid="abc"} 120`,
		`minecraft_player_deaths_total{server="servu",player="81133",uuid="abc"} 3`,
		`minecraft_player_blocks_mined_total{server="servu",player="81133",uuid="abc"} 17`,
		`minecraft_player_items_crafted_total{server="servu",player="81133",uuid="abc"} 4`,
		`minecraft_player_distance_meters_total{server="servu",player="81133",uuid="abc",mode="aviate"} 123.45`,
	} {
		if !strings.Contains(result, expected) {
			t.Fatalf("missing %s in %s", expected, result)
		}
	}
	// A missing usercache entry falls back to UUID, preserving usable identity.
	os.WriteFile(filepath.Join(root, "usercache.json"), []byte(`[]`), 0600)
	result, err = playerStatsMetrics(root)
	if err != nil || !strings.Contains(result, `player="abc"`) {
		t.Fatal(result, err)
	}
	// Broken or partially written files must not masquerade as zero counters.
	for _, data := range []string{`{`, `{"stats":{}}`, `{"stats":{"minecraft:custom":{"minecraft:deaths":-1}}}`} {
		os.WriteFile(file, []byte(data), 0600)
		result, err = playerStatsMetrics(root)
		if err == nil || strings.Contains(result, "minecraft_player_deaths_total") {
			t.Fatal(result, err)
		}
		if !strings.Contains(result, `minecraft_player_stats_file_collection_success{server="servu",player="abc",uuid="abc"} 0`) {
			t.Fatal(result)
		}
	}
}

func TestMissingPlayerStats(t *testing.T) {
	root := t.TempDir()
	os.WriteFile(filepath.Join(root, "usercache.json"), []byte(`[]`), 0600)
	if _, err := playerStatsMetrics(root); err == nil {
		t.Fatal("missing stats directory reported healthy")
	}
}

func TestBackupStatusMetrics(t *testing.T) {
	dir := t.TempDir()
	repository := filepath.Join(dir, "repository")
	result := backupStatusMetrics(repository, "servu")
	if !strings.Contains(result, `minecraft_backup_status_collection_success{server="servu"} 0`) || strings.Contains(result, "minecraft_backup_attempt_success") {
		t.Fatal(result)
	}
	file := filepath.Join(dir, ".monitoring.json")
	os.WriteFile(file, []byte(`{"last_attempt":123,"last_success":100,"duration":7,"success":false,"in_progress":true}`), 0600)
	os.WriteFile(filepath.Join(dir, ".saving-disabled"), nil, 0600)
	result = backupStatusMetrics(repository, "servu")
	for _, expected := range []string{
		`minecraft_backup_last_success_timestamp_seconds{server="servu"} 100`,
		`minecraft_backup_attempt_success{server="servu"} 0`,
		`minecraft_backup_in_progress{server="servu"} 1`,
		`minecraft_backup_saving_disabled{server="servu"} 1`,
	} {
		if !strings.Contains(result, expected) {
			t.Fatal(result)
		}
	}
	for _, data := range []string{`{`, `{}`, `null`} {
		os.WriteFile(file, []byte(data), 0600)
		result = backupStatusMetrics(repository, "servu")
		if !strings.Contains(result, `minecraft_backup_status_collection_success{server="servu"} 0`) {
			t.Fatal(result)
		}
	}
}

func TestFilesystemMetrics(t *testing.T) {
	result := filesystemMetrics(t.TempDir(), "servu")
	for _, name := range []string{"minecraft_filesystem_size_bytes", "minecraft_filesystem_free_bytes", "minecraft_filesystem_avail_bytes"} {
		if !strings.Contains(result, name+`{server="servu"}`) {
			t.Fatal(result)
		}
	}
	if !strings.Contains(result, `minecraft_filesystem_collection_success{server="servu"} 1`) {
		t.Fatal(result)
	}
	result = filesystemMetrics("/definitely-missing-minecraft-exporter-test", "servu")
	if !strings.Contains(result, `minecraft_filesystem_collection_success{server="servu"} 0`) || strings.Contains(result, "minecraft_filesystem_size_bytes") {
		t.Fatal(result)
	}
}

func TestProcessDetails(t *testing.T) {
	fields := make([]string, 22)
	fields[17] = "7"
	fields[19] = "1"
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "io"), []byte("read_bytes: 123\nwrite_bytes: 456\n"), 0600)
	result, err := processDetails(dir, fields, 100, labels("server", "servu"))
	if err != nil {
		t.Fatal(err)
	}
	for _, expected := range []string{`minecraft_process_threads{server="servu"} 7`, `minecraft_process_disk_read_bytes_total{server="servu"} 123`, `minecraft_process_disk_written_bytes_total{server="servu"} 456`} {
		if !strings.Contains(result, expected) {
			t.Fatal(result)
		}
	}
	os.Remove(filepath.Join(dir, "io"))
	result, err = processDetails(dir, fields, 100, labels("server", "servu"))
	if err != nil || !strings.Contains(result, `minecraft_process_io_collection_success{server="servu"} 0`) || !strings.Contains(result, "minecraft_process_uptime_seconds") {
		t.Fatal(result, err)
	}
}
