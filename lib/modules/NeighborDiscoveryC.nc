configuration NeighborDiscoveryC{
	provides interface NeighborDiscovery;
}

implementation{
	components NeighborDiscoveryP;

	components new TimerMilliC() as neighborDiscoveryTimer;
	components new SimpleSendC(AM_PACK);

    components new HashmapC(uint16_t, 64);
    NeighborDiscoveryP.neighborTable -> HashmapC;
	
	NeighborDiscovery = NeighborDiscoveryP.NeighborDiscovery;

	NeighborDiscoveryP.Sender -> SimpleSendC;
	NeighborDiscoveryP.neighborDiscoveryTimer -> neighborDiscoveryTimer;

} 
