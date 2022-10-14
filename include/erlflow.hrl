-include_lib("netflow/include/netflow_v5.hrl").

-define(FLOW_SIGN(#nfrec_v5{src_addr = SrcAddr, src_port = SrcPort, dst_addr = DstAddr, dst_port = DstPort, prot = Proto,
    tos = Tos, first = StartTimestamp}), {SrcAddr, SrcPort, DstAddr, DstPort, Proto, Tos, StartTimestamp}).

-define(INACTIVITY_TIMEOUT, 300000).