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

// enable the "overheard" logs during flooding
// #define FLOOD_LOG_VERBOSE

// Constants
enum{
   NEIGHBOR_DISCOVERY_DELAY = 1000, ///< 1000ms, 1s
   MAX_NEIGHBOR_AGE         = 5,    ///< Neighbor is forgotten if it didn't reply to last 5 pings

   /**
    * Count of recent flood packs to remember.
    * 
    * Set to count of flood packets expected to be live in the network at once. For now, that is
    * two. One for the PING, and another for the PINGREPLY.
    */
   FLOOD_PACK_CACHE_SIZE = 2,    
};

typedef struct{
   uint16_t node_id;             ///< Node ID of neighbor
   uint16_t start_packet;        ///< Num packets sent when we found this neighbor
   uint16_t most_recent_packet;  ///< Most recent iteration we received a reply from this node
   uint16_t packets_rcvd;
} neighbor_t;

typedef struct{
   uint16_t src;   ///< Node ID of node initiating flood req
   uint16_t seq;  ///< Sequence of flood request (assumes a single node has one seq num for all flood reqs regardless of destination)
} flood_pack_t;

module Node{
   uses interface Boot;

   uses interface SplitControl as AMControl;
   uses interface Receive;

   uses interface SimpleSend as Sender;

   uses interface CommandHandler;

   uses interface List<neighbor_t> as neighborList;
   uses interface Timer<TMilli> as periodicTimer;
}

implementation{
   uint16_t ping_seq_num = 0;

   /*
    * assumes every node has a single incrementing seq num for all destination nodes
    *
    * assumes that not more than one floor req will pass its threshold over a given
    * node at a time. Breaking this assumption would result in the duplicate flood
    * req being detected as a new flood req. To fix this, just stash a small number (4)
    * of these entries in a circular buffer and check all entries instead of just 1.
    */
   flood_pack_t recent_flood_packets[FLOOD_PACK_CACHE_SIZE];
   uint8_t flood_pack_write_pos;

   // Prototypes
   void send_pack(uint16_t src, uint16_t dest, uint8_t TTL, uint8_t protocol, uint16_t seq, uint8_t* payload, uint8_t length);
   uint16_t swap_endianness(nx_uint16_t val);
   bool is_duplicate_msg(uint16_t src, uint16_t seq);
   void record_msg(uint16_t src, uint16_t seq);

   //Project 1 Prototypes
   uint16_t find_neighbor(uint16_t src);

   event void Boot.booted(){
      uint16_t i;
      flood_pack_t blank_pack;
      blank_pack.src = -1;
      blank_pack.seq = -1;

      for (i = 0; i < FLOOD_PACK_CACHE_SIZE; i++)
      {
         recent_flood_packets[i] = blank_pack;
      }

      flood_pack_write_pos = 0;

      call AMControl.start();

      // dbg(GENERAL_CHANNEL, "Booted\n");
   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");

         // Check for neighbors at regular intervals
         call periodicTimer.startPeriodic(NEIGHBOR_DISCOVERY_DELAY);
      }else{
         //Retry until successful
         call AMControl.start();
      }
   }

   event void periodicTimer.fired()
   {
      // dbg(NEIGHBOR_CHANNEL, "Node %u checking for neighbors\n", TOS_NODE_ID);

      uint16_t size = call neighborList.size();

      // loop backwards so removing a neighbor doesn't move list location for remaining neighbors
      uint16_t i;
      for (i = size-1; i != (uint16_t)~0; i--)
      {
         neighbor_t temp = call neighborList.get(i);
         
         // integer overflow expected and required for correctness
         uint16_t age = (ping_seq_num - temp.most_recent_packet);

         // Remove neighbors that we found more than MAX_NEIGHBOR_AGE iterations ago
         if (age > MAX_NEIGHBOR_AGE)
         {
            dbg(NEIGHBOR_CHANNEL, "Node[%u] %u over age %u\n", i, temp.node_id, MAX_NEIGHBOR_AGE);
            call neighborList.set(i, call neighborList.back());
            call neighborList.popback();
         }
      }

      // Ping all nodes in listening range asking for a ping reply
      send_pack(TOS_NODE_ID, AM_BROADCAST_ADDR, 1, PROTOCOL_PING, ping_seq_num, NULL, 0);
      ping_seq_num++;
   }

   event void AMControl.stopDone(error_t err){}

   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
      if(len==sizeof(pack)){
         pack* packet = (pack*)payload;
         uint16_t dest = packet->dest;
         uint16_t src = packet->src;
         uint16_t seq = packet->seq;
         uint8_t TTL = packet->TTL;
         uint8_t protocol = packet->protocol;

         dbg(GENERAL_CHANNEL, "Received{dest=%u,src=%u,seq=%u,TTL=%u,protocol=%u}\n", dest, src, seq, TTL, protocol);
         
         if (dest == AM_BROADCAST_ADDR)
         {
            uint16_t list_location;
            switch(protocol)
            {
               case PROTOCOL_PING:
                  // dbg(NEIGHBOR_CHANNEL, "Received neighbor discovery packet, responding to node %u\n", src);
                  send_pack(TOS_NODE_ID, AM_BROADCAST_ADDR, 1, PROTOCOL_PINGREPLY, seq, (uint8_t *) packet->payload, sizeof(packet->payload));
                  break;

               case PROTOCOL_PINGREPLY:
                  list_location = find_neighbor(src);
                  if (list_location == (uint16_t)-1)
                  {
                     // add new neighbor to list
                     neighbor_t new_neighbor;
                     new_neighbor.node_id            = src;
                     new_neighbor.start_packet       = ping_seq_num;
                     new_neighbor.most_recent_packet = ping_seq_num;
                     new_neighbor.packets_rcvd       = 1;
                     call neighborList.pushback(new_neighbor);
                  }
                  else
                  {
                     // refresh neighbor's age so they don't age out
                     neighbor_t neighbor = call neighborList.get(list_location);
                     neighbor.most_recent_packet = ping_seq_num;
                     neighbor.packets_rcvd++;
                     call neighborList.set(list_location, neighbor);
                  }
                  break;

               default:
                  break;
            }
         }
         else
         {
            // This is a flood packet, a msg meant for a specific node

            if (TOS_NODE_ID == src)
            {
               // we're the original sender. Ignore this msg
               return msg;
            }

            if (is_duplicate_msg(src, seq))
            {
               return msg;
            }

            record_msg(src, seq);

            if (dest == TOS_NODE_ID)
            {
               switch(protocol)
               {
                  case PROTOCOL_PING:
                     if (TTL != 0)
                     {
                        // Return acknowledgement to sender 
                        dbg(FLOODING_CHANNEL, "Sending PINGREPLY to node %u with seq %u\n", src, ping_seq_num);

                        /*
                        * Embed the sender's seq in the payload to match a PING to a PINGREPLY
                        *
                        * The duplicate msg rejection depends on every node only sending PING
                        * or PINGREPLY msgs with uniqueue incrementing seq.
                        */
                        send_pack(TOS_NODE_ID, src, MAX_TTL, PROTOCOL_PINGREPLY, ping_seq_num, (uint8_t *) &seq, sizeof(seq));
                        ping_seq_num++;
                     }
                     else
                     {
                        // If the TTL hit 0, then we can't send a PINGREPLY because the packet didn't have long enough to live
                        dbg(FLOODING_CHANNEL, "PING packet from %u w/ seq %u aged out, so can't reply\n", src, seq);
                     }
                     break;

                  case PROTOCOL_PINGREPLY:
                     // Received awknowledgement sent from the destination node
                     dbg(FLOODING_CHANNEL, "Received PINGREPLY from node %u\n", src);

                  default:
                     break;
               } 
            }
            else if (TTL != 0)
            {
               // We received a packet meant for someone else. Forward the msg to add neighbors with the TTL decremented
               send_pack(src, dest, TTL-1, protocol, seq, (uint8_t *)packet->payload, sizeof(packet->payload));

               #ifdef FLOOD_LOG_VERBOSE
               if (protocol == PROTOCOL_PING)
               {
                  dbg(FLOODING_CHANNEL, "Overheard PING from %u to %u w/ seq %u\n", src, dest, seq);
               }
               else if (protocol == PROTOCOL_PINGREPLY)
               {
                  dbg(FLOODING_CHANNEL, "Overheard PINGREPLY from %u to %u w/ seq %u\n", src, dest, seq);
               }
               #endif
            }
            else
            {
               dbg(FLOODING_CHANNEL, "PING from %u to %u w/ seq %u aged out\n", src, dest, seq);
            }
         }
         return msg;
      }
      else
      {
         dbg(GENERAL_CHANNEL, "Unknown Packet Type %u\n", len);
         return msg;
      }
   }


   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      dbg(GENERAL_CHANNEL, "Sending PING to node %u w/ seq %u \n", destination, ping_seq_num);
      send_pack(TOS_NODE_ID, destination, MAX_TTL, PROTOCOL_PING, ping_seq_num, payload, PACKET_MAX_PAYLOAD_SIZE);
      ++ping_seq_num;
   }

   event void CommandHandler.printNeighbors(){
      uint16_t i;

      dbg(NEIGHBOR_CHANNEL, "List of active neighbors:\n");
      dbg(NEIGHBOR_CHANNEL, "Node | Age \n");
      dbg(NEIGHBOR_CHANNEL, "-----+-----\n");

      for (i = call neighborList.size() - 1; i != (uint16_t)~0; i--)
      {
         neighbor_t temp;
         uint16_t age;
         // uint16_t sent;
         // uint16_t quality;

         temp = call neighborList.get(i);
         age = (ping_seq_num - temp.most_recent_packet);
         // sent = (ping_seq_num - temp.start_packet);
         // quality = ((uint32_t)sent * 100) / temp.packets_rcvd;

         dbg(NEIGHBOR_CHANNEL, "%4u | %3u\n", temp.node_id, age);
      }
   }

   event void CommandHandler.printRouteTable(){}

   event void CommandHandler.printLinkState(){}

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer(){}

   event void CommandHandler.setTestClient(){}

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}

   void send_pack(uint16_t src, uint16_t dest, uint8_t TTL, uint8_t protocol, uint16_t seq, uint8_t* payload, uint8_t length)
   {
      pack packet;
      packet.src = src;
      packet.dest = dest;
      packet.TTL = TTL;
      packet.seq = seq;
      packet.protocol = protocol;

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
      call Sender.send(packet, AM_BROADCAST_ADDR);
   }

   uint16_t find_neighbor(uint16_t src)
   {
      uint16_t size = call neighborList.size();
      uint16_t i;
      for (i = 0; i < size; i++)
      {
         neighbor_t temp = call neighborList.get(i);
         if(temp.node_id == src)
         {
            return i;
         }
      }

      return -1;
   }

   bool is_duplicate_msg(uint16_t src, uint16_t seq)
   {
      uint8_t i;
      for (i = 0; i < FLOOD_PACK_CACHE_SIZE; i++)
      {
         if (recent_flood_packets[i].src == src)
         {
            // We've seen a flood packet from this node recently. Check if we already sent it
            int16_t age = seq - recent_flood_packets[i].seq;

            /*
            * We've seen this flood packet before because it was the most recent one we sent.

            * This creates a sort of wave cancelation effect at the fronteir of a flood req
            * causing a flood msg going down two paths to cancel itself out if it attempts
            * to go backwards through a network loop.
            * 
            * e.g. node 1 sends flood msg with seq 0
            * 
            *    -> 2 -----
            * 1 -          -> 5
            *    -> 3 -> 4-
            * 
            * When the flood msg from 1 reaches 5, 5 will rebroadcast it to 2 and 4. 2 and 4
            * won't repeat the msg because the most recent flood msg they sent was the one from
            * node 0 for seq 0. None of the nodes will send any more flood msgs for node 1 until it
            * increments its sequence number indicating the next flood msg.
            *
            * If we want to detect up to x flood msgs concurrently in a network, then replace
            * the single entry with a small circular buffer x entries long.
            *
            * We've found a duplicate flood msg, so drop it
            */
            if (age <= 0)
            {
               return TRUE;
            }
         }
      }

      return FALSE;
   }

   void record_msg(uint16_t src, uint16_t seq)
   {
      recent_flood_packets[flood_pack_write_pos].src = src;
      recent_flood_packets[flood_pack_write_pos].seq = seq;
      flood_pack_write_pos = (flood_pack_write_pos + 1) % FLOOD_PACK_CACHE_SIZE;
   }
}