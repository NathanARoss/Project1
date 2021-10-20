#include "../../includes/channels.h"
#include "../../includes/protocol.h"
#include "../../includes/packet.h"

#define HISTORY_SIZE 32

module FloodingP
{
	uses interface SimpleSend as Sender;

	provides interface Flooding;
}

implementation
{
	typedef struct
	{
		uint16_t src;
		uint16_t seq;
	} history_t;

	uint16_t flood_seq = 0;
	uint16_t historyWritePos = 0;
	history_t floodHistory[HISTORY_SIZE];

	bool hasSeenFloodPacket(uint16_t src, uint16_t seq)
	{
		uint32_t i;
		for (i = 0; i < HISTORY_SIZE; i++)
		{
			if (src == floodHistory[i].src && seq == floodHistory[i].seq)
			{
				return TRUE;
			}
		}
		return FALSE;
	}

	void recordFloodPacket(uint16_t src, uint16_t seq)
	{
		floodHistory[historyWritePos] = (history_t){
			.src = src,
			.seq = seq
		};

		historyWritePos = (historyWritePos + 1) % HISTORY_SIZE;
		return;
	}

	command message_t *Flooding.receive(message_t * raw_msg, void *payload, uint8_t len)
	{
		pack *msg = (pack *)payload;
		dbg(FLOODING_CHANNEL, "Received flooding packet %s \n", msg->payload);

		// this function is called if dest == AM_BROADCAST_ADDR

		if (hasSeenFloodPacket(msg->src, msg->seq))
		{
			return raw_msg;
		}

		recordFloodPacket(msg->src, msg->seq);

		if (msg->TTL == 0)
		{
			dbg(FLOODING_CHANNEL, "Flooding packet from node %u expired \n", msg->src);
			return raw_msg;
		}

		msg->TTL -= 1;
		// call Sender.send(*msg, AM_BROADCAST_ADDR);
		dbg(FLOODING_CHANNEL, "Flooding node %u's LSA packet #%u \n", msg->src, msg->seq);

		return raw_msg;
	}
}
