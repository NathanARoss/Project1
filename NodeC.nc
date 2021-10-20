/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */

#include <Timer.h>
#include "includes/CommandMsg.h"
#include "includes/packet.h"

configuration NodeC{
    provides interface Node;
}

implementation {
    components MainC;
    components NodeP;

    NodeP -> MainC.Boot;

    Node = NodeP.Node;

    components ActiveMessageC;
    NodeP.AMControl -> ActiveMessageC;

    components CommandHandlerC;
    NodeP.CommandHandler -> CommandHandlerC;

	components NeighborDiscoveryC;
	NodeP.NeighborDiscovery -> NeighborDiscoveryC.NeighborDiscovery;

	components RoutingTableC;
	NodeP.RoutingTable -> RoutingTableC.RoutingTable;

	components ForwardingC;
	NodeP.Forwarding -> ForwardingC.Forwarding;

}
