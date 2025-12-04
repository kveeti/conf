let
  keys = {
    veeti = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPgUQ+IBuwDbO0eVmuk9cLDxUAJ5fly7jqUYoiBugo2f";

    router = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO3xJd0m0H3StZkKZn6yjP23FwmDA2D505l4nlt9xVIj router";
  };
in keys // {
  admins = [ keys.veeti ];
  all = [ keys.veeti keys.router ];
}
