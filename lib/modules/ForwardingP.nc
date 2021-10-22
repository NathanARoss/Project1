#include "../../includes/channels.h"
#include "../../includes/protocol.h"
#include "../../includes/packet.h"

module ForwardingP
{
	uses interface Hashmap<uint16_t> as seenLinkStateAdvertisements;
	uses interface SimpleSend as Sender;
	uses interface Receive;
	uses interface Node;
	uses interface RoutingTable;
	uses interface NeighborDiscovery;

	provides interface Forwarding;
}

implementation
{
	command void Forwarding.start()
	{
		call RoutingTable.start();

		call seenLinkStateAdvertisements.reset();
	}

	command error_t Forwarding.send(pack *payload)
	{
		uint16_t nextHop = call RoutingTable.getNextHop(payload->dest);

		if (nextHop == ~0)
		{
			dbg(ROUTING_CHANNEL, "Missing next hop for destination %u \n", payload->dest);
			return FAIL;
		}
		else
		{
			dbg(ROUTING_CHANNEL, "Routing packet for %u through %u\n", payload->dest, nextHop);
			return call Sender.send(*payload, nextHop);
		}
	}

	bool hasSeenLSA(uint16_t src, uint16_t seq)
	{
		uint16_t seen_seq;

		if (TOS_NODE_ID == src)
		{
			return TRUE;
		}

		if (call seenLinkStateAdvertisements.contains(src) == FALSE)
		{
			return FALSE;
		}

		seen_seq = call seenLinkStateAdvertisements.get(src);
		return (seq <= seen_seq);
	}

	void recordLSA(uint16_t src, uint16_t seq)
	{
		call seenLinkStateAdvertisements.insert(src, seq);
	}

	event message_t *Receive.receive(message_t * msg, void *payload, uint8_t len)
	{
		pack *packet = (pack *)payload;
		uint16_t src = packet->src;
		uint16_t dest = packet->dest;
		uint16_t seq = packet->seq;
		uint8_t TTL = packet->TTL;
		uint8_t protocol = packet->protocol;
		uint16_t link_src = packet->link_src;

		// dbg(ROUTING_CHANNEL, "Received{dest=%u,src=%u,seq=%u,TTL=%u,protocol=%u,link_src=%u}\n", dest, src, seq, TTL, protocol, link_src);

		if (dest == TOS_NODE_ID)
		{
			// packet is intended for *this* node
			switch (protocol)
			{
			case PROTOCOL_NEIGHBOR_DISCOVERY:
				return call NeighborDiscovery.receive(msg, payload, len);

			default:
				return call Node.receive(msg, payload, len);
			}
		}
		else if (dest == AM_BROADCAST_ADDR)
		{
			if (protocol == PROTOCOL_NEIGHBOR_DISCOVERY)
			{
				// packet is just a node reaching out to its unknown neighbors
				return call NeighborDiscovery.receive(msg, payload, len);
			}
			else if (protocol == PROTOCOL_LINKSTATE)
			{
				error_t error;
				uint16_t neighborCount;
				uint16_t *neighborIDs;
				uint8_t i;

				// packet is a LinkState Advertisement (LSA) that needs to flood the network
				if (hasSeenLSA(src, seq))
				{
					// dbg(FLOODING_CHANNEL, "Discarding repeated LSA packet from node %u seq %u\n", src, seq);
					return msg;
				}

				recordLSA(src, seq);

				// allow the routing table to view this LSA before we forward it
				call RoutingTable.receive(msg, payload, len);

				if (TTL == 0)
				{
					dbg(FLOODING_CHANNEL, "Flooding packet from node %u expired \n", src);
					return msg;
				}

				packet->TTL = TTL - 1;
				packet->link_src = TOS_NODE_ID;

				/* 
				 * flood message to all neighbors except the one we received the
				 * flood packet from
				 */
				neighborCount = call NeighborDiscovery.getNeighborCount();
				neighborIDs = call NeighborDiscovery.getNeighborIDs();

				for (i = 0; i < neighborCount; i++)
				{
					if (neighborIDs[i] != link_src)
					{
						// dbg(FLOODING_CHANNEL, "Flooding node %u's LSA packet #%u to node %u\n", src, seq, neighborIDs[i]);
						error = call Sender.send(*packet, neighborIDs[i]);

						if (error != SUCCESS)
						{
							dbg(GENERAL_CHANNEL, "Failed to flood node #%u's LSA w/ seq %u \n", src, seq);
						}
					}
				}

				return msg;
			}
			else
			{
				dbg(ROUTING_CHANNEL, "Received flooding packet with unexpected protocol %u \n", protocol);
			}
		}
		else
		{
			// packet is intended for a single node. Attempt to route it
			if (TTL == 0 && protocol != PROTOCOL_NEIGHBOR_DISCOVERY)
			{
				// we expect neighbor discovery packets to age out because they are sent with a TTL of 0
				dbg(ROUTING_CHANNEL, "Packet intended for %u aged out \n", dest);
				return msg;
			}

			packet->TTL = TTL - 1;
			call Forwarding.send(packet);
		}

		return msg;
	}
}
