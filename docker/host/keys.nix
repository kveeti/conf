let
  keys = {
    veeti = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPgUQ+IBuwDbO0eVmuk9cLDxUAJ5fly7jqUYoiBugo2f";

    servu = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIADw5NEVcz6MIXYJZ+rRtjKE0v9sk965YSg1gA2hGT+7 servu";
  };
in keys // {
  admins = [ keys.veeti ];
  all = [ keys.veeti keys.servu ];
}
