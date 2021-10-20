configuration FloodingC{
	provides interface Flooding;
}

implementation{
	components FloodingP;
	components new SimpleSendC(AM_PACK);
	
	FloodingP.Sender -> SimpleSendC;

	Flooding = FloodingP.Flooding;
} 
