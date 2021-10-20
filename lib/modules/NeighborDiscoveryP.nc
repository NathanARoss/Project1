// Module
#include "../../includes/channels.h"
#include "../../includes/protocol.h"
#include "../../includes/packet.h"

enum
{
	/// ping our neighbors once a second to make sure they are still there
	NEIGHBOR_DISCOVERY_DELAY_MS = 1000,

	/**
	 * Weighted average of link reliability for neighbors. The most recent ping
	 * is given a weight representing 1/16th of the sample size.
	 * 
	 * alpha = (2**16 - 2**12) / 2**16 = 93.75% decay rate
	 * 
	 * Rate reliability scores delay with a single missed ping (1 second). A
	 * neighbor that hasn't replied to the most recent ping has a reliability
	 * score no higher than 93.75%.
	 *
	 * alpha^1 * (2**16)
	 */
	RELIABILITY_SCORE_DECAY = 0xF000,

	/**
	 * Score value added back when a neighbor node sends back an awk
	 *
	 * (1 - alpha), since reliability *= alpha on every discovery iteration
	 */
	RELIABILITY_HIT_SCORE = 0xFFFF - RELIABILITY_SCORE_DECAY,

	/*
	 * Neighbors lose a ping's worth of reliability every second, so give
	 * neighbors the benefit of the doubt that it'll awk the most recent ping.
	 *
	 * Reliability scores corresponding to N missed pings in a row.
	 */
	RELIABILITY_SCORE_0_THRESHOLD = 0XF000, /// alpha^1 * (2**16) == 93.75%
	RELIABILITY_SCORE_1_THRESHOLD = 0XE100, /// alpha^2 * (2**16) == 87.89%
	RELIABILITY_SCORE_2_THRESHOLD = 0XD2F0, /// alpha^3 * (2**16) == 82.40%
	RELIABILITY_SCORE_3_THRESHOLD = 0XC5C1, /// alpha^4 * (2**16) == 77.25%
	RELIABILITY_SCORE_4_THRESHOLD = 0XB964, /// alpha^5 * (2**16) == 72.42%
	RELIABILITY_SCORE_5_THRESHOLD = 0XADCE, /// alpha^6 * (2**16) == 67.90%
	RELIABILITY_SCORE_6_THRESHOLD = 0XA2F1, /// alpha^7 * (2**16) == 63.65%
	RELIABILITY_SCORE_7_THRESHOLD = 0X98C2, /// alpha^8 * (2**16) == 59.67%

	/*
	 * Initial reliability score when a neighbor is first found.
	 *
	 * A neighbor shouldn't be included in LSA packets until it has awked
	 * the last 5 neighbor pings. It's not considered perfectly reliable until
	 * ~35 pings.
	 *
	 * alpha^12 * (2**16) == 46.1%
	 * 
	 * after 5 sucessful ping replies from a new node: 60.96% - score 7
	 * after 20 successful ping replies: 85.17% - score 2
	 * after 34 successful ping replies: 93.99% - score 0
	 */
	RELIABILITY_SCORE_NEW_NEIGHBOR = 0x7600,

	/*
	 * Reliability score below which a neighbor is forgotten.

	 * When a neighbor is heard from, it immediately adds (1-alpha) == 6.25% to
	 * the reliability score. A nearly dead node takes 77 dropped pings after a
	 * successful ping reply to fall below this cutoff and be forgotten.
	 *
	 * This is the score a perfectly healthy neighbor would receive once it
	 * stops replying to pings for 2 minutes (120 pings). The purpose of
	 * forgetting neighbors is to free up room in the neighbor list if a new
	 * node comes up to replace an old one and to allow nodes to have a 2nd
	 * chance at reliability if they go down for maintenance. Don't forget nodes
	 * that stop responding too quickly because we could mistakenly give a node
	 * that replies once every 30 seconds too high of a reliability score due
	 * to score resetting.
	 * 
	 * alpha^120 * (1**16) (0.043% reliability)
	 */
	RELIABILITY_SCORE_FORGET_THRESHOLD = 0x1C,
};

typedef struct
{
	uint16_t dest;
	uint16_t reliability;
} neighbor_t;

module NeighborDiscoveryP
{
	// uses interface
	uses interface Timer<TMilli> as neighborDiscoveryTimer;
	uses interface Hashmap<uint16_t> as neighborTable;
	uses interface SimpleSend as Sender;

	provides interface NeighborDiscovery;
}

implementation
{
	uint16_t neighborDiscoverySeqNum = 0;

	void send_pack(uint16_t src, uint16_t dest, uint8_t TTL, uint8_t protocol, uint16_t seq);

	/*
	 * Reduce a neighbor's reliability score in anticipation they won't reply
	 */
	void ageNeighbor(uint16_t nodeID)
	{
		uint16_t reliability;
		reliability = call neighborTable.get(nodeID);

		/*
		 * Reduce the neighbor's reliability as if it didn't respond to this
		 * ping. If the neighbor does awk, then add the missing score back.
		 *
		 * reliability *= 0.99, but using an imul then right shift
		 */
		reliability = (uint16_t)(((uint32_t)reliability * RELIABILITY_SCORE_DECAY) >> 16);

		if (reliability < RELIABILITY_SCORE_FORGET_THRESHOLD)
		{
			// forget nodes that are haven't replied in ages
			call neighborTable.remove(nodeID);
		}
		else
		{
			// update reliability score of reasonably reliable neighbors
			call neighborTable.insert(nodeID, reliability);
		}
	}

	/*
	 * Call ageNeighbor on all known neighbors
	 */
	void ageNeighbors()
	{
		uint16_t neighborCount;
		uint16_t *neighborIDs;
		uint16_t i = 0;

		neighborCount = call neighborTable.size();
		neighborIDs = call neighborTable.getKeys();

		for (i = 0; i < neighborCount; ++i)
		{
			uint16_t neighborID = neighborIDs[i];
			ageNeighbor(neighborID);
		}
	}

	/*
	 * Add to a neighbor's reliability score if they are already known, or add
	 * them to the list if they are new.
	 */
	void rejuvenateNeighbor(uint16_t nodeID)
	{
		uint16_t reliability;

		if (call neighborTable.contains(nodeID))
		{
			reliability = call neighborTable.get(nodeID);

			// Give this neighbor credit for replying to the ping
			reliability += RELIABILITY_HIT_SCORE;
		}
		else
		{
			// if we've not seen this neighbor before, then assign a default score
			reliability = RELIABILITY_SCORE_NEW_NEIGHBOR;
		}

		call neighborTable.insert(nodeID, reliability);
	}

	uint8_t encodeReliability(uint16_t reliability)
	{
		if (reliability > RELIABILITY_SCORE_0_THRESHOLD)
		{
			return 0;
		}
		else if (reliability > RELIABILITY_SCORE_1_THRESHOLD)
		{
			return 1;
		}
		else if (reliability > RELIABILITY_SCORE_2_THRESHOLD)
		{
			return 2;
		}
		else if (reliability > RELIABILITY_SCORE_3_THRESHOLD)
		{
			return 3;
		}
		else if (reliability > RELIABILITY_SCORE_4_THRESHOLD)
		{
			return 4;
		}
		else if (reliability > RELIABILITY_SCORE_5_THRESHOLD)
		{
			return 5;
		}
		else if (reliability > RELIABILITY_SCORE_6_THRESHOLD)
		{
			return 6;
		}
		else if (reliability > RELIABILITY_SCORE_7_THRESHOLD)
		{
			return 7;
		}
		else
		{
			return ~0;
		}
	}

	command LinkState NeighborDiscovery.getOwnLinkstate()
	{
		// LinkState Advertisement to flood out
		LinkState lsa;
		uint16_t neighborCount;
		uint16_t *neighborIDs;
		uint16_t i = 0;
		uint8_t count = 0;
		uint16_t reliability;
		uint16_t score;

		neighborCount = call neighborTable.size();
		neighborIDs = call neighborTable.getKeys();

		for (i = 0; i < neighborCount; ++i)
		{
			uint16_t neighborID = neighborIDs[i];

			if (TOS_NODE_ID > neighborID)
			{
				/* 				
				 * only advertise nodes with a larger node ID so every link
				 * is mentioned in only a single LSA packet.
				 */
				continue;
			}

			reliability = call neighborTable.get(neighborID);
			score = encodeReliability(reliability);

			// if a node stops replying for 7 seconds, then don't list it
			if (score < 8)
			{
				if (count >= 8)
				{
					dbg(NEIGHBOR_CHANNEL, "node has more than 8 live neighbors, so returning only first 8 \n", count);
					break;
				}

				lsa.neighborIDs[count] = neighborID;
				lsa.reliability |= score << (count * 3);
				count++;
			}
		}

		// record how many of the entries we filled out
		lsa.count = count;
		return lsa;
	}

	command void NeighborDiscovery.start()
	{
		dbg(NEIGHBOR_CHANNEL, "Starting Neighbor Discovery \n");
		call neighborTable.reset();
		call neighborDiscoveryTimer.startPeriodic(NEIGHBOR_DISCOVERY_DELAY_MS);
	}

	command void NeighborDiscovery.print()
	{
		uint16_t neighborCount;
		uint16_t *neighborIDs;
		uint16_t i = 0;
		dbg(NEIGHBOR_CHANNEL, "Printing neighbors of %u:\n", TOS_NODE_ID);

		neighborCount = call neighborTable.size();
		neighborIDs = call neighborTable.getKeys();

		for (i = 0; i < neighborCount; ++i)
		{
			uint16_t neighborID = neighborIDs[i];

			uint16_t reliability = call neighborTable.get(neighborID);
			uint8_t percentage = ((uint32_t)reliability * 1000) >> 16;

			dbg(NEIGHBOR_CHANNEL, "Node %u - reliability %3u.%u:\n", TOS_NODE_ID, percentage / 10, percentage % 10);
		}
	}

	event void neighborDiscoveryTimer.fired()
	{

		dbg(NEIGHBOR_CHANNEL, "Sending Neighbor Packet\n");

		send_pack(TOS_NODE_ID, AM_BROADCAST_ADDR, 0, PROTOCOL_NEIGHBOR_DISCOVERY, neighborDiscoverySeqNum++);
		ageNeighbors();
	}

	command message_t *NeighborDiscovery.receive(message_t * myMsg, void *payload, uint8_t len)
	{
		pack *msg = (pack *)payload;
		dbg(NEIGHBOR_CHANNEL, "NeighborDiscovery got Packet\n");

		if (msg->dest == AM_BROADCAST_ADDR)
		{
			send_pack(TOS_NODE_ID, msg->src, 0, PROTOCOL_NEIGHBOR_DISCOVERY, neighborDiscoverySeqNum++);
		}
		if (msg->dest == TOS_NODE_ID)
		{
			rejuvenateNeighbor(msg->src);
		}
		return myMsg;
	}

	void send_pack(uint16_t src, uint16_t dest, uint8_t TTL, uint8_t protocol, uint16_t seq)
	{
		pack packet;
		packet.src = src;
		packet.dest = dest;
		packet.TTL = TTL;
		packet.seq = seq;
		packet.protocol = protocol;

		//   dbg(GENERAL_CHANNEL, "Sending{dest=%u,seq=%u,TTL=%u}\n", dest, seq, TTL);
		call Sender.send(packet, AM_BROADCAST_ADDR);
	}
}
