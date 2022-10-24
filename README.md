# erlflow

Simple netflow data to prometheus metrics converter and pre-analyzer

Description
=====

erlflow is designed to monitor network interactions and group information from multiple netflow packets into specific 
metrics according to the rules specified in the configuration

Formulation of the problem
=====

In the netflow protocol (hereinafter referred to as netflow v5), a stream is a short-lived entity that is uniquely 
identified by the following parameters:
- source address
- destination address
- source port
- destination port
- protocol number
- type of service
- first packet timestamp

Obviously, with regular interaction of the same network entities (for example services) the timestamp of the first 
packet and one of the interaction ports (as a rule) will always change. Even if you omit the timestamp and simply map 
the rest of the stream parameters to metric labels, a lot of timeseries will be created, which creates inconvenience 
during further processing of information. It is more convenient to introduce the concept of "direction of interaction" 
which can combine the data of many network flows.

Example: 
Let's say there is a network of several SIP servers. The servers interact over the "internal" network 100.127.0.0/24,
to establish communication with each other use the TCP protocol and port 5080 and for media traffic use UDP and port range
40000-41900. Clients establish connections to "external" addresses (for example, 88.127.127.0/24) and UDP port 5060, 
for media traffic use UDP protocol and port range 40000-40100.
Goal: monitor the network load for all inter-server connections in pairs, summarize the load from clients for each 
server separately.

![scheme](https://codeberg.org/ttt161/erlflow/raw/branch/master/pic/scheme.png)

Solution
=====

To solve the problem we need to describe the rules for filtering (grouping) flows, and the rules for generating labels 
for metrics.

The filter for interserver communication is described by the following set of conditions:
```
src_addr=100.127.0.0/24 dst_addr=100.127.0.0/24 proto=tcp port=5080 (параметр port описан ниже)
src_addr=100.127.0.0/24 dst_addr=100.127.0.0/24 proto=udp src_port=40000-41900 dst_port=40000-41900
```
To save statistics of transmitted packets/bytes from many network streams in one metric, we must save significant parameters 
(src_addr, dst_addr) and exclude dynamically changing ones (proto, port, src_port, dst_port, tos). 
Instead of the excluded parameters, you need to add an additional label (or labels) that will allow you to identify 
the metric as an interaction of SIP servers, for example, application="SIP",direction="service-service".

Filter for client -> server interaction:
```
src_addr!=88.127.127.0/24 dst_addr=88.127.127.0/24 proto=udp dst_port=5060
src_addr!=88.127.127.0/24 dst_addr=88.127.127.0/24 proto=udp src_port=40000-41900 dst_port=40000-41900
```
Significant parameters: dst_addr. Additional labels: application="SIP",direction="client-service"

Filter for server -> client interaction:
```
src_addr=88.127.127.0/24 dst_addr!=88.127.127.0/24 proto=udp src_port=5060
src_addr=88.127.127.0/24 dst_addr!=88.127.127.0/24 proto=udp src_port=40000-41900 dst_port=40000-41900
```
Significant parameters: src_addr. Additional labels: application="SIP",direction="service-client"

Implementation
=====

Filtering and tagging rules are specified in the config/config.yml file (the path can be overridden in sys.config via 
the config_path parameter; see the detailed description of the configuration file below). For the example above, 
config.yml looks like this:
```yml
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

- src_addr:
    match: 100.127.0.0/24
  dst_addr:
    match: 100.127.0.0/24
  proto:
    match: 17
  src_port:
    match: 40000-41900
  dst_port:
    match: 40000-41900
  action:
    key_suffix: _sip_srv
    attributes:
      - src_addr
      - dst_addr
    ext_attributes:
      application: SIP
      direction: service-service

- src_addr:
    dismatch: 88.127.127.0/24
  dst_addr:
    match: 88.127.127.0/24
  proto:
    match: 6
  port:
    match: 5060
  action:
    key_suffix: _sip_upstream
    attributes:
      - dst_addr
    ext_attributes:
      application: SIP
      direction: client-service

- src_addr:
    dismatch: 88.127.127.0/24
  dst_addr:
    match: 88.127.127.0/24
  proto:
    match: 17
  src_port:
    match: 40000-41900
  dst_port:
    match: 40000-41900
  action:
    key_suffix: _sip_upstream
    attributes:
      - dst_addr
    ext_attributes:
      application: SIP
      direction: client-service

- src_addr:
    match: 88.127.127.0/24
  dst_addr:
    dismatch: 88.127.127.0/24
  proto:
    match: 6
  src_port:
    match: 5060
  action:
    key_suffix: _sip_downstream
    attributes:
      - src_addr
    ext_attributes:
      application: SIP
      direction: service-client

- src_addr:
    match: 88.127.127.0/24
  dst_addr:
    dismatch: 88.127.127.0/24
  proto:
    match: 17
  src_port:
    match: 40000-41900
  dst_port:
    match: 40000-41900
  action:
    key_suffix: _sip_downstream
    attributes:
      - src_addr
    ext_attributes:
      application: SIP
      direction: service-client
```
For our example, the erlflow will create 12 timeseries with keys netflow_bytes_sent$KEY_SUFFIX and 12 with keys 
netflow_packets_sent$KEY_SUFFIX, regardless of how many parallel connections the servers establish between themselves 
and how many client connections exist. Example for bytes metric:
````
netflow_bytes_sent_sip_srv{src_addr="100.127.0.1",dst_addr="100.127.0.2",application="SIP",direction="service-service",sensor="127.0.0.1"}
netflow_bytes_sent_sip_srv{src_addr="100.127.0.1",dst_addr="100.127.0.3",application="SIP",direction="service-service",sensor="127.0.0.1"}
netflow_bytes_sent_sip_srv{src_addr="100.127.0.2",dst_addr="100.127.0.1",application="SIP",direction="service-service",sensor="127.0.0.1"}
netflow_bytes_sent_sip_srv{src_addr="100.127.0.2",dst_addr="100.127.0.3",application="SIP",direction="service-service",sensor="127.0.0.1"}
netflow_bytes_sent_sip_srv{src_addr="100.127.0.3",dst_addr="100.127.0.1",application="SIP",direction="service-service",sensor="127.0.0.1"}
netflow_bytes_sent_sip_srv{src_addr="100.127.0.3",dst_addr="100.127.0.2",application="SIP",direction="service-service",sensor="127.0.0.1"}

netflow_bytes_sent_sip_upstream{dst_addr="88.127.127.1",application="SIP",direction="client-service",sensor="127.0.0.1"}
netflow_bytes_sent_sip_upstream{dst_addr="88.127.127.2",application="SIP",direction="client-service",sensor="127.0.0.1"}
netflow_bytes_sent_sip_upstream{dst_addr="88.127.127.3",application="SIP",direction="client-service",sensor="127.0.0.1"}

netflow_bytes_sent_sip_downstream{src_addr="88.127.127.1",application="SIP",direction="service-client",sensor="127.0.0.1"}
netflow_bytes_sent_sip_downstream{src_addr="88.127.127.2",application="SIP",direction="service-client",sensor="127.0.0.1"}
netflow_bytes_sent_sip_downstream{src_addr="88.127.127.3",application="SIP",direction="service-client",sensor="127.0.0.1"}
````
Note! Erlflow has added the label sensor with the value ipv4 address.

![metrics](https://codeberg.org/ttt161/erlflow/raw/branch/master/pic/metrics.png)

Description of the configuration file
====

The default configuration file is config/config.yml (the path can be overridden in sys.config via the config_path parameter). 
It consists of a list of rules for processing network flows. netflow packet is compared against each rule in order from 
first to last and processed according to the first matched rule. If the flow parameters do not match any of the rules, 
then the stream is ignored.

The rule contains the names of the network flow parameters with conditions for comparison and a description of the action 
if the flow parameters match the specified conditions.
````
 ParamName:
   Operator: Value
````
Operator defines how to compare the value of the flow parameter with the given Value. To compare for a match Operator -
match, to compare for a mismatch - dismatch.

Processed network flow parameters:
- src_addr, source address, in the condition, you can compare the address for a match or mismatch with the ipv4 prefix
Example:
````
 src_addr:
   match: 10.0.0.0/24
````
- dst_addr, destination address, the condition is set similarly to src_addr
- src_port, source port, the condition can take one value or a range, must be in the range 1-65535
- dst_port, destination port, similar to src_port
- port, alternative way to check the port number for peer-to-peer interactions, when the target port can belong not only 
to the server, but to any of the interacting parties. Calculated as follows: if min(src_port, dst_port) < min(ephemeral_ports)
then port=min(src_port, dst_port) else port=0. The default dynamic (ephemeral) port range is 49152-65535, but can be 
overridden in sys.config using the ephemeral_range parameter ({ephemeral_range, {49152, 65535}}). The condition is set 
similarly to src_port, dst_port
- proto, protocol number (1-252)
- tos, type of service (0-255)

NOTE! The rule must contain a condition for at least one flow parameter!

The action determines in which metric the number of bytes/packets transmitted in the flow will be stored. To do this, 
you must specify a suffix for the metric key, define a list of flow parameters that will be mapped to metric labels, and
specify additional labels. Only the suffix for the metric key is required.
Example:
````
 action:
   key_suffix: _some_string
   attributes:
     - src_addr
     - dst_addr
   ext_attributes:
     label: value
````
If attributes are not defined, then the following parameters will be used by default: src_addr, dst_addr, proto, port, tos.

IMPORTANT!!! If you specify the same key_suffix for multiple rules, then the values of attributes and ext_attributes in 
those rules must not differ. If this is not done, then the prometheus library will not be able to correctly process such 
metrics.

Also, action can take the value reject:
````
 action: reject
````
In this case, the flow information will be ignored.