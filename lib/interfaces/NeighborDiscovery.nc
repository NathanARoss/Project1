#include "../../includes/linkstate.h"
#include "../../includes/packet.h"

interface NeighborDiscovery{
	command void start();
	command void print();
	command LinkState getOwnLinkstate();
	command message_t* receive(message_t* myMsg, void* payload, uint8_t len);
}
