# o11y

The former `public` host now runs the monitoring stack at `192.168.40.13` on the servers network (VLAN 40). Its SSH identity is unchanged. DMZ/VLAN 66 is retired.

- VictoriaMetrics: 12 months of metrics.
- VictoriaLogs: 90 days of logs.
- VictoriaTraces: 30 days of traces, with the existing OpenTelemetry collector and sampling rules.
- Blackbox probes run here too.

Clients still use `metrics.internal.veetik.com`, `logs.internal.veetik.com`, and `traces.internal.veetik.com` over HTTPS on port 443, with the same credentials.

Grafana stays on `worker`. Its datasource UIDs and dashboards are unchanged. It reaches Victoria's HTTP APIs on ports 18428, 19428, and 19429; the host firewall allows only `worker` to reach those ports. The collector and OTLP storage receiver remain on loopback.

The move kept all Victoria history. The stopped source directories remain under `/var/lib/private/victoria*` on `worker`; migration manifests and private checks live under `/var/lib/o11y-migration` on both hosts.

Authentik, PostgreSQL, and their backup timer are retired on this host. Their old data and final backup remain, along with the existing restic repository history on ATX. No old data or images were deleted during the move.
