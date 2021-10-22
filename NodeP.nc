/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"

module NodeP{
   uses interface Boot;

   uses interface SplitControl as AMControl;

   uses interface NeighborDiscovery;
   uses interface RoutingTable;
   uses interface Forwarding;
   uses interface CommandHandler;

   provides interface Node;
}

implementation{
   uint16_t ping_seq_num = 0;

   // Prototypes
   void send_pack(uint16_t src, uint16_t dest, uint8_t TTL, uint8_t protocol, uint16_t seq, uint8_t * payload, uint8_t length);

   event void Boot.booted(){
      call AMControl.start();

      // dbg(GENERAL_CHANNEL, "Booted\n");
   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         // dbg(GENERAL_CHANNEL, "Radio On\n");

         call Forwarding.start();
      }else{
         //Retry until successful
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}

   command message_t* Node.receive(message_t* msg, void* payload, uint8_t len){
      /*       
       * destination must equal TOS_NODE_ID or else the forwarding layer
       * wouldn't have given us this packet
       */

      // dbg(GENERAL_CHANNEL, "Packet Received\n");
      if(len==sizeof(pack)){
         pack* packet=(pack*) payload;
         // dbg(GENERAL_CHANNEL, "Package Payload: %s\n", packet->payload);

         if (packet->protocol == PROTOCOL_PING)
			{
            dbg(GENERAL_CHANNEL, "Sending PINGREPLY to node %u w/ seq %u \n", packet->src, ping_seq_num);
            send_pack(TOS_NODE_ID,  packet->src, MAX_TTL, PROTOCOL_PINGREPLY, ping_seq_num, NULL, 0);
            ++ping_seq_num;
			}
         else if (packet->protocol == PROTOCOL_PINGREPLY)
			{
				dbg(GENERAL_CHANNEL, "Got PINGREPLY back from node %u\n", packet->src);
			}
			else
			{
            dbg(GENERAL_CHANNEL, "Unexpected protocol %u\n", packet->protocol);
			}

         return msg;
      }
      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }


   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      dbg(GENERAL_CHANNEL, "Sending PING to node %u w/ seq %u \n", destination, ping_seq_num);
      send_pack(TOS_NODE_ID, destination, MAX_TTL, PROTOCOL_PING, ping_seq_num, payload, PACKET_MAX_PAYLOAD_SIZE);
      ++ping_seq_num;
   }

   event void CommandHandler.printNeighbors()
   {
      // dbg(GENERAL_CHANNEL, "CommandHandler.printNeighbors() \n");
      call NeighborDiscovery.print();
   }

   event void CommandHandler.printRouteTable()
   {
      dbg(GENERAL_CHANNEL, "CommandHandler.printRouteTable() \n");
      call RoutingTable.print();
   }

   event void CommandHandler.printLinkState(){}

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer(){}

   event void CommandHandler.setTestClient(){}

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}

   void send_pack(uint16_t src, uint16_t dest, uint8_t TTL, uint8_t protocol, uint16_t seq, uint8_t * payload, uint8_t length)
   {
      pack packet;
      packet.src = src;
      packet.dest = dest;
      packet.TTL = TTL;
      packet.seq = seq;
      packet.protocol = protocol;
      packet.link_src = TOS_NODE_ID;

      if (length > sizeof(packet.payload))
      {
         // drop packets that have too large of a payload
         dbg(GENERAL_CHANNEL, "Payload size %u exceeded max payload size %u\n", length, sizeof(packet.payload));
         return;
      }

      if (payload != NULL && length > 0)
      {
         memcpy(packet.payload, payload, length);
      }

      // dbg(GENERAL_CHANNEL, "Sending{dest=%u,src=%u,seq=%u,TTL=%u,protocol=%u}\n", dest, src, seq, TTL, protocol);
      call Forwarding.send(&packet);
   }
}