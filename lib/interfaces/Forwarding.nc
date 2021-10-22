#include "../../includes/packet.h"

interface Forwarding{
	command void start();
	command error_t send(pack* payload);
}
