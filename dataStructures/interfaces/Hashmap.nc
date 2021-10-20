/**
 * ANDES Lab - University of California, Merced
 * This is an interface for Hashmaps.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 * 
 */

interface Hashmap<t>{
   command void reset();
   command void insert(uint16_t key, t input);
   command void remove(uint16_t key);
   command t get(uint16_t key);
   command bool contains(uint16_t key);
   command bool isEmpty();
   command uint16_t size();
   command uint16_t * getKeys();
}
