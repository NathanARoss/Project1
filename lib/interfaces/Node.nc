#include "../../includes/packet.h"

interface Node{
	command message_t* receive(message_t* myMsg, void* payload, uint8_t len);
}
