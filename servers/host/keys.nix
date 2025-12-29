let
  keys = {
    veeti = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPgUQ+IBuwDbO0eVmuk9cLDxUAJ5fly7jqUYoiBugo2f";

    servers = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGpfopQx4xX67kabI0swXa2s2ACs+VVi+5phBiu+SrDJ servers";
  };
in keys // {
  admins = [ keys.veeti ];
  all = [ keys.veeti keys.servers ];
}
