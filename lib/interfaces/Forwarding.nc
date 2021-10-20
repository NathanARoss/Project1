#include "../../includes/packet.h"

interface Forwarding{
	command error_t send(pack msg, uint16_t dest);
}
