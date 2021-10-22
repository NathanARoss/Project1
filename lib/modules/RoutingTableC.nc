configuration RoutingTableC{
	provides interface RoutingTable;
}

implementation{
	components RoutingTableP;
	components new TimerMilliC() as rebuildRoutingTableTimer;
	components new SimpleSendC(AM_PACK);

    components new HashmapC(destination_node, 1024) as RoutingTableC;
    RoutingTableP.routingTable -> RoutingTableC;

    components new HashmapC(destination_node, 1024) as UnvisitedNodesC;
    RoutingTableP.unvisitedNodes -> UnvisitedNodesC;

	components NeighborDiscoveryC;
	RoutingTableP.NeighborDiscovery -> NeighborDiscoveryC;
	
	RoutingTable = RoutingTableP.RoutingTable;

	RoutingTableP.Sender -> SimpleSendC;
	RoutingTableP.rebuildRoutingTableTimer -> rebuildRoutingTableTimer;
}
