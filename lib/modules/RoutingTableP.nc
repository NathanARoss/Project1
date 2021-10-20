#include "../../includes/channels.h"
#include "../../includes/protocol.h"
#include "../../includes/packet.h"

enum
{
	ROUTING_TABLE_REBUILD_DELAY = 10000,
	MAX_LINKS_IN_NETWORK = 1024,
};

typedef struct
{
	uint8_t nextHop;
	uint8_t cost;
} destination_node;

typedef struct
{
	uint16_t src;
	uint16_t dest;
	uint8_t cost;
	uint8_t padding;
} link;

module RoutingTableP
{
	uses interface Timer<TMilli> as rebuildRoutingTableTimer;
	uses interface Hashmap<destination_node> as routingTable;
	uses interface SimpleSend as Sender;
	uses interface NeighborDiscovery;

	provides interface RoutingTable;
}

implementation
{
	uint16_t routingTableFloodSeq = 0;

	link network_links[MAX_LINKS_IN_NETWORK];
	uint16_t receivedLinks = 0;

	void send_pack(uint8_t TTL, uint16_t seq, uint8_t * payload, uint8_t length);
	void Dijkstra();

	command void RoutingTable.start()
	{
		dbg(ROUTING_CHANNEL, "Starting Routing\n");

		call routingTable.reset();
		receivedLinks = 0;

		call NeighborDiscovery.start();
		call rebuildRoutingTableTimer.startPeriodic(ROUTING_TABLE_REBUILD_DELAY);
	}

	command uint16_t RoutingTable.getNextHop(uint16_t dest)
	{
		if (call routingTable.contains(dest))
		{
			return (call routingTable.get(dest)).nextHop;
		}
		else
		{
			return ~0;
		}
	}

	/*
	 * Wipe the routing table and initialize it with only our immediate neighbors
	 *
	 * This assumes we won't receive any ping requests for the duration it
	 * takes to rebuild this table. To avoid this assumption, we'd need to
	 * maintain a 2nd copy of the routing table to use during rebuild.
	 */
	event void rebuildRoutingTableTimer.fired()
	{

		LinkState lsa;
		uint8_t i, reliability;

		lsa = call NeighborDiscovery.getOwnLinkstate();

		// Flood this node's LinkState information across the network.
		// The whole LSA struct fits in the payload of a single packet
		send_pack(MAX_TTL, routingTableFloodSeq, (uint8_t *)&lsa, sizeof(lsa));

		call routingTable.reset();

		// assign the known costs of our immediate neighbors
		for (i = 0; i < lsa.count; ++i)
		{
			reliability = (lsa.reliability >> (i * 3)) & 0b111;
			call routingTable.insert(lsa.neighborIDs[i], (destination_node){
				.nextHop = lsa.neighborIDs[i],
				.cost = reliability + 1, // we treat unreliable links as multiple hops
			});
		}

		// Calculate the non-trivial paths using Dijkstra's algorithm
		Dijkstra();
	}

	command message_t *RoutingTable.receive(message_t * raw_msg, void *payload, uint8_t len)
	{
		LinkState lsa;
		uint32_t i;
		uint16_t nodeID;
		uint8_t reliability;

		pack *msg = (pack *)payload;
		memcpy(&lsa, msg->payload, sizeof(lsa));

		// accumulate the network links into a list
		for (i = 0; i < lsa.count; ++i)
		{
			if (receivedLinks >= MAX_LINKS_IN_NETWORK) {
				dbg(ROUTING_CHANNEL, "Exceeded allocated space for network links\n");
				break;
			}

			nodeID = lsa.neighborIDs[i];
			reliability = (lsa.reliability >> (i*3)) & 0b111;

			network_links[receivedLinks++] = (link){
				.src = TOS_NODE_ID,
				.dest = nodeID,
				.cost = reliability + 1,
			};
		}

		// //if it is in the list
		// if (routingTable[index].cost != ~0) {

		// 	if (routingTable[index].nextHop == msg->src) {
		// 		//update the cost
		// 		if (tempRoutingTable.cost != ~0)
		// 		{
		// 			routingTable[index].cost = tempRoutingTable.cost + 1;
		// 		}
		// 	//if my cost is lower update
		// 	}
		// 	else if ((tempRoutingTable.cost + 1) < routingTable[index].cost)
		// 	{
		// 			routingTable[index].cost = tempRoutingTable.cost + 1;
		// 			routingTable[index].nextHop = msg->src;
		// 	}

		// } else {
		// 	addToRoutingTable(tempRoutingTable.dest, tempRoutingTable.cost, msg->src);

		// }

		return raw_msg;
	}

	command void RoutingTable.print()
	{
		uint32_t i;
		uint16_t nodeCount;
		uint16_t *nodeIDs;
		uint16_t dest;
		destination_node node;

		nodeCount = call routingTable.size();
		nodeIDs = call routingTable.getKeys();

		dbg(ROUTING_CHANNEL, "Node %u Routing Table\n", TOS_NODE_ID);
		dbg(ROUTING_CHANNEL, "Dest | Next | Cost\n");
		dbg(ROUTING_CHANNEL, "==================\n");

		for (i = 0; i < nodeCount; i++)
		{
			dest = nodeIDs[i];
			node = call routingTable.get(dest);

			dbg(ROUTING_CHANNEL, "%4u | %4u | %4u\n", dest, node.nextHop, node.cost);
		}
	}

	void send_pack(uint8_t TTL, uint16_t seq, uint8_t * payload, uint8_t length)
	{
		uint64_t *raw;
		pack packet = {
			.src = TOS_NODE_ID,
			.dest = AM_BROADCAST_ADDR,
			.TTL = TTL,
			.seq = seq,
			.protocol = PROTOCOL_LINKSTATE,
		};

		if (length > sizeof(packet.payload))
		{
			// drop packets that have too large of a payload
			dbg(ROUTING_CHANNEL, "Payload size %u exceeded max payload size %u\n", length, sizeof(packet.payload));
			return;
		}

		if (payload != NULL && length > 0)
		{
			memcpy(packet.payload, payload, length);
		}

		// dbg(ROUTING_CHANNEL, "Flooding LSA{seq=%u,TTL=%u}\n", seq, TTL);
		raw = (uint64_t*)&packet;
		dbg(GENERAL_CHANNEL, "Sending{0x%016lX}\n", *raw);
		call Sender.send(packet, AM_BROADCAST_ADDR);
	}

	/*
	 * Use the list of network edges and the initial route table in Dijksta's
	 * algorithm to calculate optimal paths to all nodes.
	 */
	void Dijkstra()
	{
		// TO-DO
	}
}
