interface RoutingTable{
	command void start();
	command void print();
	command uint16_t getNextHop(uint16_t dest);
	command message_t* receive(message_t* myMsg, void* payload, uint8_t len);
}
