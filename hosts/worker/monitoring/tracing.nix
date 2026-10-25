{ config, pkgs, ... }:

let
  ports = config.homelab.ports;
in {
  services.opentelemetry-collector = {
    enable = true;
    package = pkgs.opentelemetry-collector-contrib;
    validateConfigFile = true;
    settings = {
      receivers.otlp.protocols.grpc = {
        endpoint = "127.0.0.1:${toString ports.otelCollector}";
        include_metadata = true;
      };

      processors = {
        memory_limiter = {
          check_interval = "1s";
          limit_percentage = 75;
          spike_limit_percentage = 15;
        };

        "resource/client" = {
          attributes = [
            {
              key = "service.name";
              action = "upsert";
              from_context = "metadata.x-telemetry-client";
            }
            {
              key = "telemetry.client";
              action = "upsert";
              from_context = "metadata.x-telemetry-client";
            }
          ];
        };

        "filter/client" = {
          error_mode = "ignore";
          traces.span = [ ''resource.attributes["telemetry.client"] == nil'' ];
        };

        tail_sampling = {
          decision_wait = "10s";
          num_traces = 10000;
          expected_new_traces_per_sec = 50;
          policies = [
            {
              name = "errors";
              type = "status_code";
              status_code.status_codes = [ "ERROR" ];
            }
            {
              name = "slow";
              type = "latency";
              latency.threshold_ms = 1000;
            }
            {
              name = "food-normal";
              type = "and";
              "and" = {
                and_sub_policy = [
                  {
                    name = "food";
                    type = "string_attribute";
                    string_attribute = {
                      key = "service.name";
                      values = [ "food" ];
                    };
                  }
                  {
                    name = "food-probabilistic";
                    type = "probabilistic";
                    probabilistic.sampling_percentage = 10;
                  }
                ];
              };
            }
          ];
        };

        batch = {
          send_batch_size = 512;
          timeout = "5s";
        };
      };

      exporters."otlp_grpc/victoriatraces" = {
        endpoint = "127.0.0.1:${toString ports.victoriatracesOtlp}";
        tls.insecure = true;
        retry_on_failure.enabled = true;
        sending_queue = {
          enabled = true;
          queue_size = 1000;
        };
      };

      service = {
        pipelines.traces = {
          receivers = [ "otlp" ];
          processors = [ "memory_limiter" "resource/client" "filter/client" "tail_sampling" "batch" ];
          exporters = [ "otlp_grpc/victoriatraces" ];
        };
        telemetry.metrics = {
          level = "basic";
          readers = [{
            pull.exporter.prometheus = {
              host = "127.0.0.1";
              port = ports.otelCollectorMetrics;
            };
          }];
        };
      };
    };
  };
}
