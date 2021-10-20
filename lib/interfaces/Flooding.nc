#include "../../includes/packet.h"

interface Flooding{
	command message_t* receive(message_t* myMsg, void* payload, uint8_t len);
}
