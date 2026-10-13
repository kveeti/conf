package main

import (
	"strings"
	"syscall"
)

// The server directory is on /home. Measure from this service's real mount
// namespace, independently of node exporter's ProtectHome setting.
func filesystemMetrics(path, server string) string {
	var out strings.Builder
	ls := labels("server", server)
	var fs syscall.Statfs_t
	err := syscall.Statfs(path, &fs)
	metric(&out, "minecraft_filesystem_collection_success", boolFloat(err == nil), ls)
	if err == nil {
		block := float64(fs.Bsize)
		metric(&out, "minecraft_filesystem_size_bytes", float64(fs.Blocks)*block, ls)
		metric(&out, "minecraft_filesystem_free_bytes", float64(fs.Bfree)*block, ls)
		metric(&out, "minecraft_filesystem_avail_bytes", float64(fs.Bavail)*block, ls)
	}
	return out.String()
}
