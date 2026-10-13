package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

func processDetails(dir string, fields []string, ticks float64, ls string) (string, error) {
	var out strings.Builder
	if len(fields) < 22 {
		return "", fmt.Errorf("short proc stat")
	}
	threads, err := strconv.ParseFloat(fields[17], 64)
	if err != nil {
		return "", err
	}
	start, err := strconv.ParseFloat(fields[19], 64)
	if err != nil {
		return "", err
	}
	data, err := os.ReadFile("/proc/uptime")
	if err != nil {
		return "", err
	}
	uptimeFields := strings.Fields(string(data))
	if len(uptimeFields) == 0 {
		return "", fmt.Errorf("empty proc uptime")
	}
	uptime, err := strconv.ParseFloat(uptimeFields[0], 64)
	if err != nil {
		return "", err
	}
	age := uptime - start/ticks
	if age < 0 {
		return "", fmt.Errorf("negative process uptime")
	}
	metric(&out, "minecraft_process_uptime_seconds", age, ls)
	metric(&out, "minecraft_process_threads", threads, ls)
	data, err = os.ReadFile(filepath.Join(dir, "io"))
	metric(&out, "minecraft_process_io_collection_success", boolFloat(err == nil), ls)
	if err == nil {
		for _, line := range strings.Split(string(data), "\n") {
			parts := strings.Fields(line)
			if len(parts) != 2 {
				continue
			}
			name := ""
			switch parts[0] {
			case "read_bytes:":
				name = "minecraft_process_disk_read_bytes_total"
			case "write_bytes:":
				name = "minecraft_process_disk_written_bytes_total"
			}
			if name == "" {
				continue
			}
			value, err := strconv.ParseFloat(parts[1], 64)
			if err != nil {
				return "", err
			}
			metric(&out, name, value, ls)
		}
	}
	return out.String(), nil
}
