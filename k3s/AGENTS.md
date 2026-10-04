- We use GitOps (Flux). Manifests are under `clusters/dev/`.
- Three k3s server nodes on VLAN 50 (`192.168.50.0/24`):
- kube-vip assigns external LoadBalancer IPs from `192.168.50.10–192.168.50.31`.
  `.8` and `.9` are reserved for the ingress controllers.

| Kubernetes node | Hostname | Cluster IP | Where it runs / config |
| --- | --- | --- | --- |
| control1 | public | 192.168.50.5 | Physical host; `hosts/public/` |
| control2 | backup | 192.168.50.6 | Physical host; `hosts/backup/` |
| control3 | control3 | 192.168.50.7 | MicroVM on ATX; `hosts/atx/control3.nix` |

- Apps run on control1/control2. Control3 is tainted against normal workloads.
- ATX is `192.168.40.10`. It also hosts the storage and backup MicroVMs below.

## Storage

- `storage` (`192.168.50.3`) is a MicroVM on ATX, not a Kubernetes node.
  Config: `hosts/atx/storage-vm.nix`.
- Its ZFS pool lives on `/var/lib/microvms/storage/data.img` on ATX.
- App disks use democratic-csi, ZFS zvols and mutual-CHAP iSCSI. Datasets live
  under `storage/mutual-chap/volumes`; detached snapshots under
  `storage/mutual-chap/snapshots`.
- CSI manages targets over SSH. Its Secret supplies both target and node login
  credentials. The storage firewall only allows iSCSI from control1/control2.
- App deployments that need a disk use democratic-csi. CNPG databases use
  `local-path` on control1/control2, with database replication.
- App disk backups use VolSync/restic; database backups use CNPG.
- `backup-vm` (`192.168.50.4`) runs Garage on ATX. Config:
  `hosts/atx/backup-vm.nix`.

## Networking and config

- Public Envoy: `192.168.50.8`. Internal Envoy: `192.168.50.9`.
  We use shared Gateway API Gateways with per-host certificates in the ingress
  namespaces. Router config forwards public TCP 80/443 to public Envoy;
  deploy the router config separately.
- Envoy Gateway controllers run separately in `public-gateway-system` and
  `internal-gateway-system`, with scoped RBAC. Proxy pods have no Secret-read
  permissions and cannot reach the Kubernetes API or databases.
- Apps have restricted pods and default-deny networking. Shared rules live in
  `clusters/dev/apps/app-security/`.
- Secrets use SOPS + age (`.sops.yaml` in the repo root).
- Addresses: `inventory.nix`. Shared k3s config: `modules/services/k3s-server.nix`.
