configuration ForwardingC{
	provides interface Forwarding;
}

implementation{
	components ForwardingP;
	components new SimpleSendC(AM_PACK);
	components new AMReceiverC(AM_PACK);

    components new HashmapC(uint16_t, 1024);
    ForwardingP.seenLinkStateAdvertisements -> HashmapC;
	
	components RoutingTableC;
	ForwardingP.RoutingTable -> RoutingTableC.RoutingTable;

	ForwardingP.Sender -> SimpleSendC;
	ForwardingP.Receive -> AMReceiverC;

	Forwarding = ForwardingP.Forwarding;

	components NeighborDiscoveryC;
	ForwardingP.NeighborDiscovery -> NeighborDiscoveryC.NeighborDiscovery;

	components NodeC;
	ForwardingP.Node -> NodeC.Node;
}
	
