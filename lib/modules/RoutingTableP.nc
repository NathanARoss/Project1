#include "../../includes/channels.h"
#include "../../includes/protocol.h"
#include "../../includes/packet.h"

enum
{
	ROUTING_TABLE_REBUILD_DELAY = 5000,
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
	uses interface Hashmap<destination_node> as unvisitedNodes;
	uses interface SimpleSend as Sender;
	uses interface NeighborDiscovery;

	provides interface RoutingTable;
}

implementation
{
	uint16_t routingTableFloodSeq = 0;

	link network_links[MAX_LINKS_IN_NETWORK];
	uint16_t receivedLinks = 0;

	command void RoutingTable.start()
	{
		// dbg(ROUTING_CHANNEL, "Starting Routing\n");

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
		LinkState lsa = call NeighborDiscovery.getOwnLinkstate();
		uint8_t i;
		error_t error;
		uint16_t fail_safe;
		uint16_t neighborCount = call NeighborDiscovery.getNeighborCount();
		uint16_t *neighborIDs = call NeighborDiscovery.getNeighborIDs();
		uint16_t currentNodeId;
		destination_node currentNode;

		// flood LSA to all nodes on network
		pack packet;
		packet.src = TOS_NODE_ID;
		packet.dest = AM_BROADCAST_ADDR;
		packet.TTL = MAX_TTL;
		packet.seq = routingTableFloodSeq++;
		packet.protocol = PROTOCOL_LINKSTATE;
		packet.link_src = TOS_NODE_ID;

		memcpy(packet.payload, &lsa, sizeof(lsa));

		for (i = 0; i < neighborCount; i++)
		{
			error = call Sender.send(packet, neighborIDs[i]);

			if (error != SUCCESS)
			{
				dbg(GENERAL_CHANNEL, "Failed to initiate LSA flood to node %u\n", packet.src, packet.dest, neighborIDs[i]);
			}
		}

		if (routingTableFloodSeq % 4 != 0)
		{
			// only calculate the routing table every 4th LSA timer fire
			return;
		}

		call routingTable.reset();
		call unvisitedNodes.reset();

		// detect nodes on network from received edges
		for (i = 0; i < receivedLinks; ++i)
		{
			destination_node unvisited;
			unvisited.cost = ~0;
			call unvisitedNodes.insert(network_links[i].dest, unvisited);
			call unvisitedNodes.insert(network_links[i].src, unvisited);
		}

		// assign the known costs of our immediate neighbors
		currentNode.cost = ~0;
		for (i = 0; i < lsa.count; ++i)
		{
			destination_node node;
			// reliability = (lsa.reliability >> (i * 3)) & 0b111;
			node.nextHop = lsa.neighborIDs[i];
			/* 
			 node.cost = reliability + 1; // we treat unreliable links as multiple hops
 			 */
			node.cost = 1; // treat all links as equally expensive for now

			call unvisitedNodes.insert(lsa.neighborIDs[i], node);

			// select closest neighbor
			if (currentNode.cost > node.cost)
			{
				currentNode = node;
				currentNodeId = lsa.neighborIDs[i];
			}
		}

		// remove ourselves from the unvisited list
		call unvisitedNodes.remove(TOS_NODE_ID);

		/* 		
		 * Calculate the non-trivial paths using Dijkstra's algorithm

		 * we can't start the algorithm from the self node because we need
		 * access to an accurate nextHop field
 		 */
		fail_safe = 1000;
		while (call unvisitedNodes.size() > 0 && fail_safe-- > 0)
		{
			uint16_t unvisitedNodeCount;
			uint16_t *unvisitedNodeIDs;
			uint8_t leastCost = ~0;

			for (i = 0; i < receivedLinks && fail_safe-- > 0; ++i)
			{
				// neighbor of currentNode
				uint16_t neighborID;

				if (network_links[i].src == currentNodeId)
				{
					neighborID = network_links[i].dest;
				}
				else if (network_links[i].dest == currentNodeId)
				{
					neighborID = network_links[i].src;
				}
				else
				{
					// this edge doesn't touch the current node
					continue;
				}

				if (call unvisitedNodes.contains(neighborID))
				{
					uint8_t cost_through_current_node = currentNode.cost + network_links[i].cost;

					if ((call unvisitedNodes.get(neighborID)).cost > cost_through_current_node)
					{
						destination_node updated_node;
						updated_node.cost = cost_through_current_node;
						updated_node.nextHop = currentNode.nextHop;
						call unvisitedNodes.insert(neighborID, updated_node);
					}
				}
			}

			// move tentative node to confirmed node
			call unvisitedNodes.remove(currentNodeId);
			call routingTable.insert(currentNodeId, currentNode);
			// dbg(ROUTING_CHANNEL, "Confirming cost to node %u is %u\n", currentNodeId, currentNode.cost);

			// find next unvisited node with smallest tentative distance
			// if no nodes remain, then the while loop will terminate
			unvisitedNodeCount = call unvisitedNodes.size();
			unvisitedNodeIDs = call unvisitedNodes.getKeys();
			for (i = 0; i < unvisitedNodeCount && fail_safe-- > 0; ++i)
			{
				uint16_t nodeID = unvisitedNodeIDs[i];
				destination_node next_node = call unvisitedNodes.get(nodeID);
				if (next_node.cost < leastCost)
				{
					currentNode = next_node;
					currentNodeId = nodeID;
				}
			}
		}

		if (fail_safe == 0)
		{
			dbg(GENERAL_CHANNEL, "Unvisited nodes: %u \n", call unvisitedNodes.size());
		}

		receivedLinks = 0;
	}

	command message_t *RoutingTable.receive(message_t * raw_msg, void *payload, uint8_t len)
	{
		LinkState *lsa;
		uint16_t i, j;
		// uint8_t reliability;

		pack *packet = (pack *)payload;
		lsa = (LinkState*)packet->payload;

		// dbg(ROUTING_CHANNEL, "Received LSA from node %u seq %u with %u links\n", packet->src, packet->seq, lsa->count);

		// accumulate the network links into a list
		for (i = 0; i < lsa->count; ++i)
		{
			uint16_t lowID;
			uint16_t highID;
			bool isDuplicate = FALSE;

			if (receivedLinks >= MAX_LINKS_IN_NETWORK) {
				dbg(ROUTING_CHANNEL, "Exceeded allocated space for network links\n");
				break;
			}

			if (lsa->neighborIDs[i] == TOS_NODE_ID)
			{
				// ignore our neighbor telling us about ourselves
				continue;
			}

			lowID = lsa->neighborIDs[i];
			highID = packet->src;

			if (lowID > highID)
			{
				uint16_t temp = lowID;
				lowID = highID;
				highID = temp;
			}

			// reliability = (lsa->reliability >> (i*3)) & 0b111;

			// check if this is a duplicate link
			for (j = 0; j < receivedLinks; ++j)
			{
				if (network_links[j].src == lowID && network_links[j].dest == highID)
				{
					isDuplicate = TRUE;
				}
			}

			if (isDuplicate == FALSE)
			{
				network_links[receivedLinks].src = lowID;
				network_links[receivedLinks].dest = highID;
				network_links[receivedLinks].cost = 1; //reliability + 1,
				receivedLinks += 1;
			}
		}

		return raw_msg;
	}

	command void RoutingTable.print()
	{
		uint32_t i, j;
		uint16_t nodeCount = call routingTable.size();
		uint16_t *nodeIDs = call routingTable.getKeys();

		dbg(ROUTING_CHANNEL, "Node %u Routing Table\n", TOS_NODE_ID);
		dbg(ROUTING_CHANNEL, "Dest | Next | Cost\n");
		dbg(ROUTING_CHANNEL, "-----+------+-----\n");

		// print nodes in sorted order without sorting them
		for (i = 0; i <= nodeCount + 1; i++)
		{
			for (j = 0; j < nodeCount; j++)
			{
				uint16_t dest = nodeIDs[j];
				destination_node node = call routingTable.get(dest);

				if (dest == i)
				{
					dbg(ROUTING_CHANNEL, "%4u | %4u | %4u\n", dest, node.nextHop, node.cost);
				}
			}
		}
	}
}
