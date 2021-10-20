/**
 * ANDES Lab - University of California, Merced
 * This moudle provides a simple hashmap.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include "../../includes/channels.h"
generic module HashmapC(typedef t, uint16_t n){
   provides interface Hashmap<t>;
}

implementation{
   uint16_t HASH_MAX_SIZE = n;

   // This index is reserved for empty values.
   uint16_t EMPTY_KEY = ~0;

   typedef struct hashmapEntry{
      uint16_t key;
      t value;
   }hashmapEntry;

   hashmapEntry map[n];
   uint16_t keys[n];
   uint16_t count;

   command void Hashmap.reset(){
      uint16_t i;

      // drop the key list
      count = 0;

      // zero out entry keys so slots appear as empty
      for (i = 0; i < HASH_MAX_SIZE; i++) {
         map[i].key = EMPTY_KEY;
      }
   }

   // Hashing Functions
   uint16_t hash2(uint16_t key){
      return key%13;
   }
   uint16_t hash3(uint16_t key){
      return 1+key%11;
   }

   uint16_t hash(uint16_t key, uint16_t i){
      return (hash2(key)+ i*hash3(key))%HASH_MAX_SIZE;
   }

   command void Hashmap.insert(uint16_t key, t input){
      uint16_t i, j;

      if(key == EMPTY_KEY){
          dbg(HASHMAP_CHANNEL, "[HASHMAP] You cannot insert a key of %d.", EMPTY_KEY);
          return;
      }

      for(i = 0; i < HASH_MAX_SIZE; ++i){
         // Generate a hash.
         j=hash(key, i);

         // Check to see if the key is free or if we already have a value located here.
         if(map[j].key==EMPTY_KEY || map[j].key==key){
             // If the key is empty, we can add it to the list of keys and increment
             // the total number of values we have..
            if(map[j].key==EMPTY_KEY){
               keys[count]=key;
               count++;
            }

            // Assign key and input.
            map[j].value=input;
            map[j].key = key;
            return;
         }
      // This will allow a total of HASH_MAX_SIZE misses. It can be greater,
      // BUt it is unlikely to occur.
      }
   }


	// We keep an internal list of all the keys we have. This is meant to remove it
   // from that internal list.
   void removeFromKeyList(uint16_t key){
      uint16_t i;
      dbg(HASHMAP_CHANNEL, "Removing entry %d\n", key);
      for(i=0; i<count; i++){
          // Once we find the key we are looking for, we can begin the process of
          // shifting all the values to the left. e.g. [1, 2, 3, 4, 0] key = 2
          // the new internal list would be [1, 3, 4, 0, 0];
         if(keys[i]==key){
            dbg(HASHMAP_CHANNEL, "Key found at %d\n", i);

            // move the key from the end into the gap where the removed key was
            count--;
            keys[i] = keys[count];

            dbg(HASHMAP_CHANNEL, "Done removing entry\n");
            return;
         }
      }

   }


   command void Hashmap.remove(uint16_t key){
      uint16_t i, j;
      for(i = 0; i < HASH_MAX_SIZE; ++i){
         j=hash(key, i);
         if(map[j].key == key){
            map[j].key=0;
            removeFromKeyList(key);
            break;
         }
      }
   }

   
   command t Hashmap.get(uint16_t key){
      uint16_t i, j;
      for(i = 0; i < HASH_MAX_SIZE; ++i){
         j=hash(key, i);
         if(map[j].key == key)
            return map[j].value;
      }

      // We have to return something so we return the first key
      return map[0].value;
   }

   command bool Hashmap.contains(uint16_t key){
      uint16_t i, j;
      /*
      if(key == EMPTY_KEY)
      {
         return FALSE;
      }
      */
      for(i = 0; i < HASH_MAX_SIZE; ++i){
         j=hash(key, i);
         if(map[j].key == key)
            return TRUE;
      }
      return FALSE;
   }

   command bool Hashmap.isEmpty(){
      return (count==0);
   }

   command uint16_t* Hashmap.getKeys(){
      return keys;
   }

   command uint16_t Hashmap.size(){
      return count;
   }
}
