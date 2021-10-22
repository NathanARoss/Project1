/*
 * This is the LinkState Advertisement (LSA) information flooded by each node
 * during the routing table build event.
 *
 * The struct is a length-prefixed list of neighbors. Each neighbor entry has
 * a node ID (dest) and a cost to visit that node from the node that sent
 * the LSA. The source node ID is taken from the source of the flood message.
 */

#ifndef LINKSTATE_H
#define LINKSTATE_H

typedef nx_struct {
    /**
     * The reliability of the link to each neighbor.
     *
     * 3-bit reliability scores per neighbor are stored separately from each
     * entry to allow the neighbor node IDs to be the full 2^16 range of values,
     * to be memory access aligned, and to keep the list compact. This entire
     * struct must fit within the 16 byte payload allowed by the pack struct.
     *
     * The first neighbor in the list has its cost stored in the lowest 3 bits,
     * the second neighbor has the next-highest 3 bits, and so on.
     *
     * Reliability for each neighbor is in the range of [0, 7]. It represents
     * the availability of the node expressed as alpha^cost, where alpha is some
     * ratio close to 99% defined at compile time. The idea is that an equal
     * reliability score of a single node and a score accumulated over a series
     * of links indicates the same probability of dropping a message.
     * 
     * i.e. a single link has a score of 6, so it has a 0.99^6 = 94.1% chance of
     * dropping a message. A series of three links with scores 1, 2, and 3 have
     * the same 0.99^1 * 0.99^2 * 0.99^3 = 0.99^6 = 94.1% chance of dropping
     * a message.
     * 
     * A neighbor will not appear in this list if the link reliability is
     * below alpha^7 == 92%.
     * 
     * This implementation assumes an equal bandwidth and delay for all links
     * in the network because this project only tests nodes going offline.
     */
    nx_uint32_t reliability : 24;

    /// reserved for future use
    nx_uint32_t reserved : 5;

    /// count of neighbors in this list (zero-based) [1, 6]
    nx_uint32_t count : 3;

    nx_uint16_t neighborIDs[6];
} LinkState;

// sizeof(LinkState) == PACKET_MAX_PAYLOAD_SIZE == 16

#endif