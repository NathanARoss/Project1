#include "../../includes/linkstate.h"
#include "../../includes/packet.h"

interface NeighborDiscovery{
	command void start();
	command void print();
	command LinkState getOwnLinkstate();
	command uint8_t getNeighborCount();
	command uint16_t* getNeighborIDs();
	command message_t* receive(message_t* myMsg, void* payload, uint8_t len);
}
