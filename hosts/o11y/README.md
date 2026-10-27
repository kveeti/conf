# o11y

The former `public` host now runs the monitoring stack at `192.168.40.13` on the servers network (VLAN 40). Its SSH identity is unchanged. DMZ/VLAN 66 is retired.

- VictoriaMetrics: 12 months of metrics.
- A separate, unbacked VictoriaMetrics store keeps selected Home Assistant temperature, humidity, and pressure readings for up to 100 years. Grafana exposes it as a separate data source; existing dashboards stay unchanged.
- VictoriaLogs: 90 days of logs.
- VictoriaTraces: 30 days of traces, with the existing OpenTelemetry collector and sampling rules.
- Blackbox probes run here too.

Clients still use `metrics.internal.veetik.com`, `logs.internal.veetik.com`, and `traces.internal.veetik.com` over HTTPS on port 443, with the same credentials.

Grafana stays on `worker`. Its datasource UIDs and dashboards are unchanged. It uses `https://o11y.internal.veetik.com/metrics`, `/logs`, and `/traces/select/jaeger` with separate read-only credentials. Nginx allows only query routes and methods; write, delete, and admin routes are not exposed. All Victoria APIs, the collector, and the OTLP storage receiver bind only to loopback.

The move kept all Victoria history. The stopped source directories remain under `/var/lib/private/victoria*` on `worker`; migration manifests and private checks live under `/var/lib/o11y-migration` on both hosts.

Authentik, PostgreSQL, and their backup timer are retired on this host. Their old data and final backup remain, along with the existing restic repository history on ATX. No old data or images were deleted during the move.
