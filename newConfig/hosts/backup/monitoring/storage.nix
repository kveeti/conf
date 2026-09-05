{ ... }:

{
  services.victoriametrics = {
    enable = true;
    listenAddress = "127.0.0.1:18428";
    stateDir = "victoriametrics";
    retentionPeriod = "12";
  };

  services.victorialogs = {
    enable = true;
    listenAddress = "127.0.0.1:19428";
    stateDir = "victorialogs";
    extraOptions = [ "-retentionPeriod=90d" ];
  };
}
