# Erlang NetFlow Aggregator (erlflow)

**erlflow** — a high-performance NetFlow v5 aggregator and analyzer designed to transform raw network flow data into structured, easily analyzable metrics with support for tagging and flexible grouping. This tool reduces the number of time series by grouping flows based on logical rules and integrates seamlessly with monitoring systems like Prometheus.

---

## Key Features

- **NetFlow v5 flow grouping** based on customizable rules
- **Dynamic metric tagging** with support for static and dynamic labels
- **Flexible filtering** by IP, ports, protocols, ToS, and other parameters
- **Automatic scalability** — metrics appear automatically as new nodes join the network
- **Prometheus integration** — ready-to-use metrics for collection and visualization
- **YAML-based configuration** — clear and powerful filtering rules

---

## Use Case Example

### Scenario: Monitoring SIP Infrastructure
A cluster of SIP servers with the following setup:
- **Internal network**: `100.127.0.0/24`
- **External network for clients**: `88.127.127.0/24`
- **Control ports**: TCP 5080
- **Media ports**: UDP 40000–41900

**Goal:**
- Track traffic between servers in pairs
- Aggregate client traffic per server

**Solution with erlflow:**
```yaml
- src_addr:
    match: 100.127.0.0/24
  dst_addr:
    match: 100.127.0.0/24
  proto:
    match: 6
  port:
    match: 5080
  action:
    key_suffix: _sip_srv
    attributes:
      - src_addr
      - dst_addr
    ext_attributes:
      application: SIP
      direction: service-service
```

Instead of thousands of individual flows, you get **12 stable metrics**, such as:

```
netflow_bytes_sent_sip_srv{src_addr="100.127.0.1",dst_addr="100.127.0.2",application="SIP",direction="service-service",sensor="127.0.0.1"}
netflow_bytes_sent_sip_upstream{dst_addr="88.127.127.1",application="SIP",direction="client-service",sensor="127.0.0.1"}
```

---

## Configuration

### Configuration File Format
The default configuration file is `config/config.yml`. The path can be overridden in `sys.config` via the `config_path` parameter.

### Rule Structure
Each rule consists of:
1. **Filtering conditions** — flow parameters and comparison operators
2. **Action** — how to process matching flows

#### Available Operators:
- `match` — matches a value or range
- `dismatch` — does not match

#### Supported Flow Parameters:
| Parameter   | Description                          | Example Value       |
|-------------|--------------------------------------|---------------------|
| `src_addr`  | Source IP address                    | `10.0.0.0/24`       |
| `dst_addr`  | Destination IP address               | `192.168.1.1`       |
| `src_port`  | Source port                          | `5060` or `40000-41000` |
| `dst_port`  | Destination port                     | `5080`              |
| `proto`     | Protocol number (1–252)              | `6` (TCP), `17` (UDP) |
| `tos`       | Type of Service (0–255)              | `0`                 |
| `port`      | Peer-to-peer port identification     | `5060`              |

> **Important:** At least one filtering parameter must be defined in each rule.

### Actions (`action`)
```yaml
action:
  key_suffix: _my_metric      # Required: suffix for the metric name
  attributes:                 # Flow parameters to use as labels
    - src_addr
    - dst_addr
  ext_attributes:             # Static labels
    application: "SIP"
    direction: "internal"
```

If `attributes` are not specified, the following defaults are used:
`src_addr, dst_addr, proto, port, tos`

### Ignoring Flows
```yaml
action: reject
```

> **Warning:** If multiple rules use the same `key_suffix`, their `attributes` and `ext_attributes` must match for Prometheus compatibility.

---

## Output Metric Format

erlflow generates Prometheus-style metrics:

```
netflow_bytes_sent_{suffix}{labels}
netflow_packets_sent_{suffix}{labels}
```

Where:
- `{suffix}` — the suffix from the rule
- `{labels}` — labels from `attributes` and `ext_attributes`, plus the auto-added `sensor` label (NetFlow source address)

---

## Quick Start

1. **Install dependencies** (Erlang/OTP, rebar3)
2. **Clone the repository**:
   ```bash
   git clone https://codeberg.org/ttt161/erlflow.git
   cd erlflow
   ```
3. **Configure rules** in `config/config.yml`
4. **Start the application**:
   ```bash
   rebar3 shell
   ```
5. **Send NetFlow v5 packets** to the default port (2055)
6. **Collect metrics** via the Prometheus endpoint

---

## Advanced Settings

### Ephemeral Port Range
Default: `49152-65535`.
Can be overridden in `sys.config`:
```erlang
{ephemeral_range, {49152, 65535}}
```

### Override Configuration Path
```erlang
{config_path, "/path/to/your/config.yml"}
```

---

## Contributing

We welcome issues, pull requests, and improvement suggestions!
Project hosted on: [https://github.com/ttt161/erlflow](https://github.com/ttt161/erlflow)

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Performance

erlflow is built on Erlang/OTP and leverages:
- **BEAM VM** for parallel flow processing
- **Binary pattern matching** for fast NetFlow packet parsing
- **ETS tables** for efficient state storage
- **Asynchronous processing** for minimal latency

---

### Summary

**erlflow** is ideal for:
- monitoring inter-service traffic
- analyzing network interactions
- integrating network monitoring into observability platforms

The tool transforms raw NetFlow into meaningful business metrics, reducing monitoring complexity and simplifying network infrastructure analysis.
