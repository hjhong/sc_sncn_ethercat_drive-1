/**
 * @file canopen_service.xc
 * @brief CANopen service between communication channels and CANopen drive.
 * @author Synapticon GmbH <support@synapticon.com>
*/

#include <stdint.h>
#include <string.h>

#include "canod.h"
#include "co_interface.h"
#include "dictionary_symbols.h"
#include "canopen_interface_service.h"
#include "pdo_handler.h"
#include "print.h"

#define MAX_PDO_SIZE 64

[[distributable]]
void canopen_interface_service(server interface i_co_communication i_co[n], unsigned n)
{
    pdo_values_t InOut = pdo_init_data();
    pdo_size_t pdo_buffer[MAX_PDO_SIZE];
    char comm_state = 0;

    int configuration_done = 0;

    printstrln("SOMANET CANOPEN SERVICE STARTING...");

    while (1)
    {
        select
        {
            /* PDO */

            case i_co[int j].pdo_in(uint8_t pdo_number, unsigned int size_in, pdo_size_t data_in[]):
                unsigned pdo_size = size_in;
                memcpy(pdo_buffer, data_in, pdo_size * sizeof(pdo_size_t));
                pdo_decode(pdo_number, pdo_buffer, InOut);
                comm_state = 1;
                break;

            case i_co[int j].pdo_out(uint8_t pdo_number, pdo_size_t data_out[]) -> { unsigned int size_out }:
                unsigned pdo_size = pdo_encode(pdo_number, pdo_buffer, InOut);
                memcpy(data_out, pdo_buffer, pdo_size * sizeof(pdo_size_t));
                size_out = pdo_size;
                break;

            case i_co[int j].pdo_exchange_app(pdo_values_t pdo_out) -> { pdo_values_t pdo_in, unsigned int status_out }:
                pdo_exchange(InOut, pdo_out, pdo_in);
                status_out = comm_state;
                comm_state = 0;
                break;

            case i_co[int j].pdo_init(void) -> {pdo_values_t pdo_out}:
                pdo_out = pdo_init_data();
                break;


            /* SDO */

            case i_co[int j].od_get_access(uint16_t index_, uint8_t subindex) -> { uint8_t access, uint8_t error }:
                    {access, error}  = canod_get_access(index_, subindex);
                    break;

            case i_co[int j].od_get_object_value(uint16_t index_, uint8_t subindex) -> { uint32_t value_out, uint32_t bitlength_out, uint8_t error_out }:
                    unsigned bitlength = 0;
                    unsigned value = 0;
                    error_out = canod_get_entry(index_, subindex, value, bitlength);
                    bitlength_out = bitlength;
                    value_out = value;
                    break;

            case i_co[int j].od_set_object_value(uint16_t index_, uint8_t subindex, uint32_t value) -> { uint8_t error_out }:
                    error_out = canod_set_entry(index_, subindex, value, 1);
                    break;

            case i_co[int j].od_get_object_value_buffer(uint16_t index_, uint8_t subindex, uint8_t data_buffer[]) -> { uint32_t bitlength_out, uint8_t error_out }:
                    unsigned bitlength = 0;
                    unsigned value = 0;
                    unsigned error = 0;
                    error = canod_get_entry(index_, subindex, value, bitlength);
                    if (error > 0)
                    {
                        error_out = error;
                        bitlength_out = 0;
                    }
                    else
                    {
                        bitlength_out = bitlength;
                        for (unsigned i = 0; i < (bitlength/8); i++) {
                            data_buffer[i] = (value >> (i*8)) & 0xff;
                        }
                    }
                    break;

            case i_co[int j].od_set_object_value_buffer(uint16_t index_, uint8_t subindex, uint8_t data_buffer[]) -> { uint8_t error_out }:
                    unsigned byte_len, error = 0;
                    unsigned value = 0;

                    {byte_len, error} = canod_find_data_length(index_, subindex);

                    if (error > 0)
                    {
                        error_out = error;
                    }
                    else
                    {
                        for (unsigned i = 0; i < byte_len; i++) {
                            value |= (unsigned) data_buffer[i] << (i*8);
                        }
                        error_out = canod_set_entry(index_, subindex, value, 1);
                    }
                    break;


            case i_co[int j].od_get_entry_description(uint16_t index_, uint8_t subindex, uint32_t valueinfo) -> { struct _sdoinfo_entry_description desc_out, uint8_t error_out }:
                    struct _sdoinfo_entry_description desc;
                    error_out = canod_get_entry_description(index_, subindex, valueinfo, desc);
                    desc_out = desc;
                    break;

            case i_co[int j].od_get_all_list_length(uint32_t list_out[]):
                    unsigned list[5];
                    canod_get_all_list_length(list);
                    memcpy(list_out, list, 5 * sizeof(unsigned));
                    break;

            case i_co[int j].od_get_list(unsigned list_out[], unsigned size, unsigned listtype) -> {int size_out}:
                    unsigned list[100];
                    size_out = canod_get_list(list, 100, listtype);
                    memcpy(list_out, list, size_out * sizeof(unsigned));
                    break;

            case i_co[int j].od_get_object_description(struct _sdoinfo_entry_description &obj_out, uint16_t index_, uint8_t subindex) -> { int error }:
                    struct _sdoinfo_entry_description obj;
                    error = canod_get_object_description(obj, index_, subindex);
                    obj_out = obj;
                    break;

            case i_co[int j].od_get_data_length(uint16_t index_, uint8_t subindex) -> {uint32_t len, uint8_t error}:
                    {len, error} = canod_find_data_length(index_, subindex); // return value: count of byte
                    break;

            case i_co[int j].inactive_communication(void):
                    comm_state = 0;
                    break;


            /* Simple notification interface */

            case i_co[int j].configuration_ready(void):
                    configuration_done = 1;
                    break;

            case i_co[int j].configuration_get(void) -> { int value }:
                    value = configuration_done;
                    break;

            case i_co[int j].configuration_done(void):
                    configuration_done = 0;
                    break;
        }
    }
}
