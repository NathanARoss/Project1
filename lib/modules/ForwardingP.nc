#include "../../includes/channels.h"
#include "../../includes/protocol.h"
#include "../../includes/packet.h"

module ForwardingP
{
	uses interface SimpleSend as Sender;
	uses interface Receive;
	uses interface Node;
	uses interface Flooding;
	uses interface RoutingTable;
	uses interface NeighborDiscovery;
	
	provides interface Forwarding;
}

implementation
{
	command error_t Forwarding.send(pack msg, uint16_t dest)
	{
		uint16_t nextHop;
		nextHop = call RoutingTable.getNextHop(dest);

		if (nextHop == ~0)
		{
			dbg(ROUTING_CHANNEL, "Missing next hop for destination %u \n", dest);
			return FAIL;
		}
		else
		{
			// dbg(ROUTING_CHANNEL, "Forwarding packet for %u through %u\n", dest, nextHop);
			return call Sender.send(msg, nextHop);
		}
	}

	event message_t *Receive.receive(message_t * msg, void *payload, uint8_t len)
	{
		pack *myMsg = (pack *)payload;
		// dbg(ROUTING_CHANNEL, "Received{dest=%u,src=%u,seq=%u,TTL=%u,protocol=%u}\n", myMsg->dest, myMsg->src, myMsg->seq, myMsg->TTL, myMsg->protocol);
		uint64_t *raw = (uint64_t*)&msg;
      	dbg(GENERAL_CHANNEL, "Received{0x%016lX}\n", *raw);

		if (myMsg->dest == TOS_NODE_ID)
		{
			// packet is intended for *this* node
			switch (myMsg->protocol) {
				case PROTOCOL_LINKSTATE:
					return call RoutingTable.receive(msg, payload, len);

				case PROTOCOL_NEIGHBOR_DISCOVERY:
					return call NeighborDiscovery.receive(msg, payload, len);

				default:
					return call Node.receive(msg, payload, len);
			}
		}
		else if (myMsg->dest == AM_BROADCAST_ADDR)
		{
			if (myMsg->protocol == PROTOCOL_NEIGHBOR_DISCOVERY) {
				// packet is just a node reaching out to its unknown neighbors
				return call NeighborDiscovery.receive(msg, payload, len);
			} else {
				// packet is intended to flood
				return call Flooding.receive(msg, payload, len);
			}
		}
		else
		{
			// packet is intended for a single node. Attempt to route it
			if (myMsg->TTL == 0)
			{
				dbg(ROUTING_CHANNEL, "Packet intended for %u aged out \n", myMsg->dest);
				return msg;
			}

			myMsg->TTL -= 1;
			call Forwarding.send(*myMsg, myMsg->dest);
		}

		return msg;
	}
}
