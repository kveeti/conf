package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
)

// Small atomic status file: refresh with player/process metrics, not with du.
func backupStatusMetrics(repository, server string) string {
	var out strings.Builder
	ls := labels("server", server)
	statusData, statusErr := os.ReadFile(filepath.Join(filepath.Dir(repository), ".monitoring.json"))
	var status struct {
		LastAttempt *float64 `json:"last_attempt"`
		LastSuccess *float64 `json:"last_success"`
		Duration    *float64 `json:"duration"`
		Success     *bool    `json:"success"`
		InProgress  *bool    `json:"in_progress"`
	}
	if statusErr == nil {
		statusErr = json.Unmarshal(statusData, &status)
	}
	if statusErr == nil && status.LastAttempt == nil {
		statusErr = os.ErrInvalid
	}
	metric(&out, "minecraft_backup_status_collection_success", boolFloat(statusErr == nil), ls)
	if statusErr == nil {
		metric(&out, "minecraft_backup_last_attempt_timestamp_seconds", *status.LastAttempt, ls)
		if status.LastSuccess != nil {
			metric(&out, "minecraft_backup_last_success_timestamp_seconds", *status.LastSuccess, ls)
		}
		if status.Duration != nil {
			metric(&out, "minecraft_backup_duration_seconds", *status.Duration, ls)
		}
		if status.Success != nil {
			metric(&out, "minecraft_backup_attempt_success", boolFloat(*status.Success), ls)
		}
		if status.InProgress != nil {
			metric(&out, "minecraft_backup_in_progress", boolFloat(*status.InProgress), ls)
		}
	}
	_, err := os.Stat(filepath.Join(filepath.Dir(repository), ".saving-disabled"))
	if err == nil || os.IsNotExist(err) {
		metric(&out, "minecraft_backup_saving_disabled", boolFloat(err == nil), ls)
	}
	return out.String()
}
