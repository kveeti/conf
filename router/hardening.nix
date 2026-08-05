{ ... }:

{
  boot.kernel.sysctl = {
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
    "kernel.kexec_load_disabled" = 1;
    "kernel.unprivileged_bpf_disabled" = 2;
    "net.core.bpf_jit_harden" = 2;
    "kernel.perf_event_paranoid" = 3;
    "kernel.sysrq" = 0;
    "kernel.randomize_va_space" = 2;
    "kernel.yama.ptrace_scope" = 1;
  };

  security.protectKernelImage = true;
  security.forcePageTableIsolation = true;

  boot.blacklistedKernelModules = [
    "dccp"
    "rds"
    "sctp"
    "tipc"
  ];
}
