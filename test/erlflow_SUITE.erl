-module(erlflow_SUITE).

%% API
-export([
    init_per_suite/1,
    end_per_suite/1,
    all/0
]).

-export([
    test/1
]).

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

all() -> [
    test
].

test(_Config) ->
    {_, Socket, _} = sys:get_state(erlflow),
    Pid = whereis(erlflow),
    %% Vector 1, flow 1
    V1F1_1 = <<
        0,5,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, %% header
        10,0,0,1, %% src_addr
        10,0,0,254, %% dst_addr
        0,0,0,0,0,0,0,0,
        0,0,0,3, %% packets
        0,0,0,27, %% octets
        0,0,0,0,255,255,0,0,0,0,255,0,0,0,17,0,0,0,255,0,0,0,0,0
    >>,
    V1F1_2 = <<
        0,5,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, %% header
        10,0,0,1, %% src_addr
        10,0,0,254, %% dst_addr
        0,0,0,0,0,0,0,0,
        0,0,0,4, %% packets
        0,0,0,33, %% octets
        0,0,0,0,255,255,0,0,0,0,255,0,0,0,17,0,0,0,255,0,0,0,0,0
    >>,
    V1F1_3 = <<
        0,5,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, %% header
        10,0,0,1, %% src_addr
        10,0,0,254, %% dst_addr
        0,0,0,0,0,0,0,0,
        0,0,0,7, %% packets
        0,0,0,128, %% octets
        0,0,0,0,255,255,0,0,0,0,255,0,0,0,17,0,0,0,255,0,0,0,0,0
    >>,

    %% Vector 1, flow 2
    V1F2_1 = <<
        0,5,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, %% header
        10,0,0,2, %% src_addr
        10,0,0,254, %% dst_addr
        0,0,0,0,0,0,0,0,
        0,0,0,5, %% packets
        0,0,0,50, %% octets
        0,0,0,0,255,255,0,0,0,0,255,0,0,0,17,0,0,0,255,0,0,0,0,0
    >>,
    V1F2_2 = <<
        0,5,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, %% header
        10,0,0,2, %% src_addr
        10,0,0,254, %% dst_addr
        0,0,0,0,0,0,0,0,
        0,0,0,7, %% packets
        0,0,0,71, %% octets
        0,0,0,0,255,255,0,0,0,0,255,0,0,0,17,0,0,0,255,0,0,0,0,0
    >>,

    %% Vector 2, flow 1
    V2F1_1 = <<
        0,5,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, %% header
        11,0,0,1, %% src_addr
        11,0,0,248, %% dst_addr
        0,0,0,0,0,0,0,0,
        0,0,0,4, %% packets
        0,0,0,42, %% octets
        0,0,0,0,255,255,0,0,0,0,255,0,0,0,17,0,0,0,255,0,0,0,0,0
    >>,
    V2F1_2 = <<
        0,5,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, %% header
        11,0,0,1, %% src_addr
        11,0,0,248, %% dst_addr
        0,0,0,0,0,0,0,0,
        0,0,0,12, %% packets
        0,0,0,88, %% octets
        0,0,0,0,255,255,0,0,0,0,255,0,0,0,17,0,0,0,255,0,0,0,0,0
    >>,

    %% Vector 2, flow 2
    V2F2_1 = <<
        0,5,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, %% header
        11,0,0,1, %% src_addr
        11,0,0,249, %% dst_addr
        0,0,0,0,0,0,0,0,
        0,0,0,4, %% packets
        0,0,0,42, %% octets
        0,0,0,0,255,255,0,0,0,0,255,0,0,0,17,0,0,0,255,0,0,0,0,0
    >>,
    V2F2_2 = <<
        0,5,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, %% header
        11,0,0,1, %% src_addr
        11,0,0,249, %% dst_addr
        0,0,0,0,0,0,0,0,
        0,0,0,12, %% packets
        0,0,0,88, %% octets
        0,0,0,0,255,255,0,0,0,0,255,0,0,0,17,0,0,0,255,0,0,0,0,0
    >>,

    Pid ! {udp, Socket, <<127,0,0,1>>, 9999, V1F1_1},
    Pid ! {udp, Socket, <<127,0,0,1>>, 9999, V1F1_3},
    timer:sleep(150),
    [{[{dst_addr,"10.0.0.254"},{sensor,"127.0.0.1"}],128}] = prometheus_counter:values(erlflow, netflow_bytes_sent_vector1),
    [{[{dst_addr,"10.0.0.254"},{sensor,"127.0.0.1"}],7}] = prometheus_counter:values(erlflow, netflow_packets_sent_vector1),

    Pid ! {udp, Socket, <<127,0,0,1>>, 9999, V2F1_1},
    Pid ! {udp, Socket, <<127,0,0,1>>, 9999, V2F2_1},
    Pid ! {udp, Socket, <<127,0,0,1>>, 9999, V1F1_2}, %% must be ignored
    timer:sleep(150),

    [{[{dst_addr,"10.0.0.254"},{sensor,"127.0.0.1"}],128}] = prometheus_counter:values(erlflow, netflow_bytes_sent_vector1),
    [{[{dst_addr,"10.0.0.254"},{sensor,"127.0.0.1"}],7}] = prometheus_counter:values(erlflow, netflow_packets_sent_vector1),

    [{[{sensor,"127.0.0.1"},{src_addr,"11.0.0.1"}],84}] = prometheus_counter:values(erlflow, netflow_bytes_sent_vector2),
    [{[{sensor,"127.0.0.1"},{src_addr,"11.0.0.1"}],8}] = prometheus_counter:values(erlflow, netflow_packets_sent_vector2),

    Pid ! {udp, Socket, <<127,0,0,1>>, 9999, V1F2_1},
    Pid ! {udp, Socket, <<127,0,0,1>>, 9999, V1F2_2},
    Pid ! {udp, Socket, <<127,0,0,1>>, 9999, V2F1_2},
    Pid ! {udp, Socket, <<127,0,0,1>>, 9999, V2F2_2},
    timer:sleep(150),

    [{[{dst_addr,"10.0.0.254"},{sensor,"127.0.0.1"}],199}] = prometheus_counter:values(erlflow, netflow_bytes_sent_vector1),
    [{[{dst_addr,"10.0.0.254"},{sensor,"127.0.0.1"}],14}] = prometheus_counter:values(erlflow, netflow_packets_sent_vector1),

    [{[{sensor,"127.0.0.1"},{src_addr,"11.0.0.1"}],176}] = prometheus_counter:values(erlflow, netflow_bytes_sent_vector2),
    [{[{sensor,"127.0.0.1"},{src_addr,"11.0.0.1"}],24}] = prometheus_counter:values(erlflow, netflow_packets_sent_vector2).
