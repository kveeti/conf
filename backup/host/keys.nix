let
  keys = {
    veeti = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPgUQ+IBuwDbO0eVmuk9cLDxUAJ5fly7jqUYoiBugo2f";

    backup = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGvNqExxnOumO559hqnwELAP/30hK4Mt93V1RgOf7CWv backup";
    servu = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIADw5NEVcz6MIXYJZ+rRtjKE0v9sk965YSg1gA2hGT+7 servu";
  };
in keys // {
  admins = [ keys.veeti ];
  all = [ keys.veeti keys.backup keys.servu ];
}
